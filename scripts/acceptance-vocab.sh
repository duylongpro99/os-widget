#!/usr/bin/env bash
# Checks the deployed vocabulary feature against its acceptance criteria.
#
# Usage: PUBLISH_TOKEN=... CLIENT_TOKEN=... SUPABASE_DB_URL=... \
#          scripts/acceptance-vocab.sh <worker-url> [criterion ...]
#
# Criteria (all four when none is named):
#   2. Ingesting a word list through the dictionary API stores the complete words,
#      skips the incomplete one, and ingesting again creates no duplicate.
#   3. Ingesting a book stores words whose context is a sentence from the book.
#   4. Changing vocab_interval_minutes takes effect without a deploy. Changes the
#      live setting for about 35 minutes and restores it, also when stopped early.
#   5. Running out of words stops or rotates as configured, and never sends an
#      empty item: the local pgTAP suite (`supabase test db`, starting and
#      stopping a local stack when none runs) plus read-only checks on the live
#      settings and vocab items.
#
# Environment:
#   PUBLISH_TOKEN    criteria 2 and 3 (the CLI sends words with it)
#   CLIENT_TOKEN     criterion 4 (reads GET /events)
#   SUPABASE_DB_URL  connection URI of the project (user, password, host, port, db);
#                    needed by 3, 4 and 5, optional for 2 (without it the
#                    no-duplicate check relies on the CLI's stored count)
#   VOCAB_WHEN_EXHAUSTED  the decided vocab_when_exhausted value (default rotate)
#
# Words stored by criteria 2 and 3 are real words and stay; their origin starts
# with "acceptance". Prints PASS or FAIL per criterion and exits 1 if any failed.
# Tokens and the database password are never printed: curl reads tokens from
# header files only this user can read, and psql gets the connection through
# its environment, never on the command line.
set -euo pipefail

usage="usage: PUBLISH_TOKEN=... CLIENT_TOKEN=... SUPABASE_DB_URL=... $0 <worker-url> [2] [3] [4] [5]"
url="${1:?$usage}"
url="${url%/}"
shift
criteria=("$@")
[[ ${#criteria[@]} -gt 0 ]] || criteria=(2 3 4 5)
for c in "${criteria[@]}"; do
  [[ "$c" =~ ^[2-5]$ ]] || { echo "unknown criterion '$c'; $usage" >&2; exit 2; }
done
wants() { local c; for c in "${criteria[@]}"; do [[ "$c" == "$1" ]] && return 0; done; return 1; }

command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
if wants 2 || wants 3; then
  command -v cargo >/dev/null || { echo "cargo is required" >&2; exit 2; }
  : "${PUBLISH_TOKEN:?PUBLISH_TOKEN must be set for criteria 2 and 3}"
fi
if wants 4; then : "${CLIENT_TOKEN:?CLIENT_TOKEN must be set for criterion 4}"; fi
if wants 5; then command -v supabase >/dev/null || { echo "supabase CLI is required" >&2; exit 2; }; fi
if [[ -n "${SUPABASE_DB_URL:-}" ]]; then command -v psql >/dev/null || { echo "psql is required" >&2; exit 2; }; fi
expected_exhausted="${VOCAB_WHEN_EXHAUSTED:-rotate}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

tmp="$(mktemp -d)"
chmod 700 "$tmp"
failures=0
restore_sql=""
started_local_db=""

cleanup() {
  if [[ -n "$restore_sql" ]]; then
    if sql "$restore_sql" >/dev/null; then
      echo "restored: vocab_interval_minutes"
    else
      echo "RESTORE FAILED: run this on the project: $restore_sql" >&2
    fi
  fi
  if [[ -n "$started_local_db" ]]; then
    (cd "$repo_root" && supabase stop >/dev/null 2>&1) && echo "stopped the local Supabase stack"
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

if [[ -n "${CLIENT_TOKEN:-}" ]]; then
  (umask 077; printf 'Authorization: Bearer %s\n' "$CLIENT_TOKEN" >"$tmp/client")
fi

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; failures=$((failures + 1)); }

# Splits SUPABASE_DB_URL into libpq environment variables, so psql never gets
# the password as an argument other processes could list.
pg_env=()
if [[ -n "${SUPABASE_DB_URL:-}" ]]; then
  re='^postgres(ql)?://([^:@/]+)(:([^@/]*))?@([^:/?]+)(:([0-9]+))?/([^?]+)(\?(.*))?$'
  [[ "$SUPABASE_DB_URL" =~ $re ]] || { echo "SUPABASE_DB_URL is not a Postgres URI with user, password, host, port and database" >&2; exit 2; }
  decode() { local s="${1//+/ }"; printf '%b' "${s//%/\\x}"; }
  pg_env=(PGUSER="$(decode "${BASH_REMATCH[2]}")" PGPASSWORD="$(decode "${BASH_REMATCH[4]}")"
    PGHOST="${BASH_REMATCH[5]}" PGPORT="${BASH_REMATCH[7]:-5432}" PGDATABASE="$(decode "${BASH_REMATCH[8]}")"
    PGSSLMODE=require PGCONNECT_TIMEOUT=15)
fi
have_db() { [[ ${#pg_env[@]} -gt 0 ]]; }

# sql QUERY: runs QUERY on the project and prints unaligned, tuples-only rows.
sql() { env "${pg_env[@]}" psql -X -q -At -v ON_ERROR_STOP=1 -c "$1"; }

# ingest ARGS...: runs `os-widget ingest ARGS` against the Worker; stdout lands
# in $tmp/ingest-out and stderr in $tmp/ingest-err.
ingest() {
  (cd "$repo_root" && OS_WIDGET_SERVER="$url" OS_WIDGET_PUBLISH_TOKEN="$PUBLISH_TOKEN" \
    cargo run -q -p cli -- ingest "$@") >"$tmp/ingest-out" 2>"$tmp/ingest-err"
}

# events_since SEQ: every event after SEQ as one JSON array, following pages of 100.
events_since() {
  local since="$1" page all='[]' n code
  while :; do
    code=$(curl -s -o "$tmp/out" -w '%{http_code}' -H @"$tmp/client" "$url/events?since=$since") || code=000
    [[ "$code" == 200 ]] || { echo "GET /events -> $code" >&2; return 1; }
    page=$(cat "$tmp/out")
    n=$(jq 'length' <<<"$page")
    all=$(jq -c --argjson p "$page" '. + $p' <<<"$all")
    [[ "$n" -lt 100 ]] && break
    since=$(jq '.[-1].seq' <<<"$page")
  done
  echo "$all"
}

latest_seq() {
  local code
  code=$(curl -s -o "$tmp/out" -w '%{http_code}' -H @"$tmp/client" "$url/items") || code=000
  [[ "$code" == 200 ]] || { echo "GET /items -> $code" >&2; return 1; }
  jq '.seq' "$tmp/out"
}

# vocab_sends SEQ: creation times (epoch seconds) of vocab-cron items created after SEQ.
vocab_sends() {
  events_since "$1" | jq -r '.[] | select(.type == "item.created" and .item.source == "vocab-cron")
    | .created_at | sub("\\.[0-9]+"; "") | sub("(\\+00:00|\\+00|Z)$"; "Z") | fromdateiso8601'
}

echo "vocab acceptance against $url, criteria ${criteria[*]}"

# 2. Dictionary ingest: complete words stored, incomplete skipped, no duplicates.
if wants 2; then
  printf '%s\n' serendipity meticulous garrulous vindicate >"$tmp/words.txt"
  word_list="'serendipity','meticulous','garrulous','vindicate'"
  notes=()
  ok=y
  if ingest words "$tmp/words.txt" --origin acceptance-words; then first=$(cat "$tmp/ingest-out"); else first="error: $(cat "$tmp/ingest-err")"; fi
  [[ "$first" == "stored 3, skipped 1" ]] || ok=n
  if have_db; then before=$(sql "select count(*) from public.vocab_words") || before="?"; fi
  if ingest words "$tmp/words.txt" --origin acceptance-words; then second=$(cat "$tmp/ingest-out"); else second="error: $(cat "$tmp/ingest-err")"; fi
  [[ "$second" == "stored 3, skipped 1" ]] || ok=n
  if have_db; then
    after=$(sql "select count(*) from public.vocab_words") || after="?"
    listed=$(sql "select count(*) from public.vocab_words where word in ($word_list)") || listed="?"
    [[ "$before" != "?" && "$before" == "$after" && "$listed" == 3 ]] || ok=n
    notes+=("rows $before before the second run, $after after; $listed of the four words stored")
  else
    notes+=("row count not checked (no SUPABASE_DB_URL): the second run reports the same stored count")
  fi
  if [[ "$ok" == y ]]; then
    pass "2 ingest words: first run '$first', second run '$second'; ${notes[*]}"
  else
    fail "2 ingest words" "first run '$first', second run '$second' (want 'stored 3, skipped 1' twice); ${notes[*]}"
  fi
fi

# 3. Book ingest: every stored word carries a sentence from the book.
if wants 3; then
  book="$repo_root/crates/cli/tests/fixtures/book/sample.txt"
  if ! have_db; then
    fail "3 ingest book" "needs SUPABASE_DB_URL to read the stored contexts"
  elif ! ingest book "$book" --origin acceptance-book --max 3; then
    fail "3 ingest book" "CLI failed: $(cat "$tmp/ingest-err")"
  else
    report=$(cat "$tmp/ingest-out")
    # The CLI joins lines and straightens quotes; compare on the same footing.
    flat=$(tr -s '[:space:]' ' ' <"$book")
    for q in $'‘' $'’'; do flat=${flat//$q/\'}; done
    for q in $'“' $'”'; do flat=${flat//$q/\"}; done
    printf '%s\n' "$flat" >"$tmp/book-flat"
    sql "select coalesce(jsonb_agg(jsonb_build_object('word', word, 'context', entry ->> 'context')), '[]')
         from public.vocab_words where origin = 'acceptance-book'" >"$tmp/book-rows"
    total=$(jq 'length' "$tmp/book-rows")
    bad=()
    while IFS=$'\t' read -r word context; do
      piece_ok=y
      [[ -n "$context" ]] || piece_ok=n
      # A long sentence is cut around the word and marked with an ellipsis.
      while IFS= read -r piece; do
        [[ -z "$piece" ]] || grep -qF -- "$piece" "$tmp/book-flat" || piece_ok=n
      done <<<"${context//…/$'\n'}"
      [[ "$piece_ok" == y ]] || bad+=("$word")
    done < <(jq -r '.[] | [.word, (.context // "")] | @tsv' "$tmp/book-rows")
    if [[ "$report" == stored\ * && "$total" -ge 1 && ${#bad[@]} -eq 0 ]]; then
      pass "3 ingest book: '$report'; $total words with origin acceptance-book, each with a sentence from the book ($(jq -r '[.[].word] | join(", ")' "$tmp/book-rows"))"
    else
      fail "3 ingest book" "'$report'; $total words with origin acceptance-book; without a sentence from the book: ${bad[*]+"${bad[*]}"}"
    fi
  fi
fi

# 4. Changing the interval takes effect at the next cron runs, without a deploy.
if wants 4; then
  if ! have_db; then
    fail "4 interval change" "needs SUPABASE_DB_URL to change vocab_interval_minutes"
  else
    old=$(sql "select value::text from public.settings where key = 'vocab_interval_minutes'")
    [[ "$old" =~ ^[0-9]+$ ]] || { echo "vocab_interval_minutes is '$old', expected a number" >&2; exit 1; }
    restore_sql="update public.settings set value = '$old'::jsonb where key = 'vocab_interval_minutes'"
    echo "vocab_interval_minutes was $old; setting 5 and watching GET /events for 15 minutes"
    s5=$(latest_seq)
    sql "update public.settings set value = '5'::jsonb where key = 'vocab_interval_minutes'" >/dev/null
    sleep 900
    sends5=()
    while read -r t; do sends5+=("$t"); done < <(vocab_sends "$s5")
    ok5=n
    for ((i = 1; i < ${#sends5[@]}; i++)); do
      gap=$((sends5[i] - sends5[i - 1]))
      ((gap >= 240 && gap <= 420)) && ok5=y
    done
    echo "setting 15 and watching GET /events for 20 minutes"
    s15=$(latest_seq)
    sql "update public.settings set value = '15'::jsonb where key = 'vocab_interval_minutes'" >/dev/null
    sleep 1200
    sends15=()
    while read -r t; do sends15+=("$t"); done < <(vocab_sends "$s15")
    sql "$restore_sql" >/dev/null && restore_sql="" && echo "restored vocab_interval_minutes to $old"
    # The first send after switching to 15 is measured from the last send at 5.
    ok15=n
    gaps15=()
    if [[ ${#sends15[@]} -ge 1 && ${#sends5[@]} -ge 1 ]]; then
      chain=("${sends5[${#sends5[@]} - 1]}" "${sends15[@]}")
      ok15=y
      for ((i = 1; i < ${#chain[@]}; i++)); do
        gap=$((chain[i] - chain[i - 1]))
        gaps15+=("${gap}s")
        ((gap >= 840)) || ok15=n
      done
    fi
    detail="interval 5: ${#sends5[@]} vocab items in 15 min; interval 15: ${#sends15[@]} in 20 min, gaps ${gaps15[*]+"${gaps15[*]}"}"
    if [[ "$ok5$ok15" == yy ]]; then
      pass "4 interval change without deploy: $detail"
    else
      fail "4 interval change" "$detail (want two sends about 5 min apart, then gaps of at least 14 min)"
    fi
  fi
fi

# 5. Running out of words: the local suite proves stop and rotate; live is read only.
if wants 5; then
  notes=()
  ok=y
  if ! (cd "$repo_root" && supabase status >/dev/null 2>&1); then
    if (cd "$repo_root" && supabase db start >/dev/null 2>&1); then started_local_db=y; else ok=n; notes+=("could not start the local database"); fi
  fi
  if [[ "$ok" == y ]]; then
    if (cd "$repo_root" && supabase test db >"$tmp/pgtap" 2>&1); then
      notes+=("local pgTAP: $(grep -E '^Result:|^Files=' "$tmp/pgtap" | tr '\n' ' ' | sed 's/ *$//')")
    else
      ok=n
      notes+=("local pgTAP failed: $(grep -E 'not ok|Failed|Result' "$tmp/pgtap" | head -5 | tr '\n' ' ')")
    fi
  fi
  if ! have_db; then
    ok=n
    notes+=("live check needs SUPABASE_DB_URL")
  else
    live=$(sql "select value #>> '{}' from public.settings where key = 'vocab_when_exhausted'") || live="?"
    [[ "$live" == "$expected_exhausted" ]] || ok=n
    empty=$(sql "select count(*) from public.items where source = 'vocab-cron'
                 and (coalesce(btrim(title), '') = '' or coalesce(btrim(body ->> 'word'), '') = ''
                      or jsonb_typeof(body -> 'meanings') is distinct from 'array')") || empty="?"
    [[ "$empty" == 0 ]] || ok=n
    notes+=("live vocab_when_exhausted '$live' (want '$expected_exhausted'); vocab-cron items without a word or meanings: $empty")
  fi
  if [[ "$ok" == y ]]; then
    pass "5 when words run out: $(IFS=';'; echo "${notes[*]}")"
  else
    fail "5 when words run out" "$(IFS=';'; echo "${notes[*]}")"
  fi
fi

echo "checks failed: $failures"
[[ "$failures" -eq 0 ]]
