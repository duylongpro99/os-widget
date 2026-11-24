#!/usr/bin/env bash
# Counts the widget reloads the app asked for and the timelines the widget ran, over a period of the
# unified log, and says whether the numbers meet the reload budget.
#
# Usage:
#   scripts/widget-reload-count.sh [--last 24h]
#   scripts/widget-reload-count.sh --start "YYYY-MM-DD HH:MM:SS" [--end "YYYY-MM-DD HH:MM:SS"]
#   scripts/widget-reload-count.sh --input <file.ndjson>      # a saved `log show --style ndjson`
#
# Lines read (subsystem local.oswidget.app, category widget):
#   widget.reload n_today=<n> reason=<first|changed|trailing> gap_ms=<ms>   one per request from the app
#   widget.timeline family=<medium|large> items=<n> unread=<n> top=<id>     one per timeline run
# Each request is paired with the first timeline that runs after it. Timelines the system runs on its
# own (the widget appearing on the desktop, a button tap) count in `timelines` and are not errors.
#
# The last line is the summary used against the budget:
#   requests=<n> min_gap_ms=<n|none> within_5s=<pct> timelines=<n> verdict=<PASS|FAIL>
# PASS needs at most 40 requests, no two closer than 5000 ms, and at least 95% of requests followed by
# a timeline within 5 s. Override with MAX_REQUESTS, MIN_GAP_MS and MIN_WITHIN_PCT.
#
# Expected output for scripts/testdata/widget-log-sample.ndjson:
#   requests=7 (first=1 changed=4 trailing=2)
#   per hour: 08:1 09:1 10:4 14:1
#   timelines=9, min_gap_ms=5000
#   delay to next timeline: p50=200 p95=8000 max=8000 ms; without timeline in 5 s: 1 of 7
#   requests=7 min_gap_ms=5000 within_5s=85.7 timelines=9 verdict=FAIL

set -euo pipefail

SUBSYSTEM="local.oswidget.app"
CATEGORY="widget"
MAX_REQUESTS="${MAX_REQUESTS:-40}"
MIN_GAP_MS="${MIN_GAP_MS:-5000}"
MIN_WITHIN_PCT="${MIN_WITHIN_PCT:-95}"

last="24h"
start=""
end=""
input=""

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --last) last="${2:?--last needs a value}"; shift 2 ;;
    --start) start="${2:?--start needs a value}"; shift 2 ;;
    --end) end="${2:?--end needs a value}"; shift 2 ;;
    --input) input="${2:?--input needs a file}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown argument: $1" >&2; usage ;;
  esac
done

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

read_log() {
  if [[ -n "$input" ]]; then
    cat "$input"
    return
  fi
  local args=(show --style ndjson --info --predicate "subsystem == \"$SUBSYSTEM\" AND category == \"$CATEGORY\"")
  if [[ -n "$start" ]]; then
    args+=(--start "$start")
    [[ -n "$end" ]] && args+=(--end "$end")
  else
    args+=(--last "$last")
  fi
  /usr/bin/log "${args[@]}"
}

read_log | jq -rsR \
  --argjson maxRequests "$MAX_REQUESTS" \
  --argjson minGap "$MIN_GAP_MS" \
  --argjson minWithin "$MIN_WITHIN_PCT" \
  --arg subsystem "$SUBSYSTEM" \
  --arg category "$CATEGORY" '
  # "2026-11-24 08:00:00.400000+0700" -> epoch milliseconds
  def epoch_ms:
    capture("^(?<date>[0-9-]+ [0-9:]+)(?:\\.(?<frac>[0-9]+))?(?<sign>[+-])(?<oh>[0-9]{2})(?<om>[0-9]{2})$") as $t
    | ((($t.date | sub(" "; "T")) + "Z" | fromdate) * 1000
       + (((($t.frac // "0") + "000")[0:3]) | tonumber)
       - (($t.oh | tonumber) * 3600 + ($t.om | tonumber) * 60) * 1000 * (if $t.sign == "+" then 1 else -1 end));

  def percentile($sorted; $p):
    if ($sorted | length) == 0 then null
    else $sorted[(((($sorted | length) * $p) | ceil) - 1) | if . < 0 then 0 else . end]
    end;

  [ split("\n")[] | select(length > 0) | (try fromjson catch empty)
    | select(.subsystem == $subsystem and .category == $category)
    | select(.timestamp != null and .eventMessage != null)
    | {at: (.timestamp | epoch_ms), hour: (.timestamp[11:13]), msg: .eventMessage} ] as $events
  | [ $events[] | select(.msg | test("^widget\\.reload ")) ] | sort_by(.at) as $requests
  | [ $events[] | select(.msg | test("^widget\\.timeline ")) ] | sort_by(.at) as $timelines
  | ($requests | map(.msg | capture("reason=(?<r>[a-z]+)").r)) as $reasons
  | ([ range(1; $requests | length) | $requests[.].at - $requests[. - 1].at ]) as $gaps
  | ($gaps | min) as $minGap_ms
  | ($requests | map(
        .at as $t
        | ([ $timelines[] | select(.at >= $t) ][0].at) as $next
        | if $next == null then null else $next - $t end)) as $delays
  | ($delays | map(select(. != null)) | sort) as $sorted
  | ($delays | map(select(. != null and . <= 5000)) | length) as $within
  | ($requests | length) as $n
  | (if $n == 0 then 100 else ($within * 1000 / $n | round) / 10 end) as $pct
  | (if $n <= $maxRequests and ($minGap_ms == null or $minGap_ms >= $minGap) and $pct >= $minWithin
     then "PASS" else "FAIL" end) as $verdict
  | "requests=\($n) (first=\($reasons | map(select(. == "first")) | length) changed=\($reasons | map(select(. == "changed")) | length) trailing=\($reasons | map(select(. == "trailing")) | length))",
    "per hour: " + (if $n == 0 then "none" else ($requests | group_by(.hour) | map("\(.[0].hour):\(length)") | join(" ")) end),
    "timelines=\($timelines | length), min_gap_ms=\($minGap_ms // "none")",
    "delay to next timeline: p50=\(percentile($sorted; 0.5) // "n/a") p95=\(percentile($sorted; 0.95) // "n/a") max=\($sorted | max // "n/a") ms; without timeline in 5 s: \($n - $within) of \($n)",
    "requests=\($n) min_gap_ms=\($minGap_ms // "none") within_5s=\($pct) timelines=\($timelines | length) verdict=\($verdict)"
'
