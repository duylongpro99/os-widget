#!/usr/bin/env bash
# Checks the OS Widget menu bar app installed on this Mac against its acceptance criteria.
# Runs on the Mac where the app is installed and reads the app's log here.
#
# Usage: PUBLISH_TOKEN=... CLIENT_TOKEN=... OS_WIDGET_SERVER=<worker-url> \
#          scripts/acceptance-menu-bar.sh <1|3|4|6|focus|all>
#
# Criteria:
#   1      A published notification shows the popup within 5 seconds (latency_ms from the
#          app's "popup.shown" log line, measured from the item's created_at).
#   3      Read state syncs through the server, with a second device simulated by the API:
#          3a  PATCH /items/{id} {"read": true} with the client token reaches the app.
#          3b  Marking read in the app reaches GET /items (read_at) and GET /events (item.read).
#   4      With this Mac offline, three items published from another machine running only
#          the CLI all appear once the network is back, without duplicates.
#   6      An item whose kind the app has no view for (vocab) still shows title and summary.
#   focus  The popup opening while typing in TextEdit does not take focus.
#
# Each criterion prints instructions, publishes test items, checks what it can through the
# API and the app log, then asks the operator to confirm what needs eyes (y/n). Test items use
# source "acceptance-m2", ttl 3600 and a dedupe_key from this run, and are deleted at the end,
# also when the script stops early. Prints PASS or FAIL per criterion and exits 1 if any failed.
# Tokens are never printed: curl reads them from header files only this user can read.
set -euo pipefail

which_check="${1:?usage: PUBLISH_TOKEN=... CLIENT_TOKEN=... OS_WIDGET_SERVER=... $0 <1|3|4|6|focus|all>}"
case "$which_check" in 1 | 3 | 4 | 6 | focus | all) ;; *)
  echo "unknown criterion '$which_check' (want 1, 3, 4, 6, focus or all)" >&2
  exit 2
  ;;
esac
: "${PUBLISH_TOKEN:?PUBLISH_TOKEN must be set}"
: "${CLIENT_TOKEN:?CLIENT_TOKEN must be set}"
: "${OS_WIDGET_SERVER:?OS_WIDGET_SERVER must be set}"
url="${OS_WIDGET_SERVER%/}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }
command -v cargo >/dev/null || { echo "cargo is required" >&2; exit 2; }
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_name="acceptance-m2"
subsystem="local.oswidget.app"

tmp="$(mktemp -d)"
chmod 700 "$tmp"
created=()
failures=0
results=()

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
  printf 'Authorization: Bearer %s\n' "$CLIENT_TOKEN" >"$tmp/client"
)

run_id="m2-$(date +%Y%m%dT%H%M%S)-$$"
echo "run $run_id against $url"

pass() { echo "PASS $1"; results+=("PASS $1"); }
fail() { echo "FAIL $1: $2"; results+=("FAIL $1: $2"); failures=$((failures + 1)); }

# req METHOD URL [BODY]: client-token request; prints the status; the body lands in $tmp/out.
req() {
  local method="$1" target="$2" body="${3-}"
  local args=(-s -m 20 -o "$tmp/out" -w '%{http_code}' -X "$method" -H @"$tmp/client")
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

# publish_note TAG TITLE: publishes a notification from this run; prints its id.
publish_note() {
  local id
  id=$(cli publish --source "$source_name" --title "$2" --summary "run $run_id" \
    --ttl 3600 --dedupe-key "$run_id-$1" 2>"$tmp/cli-err") || {
    echo "CLI publish failed: $(cat "$tmp/cli-err")" >&2
    return 1
  }
  echo "$id"
}

ask() {
  local answer
  while :; do
    read -r -p "$1 [y/n] " answer </dev/tty
    case "$answer" in y | Y) return 0 ;; n | N) return 1 ;; esac
  done
}

wait_enter() { read -r -p "$1 (Enter) " _ </dev/tty; }

now_stamp() { date '+%Y-%m-%d %H:%M:%S'; }

# app_log START PATTERN: app log lines since START whose message contains PATTERN.
app_log() {
  log show --info --debug --style compact --start "$1" \
    --predicate "subsystem == \"$subsystem\" AND eventMessage CONTAINS \"$2\"" 2>/dev/null |
    grep -F -- "$2" || true
}

# wait_log START PATTERN SECONDS: waits for a matching line; prints the first one.
wait_log() {
  local deadline=$((SECONDS + $3)) line
  while ((SECONDS < deadline)); do
    line=$(app_log "$1" "$2" | head -n 1)
    if [[ -n "$line" ]]; then echo "$line"; return 0; fi
    sleep 1
  done
  return 1
}

# wait_applied START SEQ SECONDS: waits for a "sync.applied seq=A..B" line with A <= SEQ <= B.
wait_applied() {
  local deadline=$((SECONDS + $3)) line a b
  while ((SECONDS < deadline)); do
    while read -r line; do
      [[ "$line" =~ sync\.applied\ seq=([0-9]+)\.\.([0-9]+) ]] || continue
      a="${BASH_REMATCH[1]}" b="${BASH_REMATCH[2]}"
      if ((a <= $2 && $2 <= b)); then echo "$line"; return 0; fi
    done < <(app_log "$1" "sync.applied")
    sleep 1
  done
  return 1
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

# front_app: display name of the frontmost app, from the first line of `lsappinfo info`.
front_app() { lsappinfo info "$(lsappinfo front)" | head -n 1 | sed -E 's/^"([^"]*)".*/\1/'; }

server_reachable() { curl -s -m 5 -o /dev/null "$url/" 2>/dev/null; }

echo "building the CLI once so publishing does not wait for the compiler"
(cd "$repo_root" && cargo build -q -p cli)
pgrep -x OSWidget >/dev/null || echo "warning: OSWidget is not running; start /Applications/OSWidget.app first"
echo "before starting: close the item list, turn quiet mode off and leave popups on for every kind."

check_1() {
  echo
  echo "== 1. Popup within 5 seconds"
  local start id line latency
  start=$(now_stamp)
  id=$(publish_note c1 "popup $run_id") || { fail "1 popup" "publish failed"; return; }
  remember "$id"
  echo "published $id; waiting for popup.shown"
  if ! line=$(wait_log "$start" "popup.shown id=$id" 30); then
    fail "1 popup" "no popup.shown for $id within 30 s"
    return
  fi
  latency=$(sed -nE 's/.*latency_ms=(-?[0-9]+).*/\1/p' <<<"$line")
  echo "log: ${line#*popup.shown}"
  if ! ask "Did a popup appear titled 'popup $run_id'?"; then
    fail "1 popup" "operator did not see the popup (latency_ms=$latency)"
  elif [[ -n "$latency" ]] && ((latency <= 5000)); then
    pass "1 popup shown for $id, latency_ms=$latency (<= 5000)"
  else
    fail "1 popup" "latency_ms=$latency (> 5000)"
  fi
}

check_3a() {
  echo
  echo "== 3a. Read on another device (simulated by the API) reaches this Mac"
  local seq start id created_seq read_seq code line
  seq=$(latest_seq)
  start=$(now_stamp)
  id=$(publish_note c3a "read elsewhere $run_id") || { fail "3a read from API" "publish failed"; return; }
  remember "$id"
  created_seq=$(event_seq "$seq" item.created "$id")
  if ! wait_applied "$start" "${created_seq:-0}" 30 >/dev/null; then
    fail "3a read from API" "the app did not apply item.created seq $created_seq within 30 s"
    return
  fi
  echo "the app has 'read elsewhere $run_id' as unread. Open the item list to watch it."
  wait_enter "List open?"
  seq=$(latest_seq)
  start=$(now_stamp)
  code=$(req PATCH "$url/items/$id" '{"read":true}')
  [[ "$code" == 204 ]] || { fail "3a read from API" "PATCH read -> $code"; return; }
  read_seq=$(event_seq "$seq" item.read "$id")
  if ! line=$(wait_applied "$start" "${read_seq:-0}" 30); then
    fail "3a read from API" "no sync.applied covering item.read seq $read_seq within 30 s"
    return
  fi
  echo "log: ${line#*sync.applied}"
  if ask "Within a few seconds, did 'read elsewhere $run_id' turn read and the unread badge drop?"; then
    pass "3a PATCH read (seq $read_seq) applied by the app; operator saw the item turn read"
  else
    fail "3a read from API" "app applied seq $read_seq but the operator did not see it turn read"
  fi
}

check_3b() {
  echo
  echo "== 3b. Read on this Mac reaches the server"
  local seq start id created_seq deadline read_at=""
  seq=$(latest_seq)
  start=$(now_stamp)
  id=$(publish_note c3b "read here $run_id") || { fail "3b read from app" "publish failed"; return; }
  remember "$id"
  created_seq=$(event_seq "$seq" item.created "$id")
  if ! wait_applied "$start" "${created_seq:-0}" 30 >/dev/null; then
    fail "3b read from app" "the app did not apply item.created seq $created_seq within 30 s"
    return
  fi
  wait_enter "In the item list, click 'Đã đọc' on 'read here $run_id', then press"
  deadline=$((SECONDS + 30))
  while ((SECONDS < deadline)); do
    if [[ "$(req GET "$url/items")" == 200 ]]; then
      read_at=$(jq -r --arg id "$id" '.items[] | select(.id == $id) | .read_at // empty' "$tmp/out")
      [[ -n "$read_at" ]] && break
    fi
    sleep 1
  done
  local read_seq
  read_seq=$(event_seq "$seq" item.read "$id")
  if [[ -z "$read_at" || -z "$read_seq" ]]; then
    fail "3b read from app" "read_at '${read_at}', item.read seq '${read_seq}' after 30 s"
  elif ask "Did you click 'Đã đọc' on that card (and only once)?"; then
    pass "3b GET /items read_at set and GET /events item.read seq $read_seq for $id"
  else
    fail "3b read from app" "server shows read but the operator did not mark it"
  fi
}

check_4() {
  echo
  echo "== 4. Offline, three items, no duplicates"
  local n start ids=() count line
  echo "Turn Wi-Fi off on this Mac (and any Ethernet or phone tethering)."
  while server_reachable || ping -c 1 -t 2 1.1.1.1 >/dev/null 2>&1; do
    wait_enter "This Mac still reaches the network. Turn it off, then press"
  done
  echo "offline: ping and the server both fail."
  echo "On another machine that runs only the CLI, with OS_WIDGET_PUBLISH_TOKEN set there, run:"
  for n in 1 2 3; do
    echo "  OS_WIDGET_SERVER=$url os-widget publish --source $source_name --title 'offline $n $run_id'" \
      "--summary 'run $run_id' --ttl 3600 --dedupe-key $run_id-c4-$n"
  done
  echo "(from a checkout: cargo run -q -p cli -- publish ... in place of os-widget publish)"
  wait_enter "All three published on the other machine?"
  echo "Turn the network back on."
  start=$(now_stamp)
  until server_reachable; do sleep 2; done
  echo "online again; waiting for the app to catch up"
  if [[ "$(req GET "$url/items")" == 200 ]]; then
    while read -r n; do ids+=("$n"); remember "$n"; done < <(jq -r --arg r "$run_id" \
      '.items[] | select(.source == "acceptance-m2" and (.title | test("^offline [123] " + $r + "$"))) | .id' "$tmp/out")
  fi
  count=${#ids[@]}
  line=$(wait_log "$start" "popup.shown" 60 || true)
  [[ -n "$line" ]] && echo "log: ${line#*popup.shown}"
  if [[ "$count" != 3 ]]; then
    fail "4 offline" "GET /items has $count of the three offline items"
  elif ask "Does the list show 'offline 1/2/3 $run_id' each exactly once, and the popup the newest with '+2 mục khác'?"; then
    pass "4 three offline items on the server and in the list once each; popup: ${line#*popup.shown }"
  else
    fail "4 offline" "server has the three items but the operator saw a missing, duplicated or wrong popup"
  fi
}

check_6() {
  echo
  echo "== 6. Unknown kind shows title and summary"
  local seq start id created_seq file="$tmp/vocab.json"
  jq -n --arg r "$run_id" --arg s "$source_name" '{v:1, kind:"vocab", source:$s,
    title:("vocab " + $r), summary:"title and summary must show", ttl:3600, dedupe_key:($r + "-c6"),
    body:{word:"serendipity", ipa:"/ˌser.ənˈdɪp.ə.ti/", pos:"noun",
      meanings:[{definition:"finding good things by chance", examples:["It was pure serendipity."]}]}}' >"$file"
  seq=$(latest_seq)
  start=$(now_stamp)
  id=$(cli publish --file "$file" 2>"$tmp/cli-err") || { fail "6 unknown kind" "publish failed: $(cat "$tmp/cli-err")"; return; }
  remember "$id"
  created_seq=$(event_seq "$seq" item.created "$id")
  if ! wait_applied "$start" "${created_seq:-0}" 30 >/dev/null; then
    fail "6 unknown kind" "the app did not apply item.created seq $created_seq within 30 s"
    return
  fi
  if ask "Does the card 'vocab $run_id' show its title and the summary 'title and summary must show', with no error?"; then
    pass "6 vocab item $id shown with title and summary by the fallback view"
  else
    fail "6 unknown kind" "operator did not see title and summary for $id"
  fi
}

check_focus() {
  echo
  echo "== Focus. The popup does not take focus from TextEdit"
  local i before after start id line
  echo "Open TextEdit, click into a document and keep typing until the popup has appeared."
  wait_enter "Ready to type?"
  for i in 10 9 8 7 6 5 4 3 2 1; do printf '%s ' "$i"; sleep 1; done
  echo
  before=$(front_app)
  start=$(now_stamp)
  id=$(publish_note focus "focus $run_id") || { fail "focus" "publish failed"; return; }
  remember "$id"
  if ! line=$(wait_log "$start" "popup.shown id=$id" 30); then
    fail "focus" "no popup.shown for $id within 30 s"
    return
  fi
  after=$(front_app)
  echo "front app before: $before, after popup.shown: $after"
  if [[ "$before" != TextEdit || "$after" != TextEdit ]]; then
    fail "focus" "front app before '$before', after '$after' (want TextEdit both)"
  elif ask "Did the characters you typed keep going into TextEdit while the popup showed?"; then
    pass "focus front app TextEdit before and after popup.shown; typing stayed in TextEdit"
  else
    fail "focus" "front app stayed TextEdit but the operator saw typing interrupted"
  fi
}

case "$which_check" in
  1) check_1 ;;
  3) check_3a; check_3b ;;
  4) check_4 ;;
  6) check_6 ;;
  focus) check_focus ;;
  all) check_1; check_3a; check_3b; check_4; check_6; check_focus ;;
esac

echo
echo "== Summary"
printf '%s\n' "${results[@]}"
echo "criteria failed: $failures"
[[ "$failures" -eq 0 ]]
