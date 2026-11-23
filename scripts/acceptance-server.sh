#!/usr/bin/env bash
# Checks a deployed os-widget Worker against the server acceptance criteria.
#
# Usage: PUBLISH_TOKEN=... CLIENT_TOKEN=... SUPABASE_URL=... SUPABASE_ANON_KEY=... \
#          scripts/acceptance-server.sh <worker-url>
#
# Criteria:
#   1. The CLI publishes an item and GET /events returns it.
#   2. A malformed envelope is rejected with a message naming the wrong field.
#   3. Publishing twice with the same dedupe_key creates one item.
#   4. Marking read and deleting emit the right events.
#   5. A missing token or the wrong kind of token is rejected.
#   6. The anon key reads events but not items.
# Extra checks: GET /events limit (cap 100, 0 rejected) and the 7-day default ttl.
#
# Test items use source "acceptance" and ttl 3600 (except the default-ttl item)
# and are deleted at the end, also when the script stops early. Prints PASS or
# FAIL per check and exits 1 if any check failed. Tokens and keys are never
# printed: curl reads them from header files only this user can read.
set -euo pipefail

url="${1:?usage: PUBLISH_TOKEN=... CLIENT_TOKEN=... SUPABASE_URL=... SUPABASE_ANON_KEY=... $0 <worker-url>}"
url="${url%/}"
: "${PUBLISH_TOKEN:?PUBLISH_TOKEN must be set}"
: "${CLIENT_TOKEN:?CLIENT_TOKEN must be set}"
: "${SUPABASE_URL:?SUPABASE_URL must be set}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY must be set}"
supabase_url="${SUPABASE_URL%/}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
command -v cargo >/dev/null || { echo "cargo is required" >&2; exit 2; }
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

tmp="$(mktemp -d)"
chmod 700 "$tmp"
created=()
failures=0

cleanup() {
  local id code
  for id in "${created[@]+"${created[@]}"}"; do
    code=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE -H @"$tmp/client" "$url/items/$id") || code=000
    echo "cleanup: DELETE /items/$id -> $code"
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

(
  umask 077
  printf 'Authorization: Bearer %s\n' "$PUBLISH_TOKEN" >"$tmp/publish"
  printf 'Authorization: Bearer %s\n' "$CLIENT_TOKEN" >"$tmp/client"
  printf 'Authorization: Bearer %s\n' "wrong-$(date +%s)" >"$tmp/wrong"
  printf 'apikey: %s\n' "$SUPABASE_ANON_KEY" >"$tmp/anon"
  : >"$tmp/none"
)

run_id="acceptance-$(date +%Y%m%dT%H%M%S)-$$"
echo "run $run_id against $url"

pass() { echo "PASS $1"; }
fail() { echo "FAIL $1: $2"; failures=$((failures + 1)); }

# req METHOD URL HEADER_FILE [BODY]: prints the status; the body lands in $tmp/out.
req() {
  local method="$1" target="$2" hdr="$3" body="${4-}"
  local args=(-s -o "$tmp/out" -w '%{http_code}' -X "$method" -H @"$hdr")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' --data "$body")
  # curl prints 000 itself when the request never completes; do not append another.
  local code
  code=$(curl "${args[@]}" "$target") || true
  echo "${code:-000}"
}

out() { cat "$tmp/out"; }

# remember_created STATUS: remembers the id in $tmp/out when STATUS is 2xx, so an
# envelope the Worker wrongly accepts is still deleted at the end.
remember_created() {
  if [[ "$1" == 2* ]]; then remember "$(jq -r '.id // empty' "$tmp/out" 2>/dev/null || true)"; fi
}

# envelope TITLE [EXTRA_JQ]: a notification envelope from this run, ttl 3600.
envelope() {
  jq -cn --arg t "$1" --arg r "$run_id" \
    "{v:1, kind:\"notification\", source:\"acceptance\", title:\$t, summary:(\"run \" + \$r), ttl:3600} ${2-}"
}

# publish BODY: POST /items with the publish token; prints "<status> <id>".
# Runs in a command substitution, so callers pass the id to remember.
publish() {
  local code id
  code=$(req POST "$url/items" "$tmp/publish" "$1")
  id=$(jq -r '.id // empty' "$tmp/out" 2>/dev/null || true)
  echo "$code $id"
}

remember() {
  [[ -n "$1" ]] || return 0
  local known
  for known in "${created[@]+"${created[@]}"}"; do [[ "$known" == "$1" ]] && return; done
  created+=("$1")
}

latest_seq() {
  [[ "$(req GET "$url/items" "$tmp/client")" == 200 ]] || { echo "GET /items failed: $(out)" >&2; return 1; }
  jq '.seq' "$tmp/out"
}

# events_since SEQ: every event after SEQ as one JSON array, following pages of 100.
events_since() {
  local since="$1" page all='[]' n
  while :; do
    [[ "$(req GET "$url/events?since=$since" "$tmp/client")" == 200 ]] || { echo "GET /events failed: $(out)" >&2; return 1; }
    page=$(out)
    n=$(jq 'length' <<<"$page")
    all=$(jq -c --argjson p "$page" '. + $p' <<<"$all")
    [[ "$n" -lt 100 ]] && break
    since=$(jq '.[-1].seq' <<<"$page")
  done
  echo "$all"
}

# count_events SEQ TYPE ID: how many TYPE events for item ID follow SEQ.
count_events() {
  events_since "$1" | jq --arg t "$2" --arg id "$3" '[.[] | select(.type == $t and .item_id == $id)] | length'
}

seq0=$(latest_seq)
echo "starting at seq $seq0"

# 1. CLI publish, then GET /events returns the item.
c1_id=$(cd "$repo_root" && OS_WIDGET_SERVER="$url" OS_WIDGET_PUBLISH_TOKEN="$PUBLISH_TOKEN" \
  cargo run -q -p cli -- publish --source acceptance --title "cli $run_id" \
  --summary "published by the CLI" --ttl 3600 2>"$tmp/cli-err") || c1_id=""
if [[ -z "$c1_id" ]]; then
  fail "1 CLI publish" "CLI failed: $(cat "$tmp/cli-err")"
else
  remember "$c1_id"
  found=$(events_since "$seq0" | jq --arg id "$c1_id" \
    '[.[] | select(.type == "item.created" and .item_id == $id and .item.id == $id)] | length')
  if [[ "$found" == 1 ]]; then
    pass "1 CLI publish $c1_id appears in GET /events as item.created with its item"
  else
    fail "1 CLI publish" "found $found item.created events with the item for $c1_id"
  fi
fi

# 2. Malformed envelopes name the wrong field.
code=$(req POST "$url/items" "$tmp/publish" "$(envelope x '| del(.title)')")
remember_created "$code"
c2a=$(jq -c '{field, message}' "$tmp/out" 2>/dev/null || out)
c2a_ok=$([[ "$code" == 400 ]] && jq -e '.message | contains("title")' "$tmp/out" >/dev/null && echo y || echo n)
vocab=$(jq -cn --arg r "$run_id" '{v:1, kind:"vocab", source:"acceptance", title:"vocab", summary:$r, ttl:3600,
  body:{word:"w", ipa:"/w/", pos:"noun", meanings:[{examples:["e"]}]}}')
code_b=$(req POST "$url/items" "$tmp/publish" "$vocab")
remember_created "$code_b"
c2b=$(jq -c '{field, message}' "$tmp/out" 2>/dev/null || out)
c2b_ok=$([[ "$code_b" == 400 ]] && jq -e '.field == "body.meanings[0]"' "$tmp/out" >/dev/null && echo y || echo n)
code_c=$(req POST "$url/items" "$tmp/publish" "$(envelope weather '| .kind = "weather"')")
remember_created "$code_c"
c2c=$(jq -c '{field, message}' "$tmp/out" 2>/dev/null || out)
c2c_ok=$([[ "$code_c" == 400 ]] && jq -e '.field == "kind"' "$tmp/out" >/dev/null && echo y || echo n)
if [[ "$c2a_ok$c2b_ok$c2c_ok" == yyy ]]; then
  pass "2 invalid envelopes: no title -> $code $c2a; vocab without definition -> $code_b $c2b; kind weather -> $code_c $c2c"
else
  fail "2 invalid envelopes" "no title -> $code $c2a; vocab -> $code_b $c2b; weather -> $code_c $c2c"
fi

# 3. Same dedupe_key twice creates one item.
seq3=$(latest_seq)
dedupe=$(envelope "dedupe $run_id" "| .dedupe_key = \"$run_id\"")
read -r d1_code d1_id <<<"$(publish "$dedupe")"
remember "$d1_id"
read -r d2_code d2_id <<<"$(publish "$dedupe")"
remember "$d2_id"
d_created=$(count_events "$seq3" item.created "$d1_id")
if [[ "$d1_code" == 201 && "$d2_code" == 200 && -n "$d1_id" && "$d1_id" == "$d2_id" && "$d_created" == 1 ]]; then
  pass "3 dedupe: first 201, second 200, same id $d1_id, one item.created"
else
  fail "3 dedupe" "first $d1_code $d1_id, second $d2_code $d2_id, item.created count $d_created"
fi

# 4. Read state and deletion emit the right events.
read -r r_code r_id <<<"$(publish "$(envelope "read $run_id")")"
remember "$r_id"
c4=()
check4() { [[ "$1" == "$2" ]] || c4+=("$3: got $1, want $2"); }
if [[ "$r_code" != 201 ]]; then
  fail "4 read and delete" "could not publish the test item: $r_code $(out)"
else
  s=$(latest_seq)
  check4 "$(req PATCH "$url/items/$r_id" "$tmp/client" '{"read":true}')" 204 "PATCH read"
  check4 "$(count_events "$s" item.read "$r_id")" 1 "item.read events"
  s=$(latest_seq)
  check4 "$(req PATCH "$url/items/$r_id" "$tmp/client" '{"read":true}')" 204 "PATCH read again"
  check4 "$(events_since "$s" | jq --arg id "$r_id" '[.[] | select(.item_id == $id)] | length')" 0 "events after repeated read"
  s=$(latest_seq)
  check4 "$(req PATCH "$url/items/$r_id" "$tmp/client" '{"read":false}')" 204 "PATCH unread"
  check4 "$(count_events "$s" item.unread "$r_id")" 1 "item.unread events"
  s=$(latest_seq)
  check4 "$(req DELETE "$url/items/$r_id" "$tmp/client")" 204 "DELETE"
  check4 "$(count_events "$s" item.deleted "$r_id")" 1 "item.deleted events"
  s=$(latest_seq)
  check4 "$(req DELETE "$url/items/$r_id" "$tmp/client")" 204 "DELETE again"
  check4 "$(events_since "$s" | jq --arg id "$r_id" '[.[] | select(.item_id == $id)] | length')" 0 "events after repeated delete"
  check4 "$(req PATCH "$url/items/$r_id" "$tmp/client" '{"read":true}')" 404 "PATCH after delete"
  if [[ ${#c4[@]} -eq 0 ]]; then
    pass "4 read/unread/delete on $r_id: 204 with item.read, item.unread, item.deleted; repeats add no event; PATCH after delete 404"
  else
    fail "4 read and delete" "$(IFS=';'; echo "${c4[*]}")"
  fi
fi

# 5. Missing, wrong or wrong-kind tokens are rejected.
a=$(req GET "$url/items" "$tmp/none")
b=$(req POST "$url/items" "$tmp/client" "$(envelope "client token $run_id")")
remember_created "$b"
c=$(req GET "$url/events?since=0" "$tmp/publish")
d=$(req GET "$url/items" "$tmp/wrong")
if [[ "$a $b $c $d" == "401 403 403 401" ]]; then
  pass "5 tokens: none -> 401, client token on POST /items -> 403, publish token on GET /events -> 403, wrong token -> 401"
else
  fail "5 tokens" "none $a (want 401), client POST $b (want 403), publish GET /events $c (want 403), wrong $d (want 401)"
fi

# 6. The anon key reads events but not items, and cannot run the purge.
e=$(req GET "$supabase_url/rest/v1/events?limit=1" "$tmp/anon")
e_ok=$([[ "$e" == 200 ]] && jq -e 'type == "array"' "$tmp/out" >/dev/null && echo y || echo n)
i=$(req GET "$supabase_url/rest/v1/items?limit=1" "$tmp/anon")
i_ok=$({ [[ "$i" == 401 || "$i" == 403 ]] || { [[ "$i" == 200 ]] && jq -e '. == []' "$tmp/out" >/dev/null; }; } && echo y || echo n)
p=$(req POST "$supabase_url/rest/v1/rpc/purge_old_rows" "$tmp/anon" '{}')
p_ok=$([[ "$p" != 2* && "$p" != 000 ]] && echo y || echo n)
if [[ "$e_ok$i_ok$p_ok" == yyy ]]; then
  pass "6 anon key: events -> $e array, items -> $i no rows, rpc/purge_old_rows -> $p rejected"
else
  fail "6 anon key" "events $e, items $i, rpc/purge_old_rows $p"
fi

# Extra: GET /events limit.
l1=$(req GET "$url/events?since=0&limit=500" "$tmp/client")
l1_n=$(jq 'length' "$tmp/out" 2>/dev/null || echo "?")
l0=$(req GET "$url/events?since=0&limit=0" "$tmp/client")
if [[ "$l1" == 200 && "$l1_n" -le 100 && "$l0" == 400 ]]; then
  pass "limit: since=0&limit=500 -> 200 with $l1_n events (max 100), limit=0 -> 400"
else
  fail "limit" "limit=500 -> $l1 with $l1_n events, limit=0 -> $l0"
fi

# Extra: an item published without ttl expires 7 days after it was created.
read -r t_code t_id <<<"$(publish "$(envelope "default ttl $run_id" '| del(.ttl)')")"
remember "$t_id"
to_epoch='sub("\\.[0-9]+"; "") | sub("(\\+00:00|\\+00|Z)$"; "Z") | fromdateiso8601'
gap=""
if [[ "$t_code" == 201 && "$(req GET "$url/items" "$tmp/client")" == 200 ]]; then
  gap=$(jq --arg id "$t_id" ".items[] | select(.id == \$id) | (.expires_at | $to_epoch) - (.created_at | $to_epoch)" "$tmp/out")
fi
if [[ -n "$gap" ]] && (( gap >= 604800 - 5 && gap <= 604800 + 5 )); then
  pass "default ttl: expires_at - created_at = ${gap}s (7 days = 604800s)"
else
  fail "default ttl" "publish $t_code, expires_at - created_at = '${gap}'s"
fi

echo "checks failed: $failures"
[[ "$failures" -eq 0 ]]
