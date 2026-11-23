#!/usr/bin/env bash
# Sends a sequential load to a deployed os-widget Worker so its per-request CPU
# time can be read from Cloudflare telemetry.
#
# Usage: PUBLISH_TOKEN=... CLIENT_TOKEN=... scripts/measure-worker.sh <worker-url> [count]
#   1. <count> POST /items with distinct titles and a null dedupe_key, using the
#      publish token.
#   2. One GET /items to read the latest seq (filter it out of the CPU data by
#      its path).
#   3. <count> GET /events?since=<latest seq - 5>, using the client token.
# Prints the number of non-2xx responses per endpoint and exits 1 if any.
set -euo pipefail

url="${1:?usage: PUBLISH_TOKEN=... CLIENT_TOKEN=... $0 <worker-url> [count]}"
url="${url%/}"
count="${2:-150}"
: "${PUBLISH_TOKEN:?PUBLISH_TOKEN must be set}"
: "${CLIENT_TOKEN:?CLIENT_TOKEN must be set}"
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

# Keep the tokens out of the process list: curl reads the headers from files
# only this user can read.
hdr_dir="$(mktemp -d)"
trap 'rm -rf "$hdr_dir"' EXIT
chmod 700 "$hdr_dir"
publish_hdr="$hdr_dir/publish"
client_hdr="$hdr_dir/client"
(
  umask 077
  printf 'Authorization: Bearer %s\n' "$PUBLISH_TOKEN" >"$publish_hdr"
  printf 'Authorization: Bearer %s\n' "$CLIENT_TOKEN" >"$client_hdr"
)

run_id="$(date +%Y%m%dT%H%M%S)"
post_errors=0
get_errors=0

echo "run $run_id: $count POST /items"
for i in $(seq 1 "$count"); do
  body=$(jq -cn --arg t "measure $run_id #$i" \
    '{v:1, kind:"notification", source:"measure-worker", title:$t, summary:"cpu measurement", dedupe_key:null, body:{}}')
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H @"$publish_hdr" -H 'Content-Type: application/json' \
    --data "$body" "$url/items") || code=000
  [[ "$code" == 2* ]] || { post_errors=$((post_errors + 1)); echo "POST #$i -> $code" >&2; }
done

latest=$(curl -sf -H @"$client_hdr" "$url/items" | jq '.seq') || {
  echo "GET /items failed (POST /items errors so far: $post_errors)" >&2
  exit 1
}
since=$((latest > 5 ? latest - 5 : 0))

echo "run $run_id: $count GET /events?since=$since (latest seq $latest)"
for i in $(seq 1 "$count"); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -H @"$client_hdr" "$url/events?since=$since") || code=000
  [[ "$code" == 2* ]] || { get_errors=$((get_errors + 1)); echo "GET #$i -> $code" >&2; }
done

echo "errors: POST /items $post_errors, GET /events $get_errors, total $((post_errors + get_errors))"
[[ $((post_errors + get_errors)) -eq 0 ]]
