#!/usr/bin/env bash
# Checks the OS Widget desktop widget installed on this Mac against its acceptance criteria.
# Runs on the Mac where the app is installed, with a medium and a large OS Widget widget on the
# desktop, and reads the app and widget log here.
#
# Usage: PUBLISH_TOKEN=... CLIENT_TOKEN=... OS_WIDGET_SERVER=<worker-url> \
#          scripts/acceptance-widget.sh <2|read|delete|offline|reload|checklist|day|all> [day options]
#
# Criteria:
#   2          A published notification reaches the top of both widgets in under 5 s, measured
#              from the app's first "sync.applied ... new=N" (N >= 1) after the publish to the
#              widget's "widget.timeline family=<f> ... top=<id>". Five rounds, 40 s apart.
#   read       Tapping the check mark in the widget reaches GET /items (read_at) and GET /events
#              (item.read), through "widget.intent" and "widget.inbox_drained" in the log.
#   delete     Same with the trash button: item.deleted, and the item leaves GET /items.
#   offline    With Wi-Fi off, the tap is drained into the app's queue; once Wi-Fi is back the
#              server gets read_at within 60 s. Needs no answer while offline.
#   reload     Five items published within about 3 s cause at most 3 "widget.reload" lines, at
#              least 5 s apart, and the last timeline shows the last item; a later sync round with
#              no change causes no reload.
#   checklist  Publishes one notification, generic and vocab item and walks the operator checklist
#              (rows per size, compact layouts, dimmed read items, a tap with the app quit, a tap
#              on the row body, light and dark mode).
#   day        Runs scripts/widget-reload-count.sh over the given window (pass --input <file> for a
#              saved `log stream`, or --start/--end) and also requires at least one request.
#   all        2, read, delete, reload. offline, checklist and day run on their own.
#
# Test items use source "acceptance-m3", ttl 3600 and a dedupe_key from this run, and are deleted
# at the end, also when the script stops early. Prints PASS or FAIL per criterion and exits 1 if
# any failed. Tokens are never printed: curl reads them from header files only this user can read.
# Answers to y/n questions are read from OPERATOR_INPUT (default /dev/tty; a FIFO works, so a
# second session can relay the operator's answers).
set -euo pipefail

which_check="${1:?usage: PUBLISH_TOKEN=... CLIENT_TOKEN=... OS_WIDGET_SERVER=... $0 <2|read|delete|offline|reload|checklist|day|all>}"
shift
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
subsystem="local.oswidget.app"

case "$which_check" in
  2 | read | delete | offline | reload | checklist | all) ;;
  day)
    command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
    out=$("$repo_root/scripts/widget-reload-count.sh" "$@")
    echo "$out"
    summary=$(tail -n 1 <<<"$out")
    requests=$(sed -nE 's/^requests=([0-9]+) .*/\1/p' <<<"$summary")
    verdict=$(sed -nE 's/.*verdict=([A-Z]+)$/\1/p' <<<"$summary")
    # Taps on the widget buttons each lead to about one reload after the app drains the inbox.
    if [[ "${1-}" == --input ]]; then
      taps=$(grep -c '"eventMessage":"widget.intent ' "$2" || true)
    else
      taps=$(/usr/bin/log show --info --style compact "$@" \
        --predicate "subsystem == \"$subsystem\" AND eventMessage BEGINSWITH \"widget.intent \"" 2>/dev/null |
        grep -c 'widget.intent ' || true)
    fi
    echo "button taps in the window: $taps"
    if [[ "$verdict" == PASS && "${requests:-0}" -gt 0 ]]; then
      echo "PASS day $summary"
    elif [[ "${requests:-0}" -eq 0 ]]; then
      echo "FAIL day: no widget.reload in the window (is the new app running?)"
      exit 1
    else
      echo "FAIL day $summary"
      exit 1
    fi
    exit 0
    ;;
  *)
    echo "unknown criterion '$which_check' (want 2, read, delete, offline, reload, checklist, day or all)" >&2
    exit 2
    ;;
esac

: "${PUBLISH_TOKEN:?PUBLISH_TOKEN must be set}"
: "${CLIENT_TOKEN:?CLIENT_TOKEN must be set}"
: "${OS_WIDGET_SERVER:?OS_WIDGET_SERVER must be set}"
url="${OS_WIDGET_SERVER%/}"
answers="${OPERATOR_INPUT:-/dev/tty}"
families="${WIDGET_FAMILIES:-medium large}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
command -v cargo >/dev/null || { echo "cargo is required" >&2; exit 2; }
source_name="acceptance-m3"

tmp="$(mktemp -d)"
chmod 700 "$tmp"
created=()
failures=0
results=()
run_started="$(date '+%Y-%m-%d %H:%M:%S')"

cleanup() {
  local id code
  for id in "${created[@]+"${created[@]}"}"; do
    code=$(curl -s -m 20 -o /dev/null -w '%{http_code}' -X DELETE -H @"$tmp/client" "$url/items/$id") || code=000
    echo "cleanup: DELETE /items/$id -> $code"
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

(
  umask 077
  printf 'Authorization: Bearer %s\n' "$CLIENT_TOKEN" >"$tmp/client"
  printf 'Authorization: Bearer %s\n' "$PUBLISH_TOKEN" >"$tmp/publish"
)

run_id="m3-$(date +%Y%m%dT%H%M%S)-$$"
echo "run $run_id against $url"

pass() { echo "PASS $1"; results+=("PASS $1"); }
fail() { echo "FAIL $1: $2"; results+=("FAIL $1: $2"); failures=$((failures + 1)); }

# req METHOD URL [BODY] [HEADER_FILE]: prints the status; the body lands in $tmp/out.
req() {
  local method="$1" target="$2" body="${3-}" header="${4:-$tmp/client}"
  local args=(-s -m 20 -o "$tmp/out" -w '%{http_code}' -X "$method" -H @"$header")
  [[ -n "$body" ]] && args+=(-H 'Content-Type: application/json' --data "$body")
  local code
  code=$(curl "${args[@]}" "$target") || true
  echo "${code:-000}"
}

remember() {
  [[ -n "$1" ]] || return 0
  local known
  for known in "${created[@]+"${created[@]}"}"; do [[ "$known" == "$1" ]] && return; done
  created+=("$1")
}

# cli ARGS...: runs `os-widget` with the publish token in its environment only.
cli() {
  (cd "$repo_root" && OS_WIDGET_SERVER="$url" OS_WIDGET_PUBLISH_TOKEN="$PUBLISH_TOKEN" \
    cargo run -q -p cli -- "$@")
}

# publish_note TAG TITLE: publishes a notification with the CLI; prints its id.
publish_note() {
  local id
  id=$(cli publish --source "$source_name" --title "$2" --summary "run $run_id" \
    --ttl 3600 --dedupe-key "$run_id-$1" 2>"$tmp/cli-err") || {
    echo "CLI publish failed: $(cat "$tmp/cli-err")" >&2
    return 1
  }
  echo "$id"
}

# post_item JSON: POST /items with the publish token (no compiler start-up); prints the id.
post_item() {
  local code
  code=$(req POST "$url/items" "$1" "$tmp/publish")
  [[ "$code" == 200 || "$code" == 201 ]] || { echo "POST /items -> $code" >&2; return 1; }
  jq -r '.id // empty' "$tmp/out"
}

ask() {
  local answer
  while :; do
    echo "ASK: $1 [y/n]"
    read -r answer <"$answers" || answer=""
    case "$answer" in y | Y) return 0 ;; n | N) return 1 ;; esac
  done
}

# confirm LABEL QUESTION PASS_TEXT: asks the operator and records PASS or FAIL.
confirm() {
  if ask "$2"; then pass "$3"; else fail "$1" "operator said no"; fi
}

wait_enter() {
  echo "WAIT: $1 (Enter)"
  read -r _ <"$answers" || true
}

now_stamp() { date '+%Y-%m-%d %H:%M:%S'; }

# events START PATTERN: "<epoch ms> <message>" for app and widget log lines since START whose
# message contains PATTERN, oldest first.
events() {
  /usr/bin/log show --info --style ndjson --start "$1" \
    --predicate "subsystem == \"$subsystem\" AND process BEGINSWITH \"OSWidget\" AND eventMessage CONTAINS \"$2\"" \
    2>/dev/null | jq -rR '
      (try fromjson catch empty) | select(.eventMessage != null and .timestamp != null)
      | (.timestamp | capture("^(?<d>[0-9-]+ [0-9:]+)(?:\\.(?<f>[0-9]+))?(?<s>[+-])(?<h>[0-9]{2})(?<m>[0-9]{2})$")) as $t
      | ((($t.d | sub(" "; "T")) + "Z" | fromdate) * 1000 + (((($t.f // "0") + "000")[0:3]) | tonumber)
         - (($t.h | tonumber) * 3600 + ($t.m | tonumber) * 60) * 1000 * (if $t.s == "+" then 1 else -1 end))
        as $ms
      | "\($ms) \(.eventMessage)"' | sort -n
}

# wait_event START PATTERN SECONDS: waits for a matching line; prints the first "<ms> <message>".
wait_event() {
  local deadline=$((SECONDS + $3)) line
  while ((SECONDS < deadline)); do
    line=$(events "$1" "$2" | head -n 1)
    if [[ -n "$line" ]]; then echo "$line"; return 0; fi
    sleep 1
  done
  return 1
}

# first_applied START SECONDS: first "sync.applied ... new=N" with N >= 1 since START.
first_applied() {
  local deadline=$((SECONDS + $2)) line
  while ((SECONDS < deadline)); do
    line=$(events "$1" "sync.applied" | grep -E ' new=[1-9]' | head -n 1 || true)
    if [[ -n "$line" ]]; then echo "$line"; return 0; fi
    sleep 1
  done
  return 1
}

# wait_top START ID SECONDS: waits until every family in $families logged a timeline with top=ID;
# prints "<family>=<ms>" per family.
wait_top() {
  local deadline=$((SECONDS + $3)) f line out missing
  while ((SECONDS < deadline)); do
    out="" missing=0
    for f in $families; do
      line=$(events "$1" "widget.timeline family=$f " | grep -F "top=$2" | head -n 1 || true)
      if [[ -n "$line" ]]; then out+="$f=${line%% *} "; else missing=1; fi
    done
    if ((missing == 0)); then echo "$out"; return 0; fi
    sleep 1
  done
  echo "$out"
  return 1
}

item_field() {
  [[ "$(req GET "$url/items")" == 200 ]] || return 0
  jq -r --arg id "$1" --arg f "$2" '.items[] | select(.id == $id) | .[$f] // empty' "$tmp/out"
}

item_present() {
  [[ "$(req GET "$url/items")" == 200 ]] || return 2
  jq -e --arg id "$1" 'any(.items[]; .id == $id)' "$tmp/out" >/dev/null
}

latest_seq() {
  [[ "$(req GET "$url/items")" == 200 ]] || { echo "GET /items failed" >&2; return 1; }
  jq '.seq' "$tmp/out"
}

# event_seq SINCE TYPE ID: seq of the first TYPE event for item ID after SINCE, or empty.
event_seq() {
  [[ "$(req GET "$url/events?since=$1&limit=100")" == 200 ]] || return 0
  jq -r --arg t "$2" --arg id "$3" \
    '[.[] | select(.type == $t and .item_id == $id)][0].seq // empty' "$tmp/out"
}

server_reachable() { curl -s -m 5 -o /dev/null "$url/" 2>/dev/null; }

# show_on_widget TAG TITLE: publishes a notification, sets shown_id, and waits until both widgets
# show it on top. Runs in the calling shell so the id is remembered for cleanup.
shown_id=""
show_on_widget() {
  local start
  start=$(now_stamp)
  shown_id=$(publish_note "$1" "$2") || return 1
  remember "$shown_id"
  if ! wait_top "$start" "$shown_id" 30 >/dev/null; then
    echo "no widget.timeline top=$shown_id for every family ($families) within 30 s" >&2
    return 1
  fi
}

echo "building the CLI once so publishing does not wait for the compiler"
(cd "$repo_root" && cargo build -q -p cli)
pgrep -x OSWidget >/dev/null || echo "warning: OSWidget is not running; start /Applications/OSWidget.app first"
echo "widget families checked: $families"

check_2() {
  echo
  echo "== 2. A published item reaches the top of the widgets in under 5 s"
  local round start id applied tops f ms worst delays=() bad=0 last_title=""
  for round in 1 2 3 4 5; do
    ((round > 1)) && sleep 40
    start=$(now_stamp)
    last_title="top $round $run_id"
    id=$(publish_note "c2-$round" "$last_title") || { fail "2 top" "round $round publish failed"; return; }
    remember "$id"
    if ! applied=$(first_applied "$start" 30); then
      fail "2 top" "round $round: no sync.applied new>=1 within 30 s"
      return
    fi
    if ! tops=$(wait_top "$start" "$id" 30); then
      fail "2 top" "round $round: timelines with top=$id only for: ${tops:-none}"
      return
    fi
    worst=0
    for f in $tops; do
      ms=$((${f#*=} - ${applied%% *}))
      ((ms > worst)) && worst=$ms
      echo "round $round $id ${f%%=*}: ${ms} ms from sync.applied to widget.timeline"
    done
    delays+=("$worst")
    ((worst < 5000)) || bad=$((bad + 1))
  done
  echo "worst delay per round (ms): ${delays[*]}"
  if ((bad > 0)); then
    fail "2 top" "$bad of 5 rounds took 5 s or more: ${delays[*]} ms"
  elif ask "Is '$last_title' on top of both widgets and at the top of the item list?"; then
    pass "2 top in under 5 s in 5 rounds (worst per round: ${delays[*]} ms); operator saw it on top"
  else
    fail "2 top" "timelines in time (${delays[*]} ms) but the operator did not see the item on top"
  fi
}

# check_tap NAME ACTION: shared body of read and delete.
check_tap() {
  local name="$1" action="$2" title id seq start intent drained deadline ok="" ev
  echo
  title="$name $run_id"
  [[ "$action" == read ]] && echo "== read. The check mark in the widget marks the item read on the server" ||
    echo "== delete. The trash button in the widget deletes the item on the server"
  show_on_widget "c-$name" "$title" || { fail "$name" "the item did not reach the widgets"; return; }
  id="$shown_id"
  seq=$(latest_seq)
  start=$(now_stamp)
  if [[ "$action" == read ]]; then
    echo "TAP: in the widget, click the check mark on '$title' (once)."
  else
    echo "TAP: in the widget, click the trash button on '$title' (once)."
  fi
  if ! intent=$(wait_event "$start" "widget.intent action=$action id=$id" "${TAP_WAIT_SECONDS:-600}"); then
    fail "$name" "no widget.intent action=$action id=$id within ${TAP_WAIT_SECONDS:-600} s (a tap in the app list or popup does not count)"
    return
  fi
  if ! drained=$(wait_event "$start" "widget.inbox_drained" 30); then
    fail "$name" "the app did not drain the inbox within 30 s of the tap"
    return
  fi
  echo "log: ${intent#* } -> ${drained#* } after $((${drained%% *} - ${intent%% *})) ms"
  deadline=$((SECONDS + 30))
  while ((SECONDS < deadline)); do
    if [[ "$action" == read ]]; then
      [[ -n "$(item_field "$id" read_at)" ]] && { ok=1; break; }
    else
      item_present "$id" || { [[ $? == 1 ]] && { ok=1; break; }; }
    fi
    sleep 1
  done
  [[ "$action" == read ]] && ev=item.read || ev=item.deleted
  local ev_seq
  ev_seq=$(event_seq "$seq" "$ev" "$id")
  if [[ -z "$ok" || -z "$ev_seq" ]]; then
    fail "$name" "server after 30 s: state changed '${ok:-no}', $ev seq '${ev_seq}'"
  elif [[ "$action" == read ]] && ! ask "Do both widgets and the item list show '$title' as read (dimmed, no check mark)?"; then
    fail "$name" "server has read_at and $ev seq $ev_seq but the operator did not see it read"
  elif [[ "$action" == delete ]] && ! ask "Is '$title' gone from both widgets and from the item list?"; then
    fail "$name" "server deleted it ($ev seq $ev_seq) but the operator still saw it"
  else
    pass "$name widget tap -> inbox drained -> server $ev seq $ev_seq for $id"
  fi
}

check_offline() {
  echo
  echo "== offline. A tap with Wi-Fi off reaches the server once Wi-Fi is back"
  local title id start intent drained sent deadline read_at="" dropped
  title="offline $run_id"
  show_on_widget c-offline "$title" || { fail "offline" "the item did not reach the widgets"; return; }
  id="$shown_id"
  echo "TAP: turn Wi-Fi off, click the check mark on '$title' in the widget, wait 10 s, turn Wi-Fi on."
  echo "waiting up to ${TAP_WAIT_SECONDS:-600} s for the network to drop"
  deadline=$((SECONDS + ${TAP_WAIT_SECONDS:-600}))
  while server_reachable; do
    ((SECONDS < deadline)) || { fail "offline" "the server stayed reachable for ${TAP_WAIT_SECONDS:-600} s"; return; }
    sleep 1
  done
  dropped=$(now_stamp)
  echo "offline since $dropped"
  if ! intent=$(wait_event "$dropped" "widget.intent action=read id=$id" 600); then
    fail "offline" "no widget.intent action=read id=$id within 10 minutes of going offline"
    return
  fi
  if ! drained=$(wait_event "$dropped" "widget.inbox_drained" 30); then
    fail "offline" "the app did not drain the inbox while offline"
    return
  fi
  echo "log: ${intent#* } -> ${drained#* }"
  sent=$(events "$dropped" "sync.queue_sent id=$id" | head -n 1)
  echo "queue_sent before the network came back: ${sent:-none}"
  echo "waiting up to 10 minutes for the network to come back"
  deadline=$((SECONDS + 600))
  until server_reachable; do
    ((SECONDS < deadline)) || { fail "offline" "the server stayed unreachable for 10 minutes"; return; }
    sleep 2
  done
  echo "online again at $(now_stamp)"
  deadline=$((SECONDS + 60))
  while ((SECONDS < deadline)); do
    read_at=$(item_field "$id" read_at)
    [[ -n "$read_at" ]] && break
    sleep 1
  done
  sent=$(events "$dropped" "sync.queue_sent id=$id" | tail -n 1)
  if [[ -z "$read_at" ]]; then
    fail "offline" "no read_at on the server 60 s after the network came back"
  else
    pass "offline tap drained while offline, read_at $read_at on the server after reconnect (${sent#* })"
  fi
}

check_reload() {
  echo
  echo "== reload. A burst of items causes few reloads, and a quiet sync round causes none"
  local start i id last_id="" reloads n gaps="" prev="" ms bad=0 top quiet_start sync_line after
  sleep 6
  start=$(now_stamp)
  for i in 1 2 3 4 5; do
    id=$(post_item "$(jq -cn --arg r "$run_id" --arg s "$source_name" --arg i "$i" '{v:1, kind:"notification",
      source:$s, title:("burst " + $i + " " + $r), summary:("run " + $r), ttl:3600,
      dedupe_key:($r + "-burst-" + $i)}')") || { fail "reload" "publish $i failed"; return; }
    remember "$id"
    last_id="$id"
    sleep 0.5
  done
  echo "published 5 items; last $last_id; watching 15 s"
  sleep 15
  reloads=$(events "$start" "widget.reload n_today=")
  n=$(grep -c . <<<"$reloads" || true)
  while read -r ms _; do
    [[ -n "$ms" ]] || continue
    if [[ -n "$prev" ]]; then
      gaps+="$((ms - prev)) "
      ((ms - prev >= 5000)) || bad=$((bad + 1))
    fi
    prev=$ms
  done <<<"$reloads"
  top=$(events "$start" "widget.timeline " | tail -n 1)
  echo "reloads: $n, gaps ms: ${gaps:-none}; last timeline: ${top#* }"
  if ((n > 3 || bad > 0)); then
    fail "reload burst" "$n reloads, gaps ${gaps:-none} ms"
  elif [[ "$top" != *"top=$last_id"* ]]; then
    fail "reload burst" "last timeline is not the last item: ${top#* }"
  else
    pass "reload burst: $n reloads for 5 items, gaps ${gaps:-none} ms, last timeline top=$last_id"
  fi

  echo "waiting up to 6 minutes for a sync round with no change"
  quiet_start=$(now_stamp)
  local deadline=$((SECONDS + 360)) found=""
  while ((SECONDS < deadline)) && [[ -z "$found" ]]; do
    sleep 5
    while read -r ms _; do
      [[ -n "$ms" ]] || continue
      sync_line=$(events "$quiet_start" "sync.applied" | awk -v t="$ms" '$1 >= t' | head -n 1)
      if [[ "$sync_line" == *" new=0" ]]; then found="$ms"; break; fi
    done < <(events "$quiet_start" "sync.start")
  done
  if [[ -z "$found" ]]; then
    fail "reload quiet" "no sync round with new=0 within 6 minutes"
    return
  fi
  sleep 7
  after=$(events "$quiet_start" "widget.reload n_today=" | awk -v t="$found" '$1 >= t && $1 <= t + 6000')
  if [[ -n "$after" ]]; then
    fail "reload quiet" "reload after a sync round with no change: ${after#* }"
  else
    pass "reload quiet: no widget.reload within 6 s of a sync round with new=0"
  fi
}

check_checklist() {
  echo
  echo "== checklist. Operator checks that need eyes"
  local start note generic vocab id seq tap read_at deadline i
  # Four older items first, so the large widget has more than its 6 rows to fill.
  for i in 1 2 3 4; do
    id=$(post_item "$(jq -cn --arg r "$run_id" --arg s "$source_name" --arg i "$i" '{v:1, kind:"notification",
      source:$s, title:("filler " + $i + " " + $r), summary:("run " + $r), ttl:3600,
      dedupe_key:($r + "-filler-" + $i)}')") || { fail "checklist" "filler publish failed"; return; }
    remember "$id"
  done
  show_on_widget cl-note "note $run_id" || { fail "checklist" "publish failed"; return; }
  note="$shown_id"
  generic=$(post_item "$(jq -cn --arg r "$run_id" --arg s "$source_name" '{v:1, kind:"generic", source:$s,
    title:("generic " + $r), summary:"a generic item with a longer summary that should be cut short in the widget row",
    ttl:3600, dedupe_key:($r + "-generic"), body:{blocks:[{type:"text", markdown:"generic body"}]}}')") || { fail "checklist" "generic publish failed"; return; }
  remember "$generic"
  vocab=$(post_item "$(jq -cn --arg r "$run_id" --arg s "$source_name" '{v:1, kind:"vocab", source:$s,
    title:("vocab " + $r), summary:"title and summary must show", ttl:3600, dedupe_key:($r + "-vocab"),
    body:{word:"serendipity", ipa:"/ˌser.ənˈdɪp.ə.ti/", pos:"noun",
      meanings:[{definition:"finding good things by chance", examples:["It was pure serendipity."]}]}}')") || { fail "checklist" "vocab publish failed"; return; }
  remember "$vocab"
  start=$(now_stamp)
  wait_top "$start" "$vocab" 30 >/dev/null || echo "note: no timeline with top=$vocab yet"

  confirm "checklist 1" "1. Medium shows 3 rows, large 6 rows, newest on top, and the unread count at the top matches the menu bar badge?" "checklist 1 rows per size, newest on top, unread count"
  confirm "checklist 2" "2. The notification, generic and vocab rows ('vocab $run_id' shows title and summary) fit without text overflow, in both sizes?" "checklist 2 compact rows fit"

  echo "TAP: click the check mark on 'note $run_id' in the widget (marks it read)."
  start=$(now_stamp)
  wait_event "$start" "widget.intent action=read id=$note" 600 >/dev/null || echo "note: no tap logged for 'note $run_id'"
  confirm "checklist 3" "3. Is 'note $run_id' now dimmed with no check mark, while unread rows keep theirs?" "checklist 3 read rows dimmed without check mark"

  echo "STEP: quit OS Widget from its menu bar menu (Quit). Leave it closed."
  deadline=$((SECONDS + 600))
  while pgrep -x OSWidget >/dev/null; do
    ((SECONDS < deadline)) || { fail "checklist 4" "OSWidget still running after 10 minutes"; break; }
    sleep 1
  done
  if ! pgrep -x OSWidget >/dev/null; then
    seq=$(latest_seq)
    echo "TAP: with the app quit, click the check mark on 'generic $run_id' in the widget."
    start=$(now_stamp)
    if tap=$(wait_event "$start" "widget.intent action=read id=$generic" 600); then
      echo "log: ${tap#* } (app running: $(pgrep -x OSWidget >/dev/null && echo yes || echo no))"
      [[ -z "$(item_field "$generic" read_at)" ]] && echo "server: no read_at yet (app closed), as expected"
      if ask "4a. Did the widget show 'generic $run_id' as read right away, with the app quit?"; then
        echo "STEP: open OS Widget again (/Applications/OSWidget.app)."
        deadline=$((SECONDS + 600))
        until pgrep -x OSWidget >/dev/null || ((SECONDS >= deadline)); do sleep 1; done
        deadline=$((SECONDS + 60))
        read_at=""
        while ((SECONDS < deadline)); do
          read_at=$(item_field "$generic" read_at)
          [[ -n "$read_at" ]] && break
          sleep 1
        done
        if [[ -n "$read_at" ]]; then
          pass "checklist 4 tap with the app quit shown at once; sent after reopening (read_at $read_at, item.read seq $(event_seq "$seq" item.read "$generic"))"
        else
          fail "checklist 4" "no read_at on the server 60 s after the app was reopened"
        fi
      else
        fail "checklist 4" "the widget did not update with the app quit"
      fi
    else
      fail "checklist 4" "no tap logged with the app quit"
    fi
  fi

  confirm "checklist 5" "5. Clicking the body of a row (not the buttons) does nothing?" "checklist 5 row body does nothing"
  confirm "checklist 6" "6. Switch System Settings > Appearance to Light, then Dark: both widgets readable in both?" "checklist 6 light and dark readable"
}

case "$which_check" in
  2) check_2 ;;
  read) check_tap read read ;;
  delete) check_tap delete delete ;;
  offline) check_offline ;;
  reload) check_reload ;;
  checklist) check_checklist ;;
  all) check_2; check_tap read read; check_tap delete delete; check_reload ;;
esac

echo
echo "== Summary"
printf '%s\n' "${results[@]}"
echo "widget button taps logged in this run: $(events "$run_started" "widget.intent action=" | grep -c . || true)"
echo "criteria failed: $failures"
[[ "$failures" -eq 0 ]]
