#!/bin/bash
# Show the full event timeline for one session.
# Usage: bash session_log.sh <sessionId>
#   or:  bash session_log.sh latest          # last 20 sessions seen
#   or:  bash session_log.sh user <userId>   # all sessions for one user

set -e
DIR="$(dirname "$0")/../data/reports"

if [ "$1" = "latest" ]; then
  ls -t "$DIR"/*.json 2>/dev/null | head -50 | \
    xargs -I{} sh -c 'jq -r "[.time, .sessionId, (.userId|tostring), .type, (.logs[0]//\"\")] | @tsv" "{}"' | \
    sort -u -k2,2 | head -20
  exit 0
fi

if [ "$1" = "user" ]; then
  uid="$2"
  echo "Sessions for user $uid:"
  for f in "$DIR"/*.json; do
    jq -r --arg uid "$uid" 'select(.userId == ($uid|tonumber)) | "\(.time)\t\(.sessionId)\t\(.type)"' "$f" 2>/dev/null
  done | sort -u
  exit 0
fi

sid="$1"
if [ -z "$sid" ]; then
  echo "Usage: $0 <sessionId> | latest | user <userId>"
  exit 1
fi

echo "=== Session $sid ==="
ls -1 "$DIR/${sid}_"*.json 2>/dev/null | sort | while read f; do
  jq -r '"[\(.time)] \(.type): \(.logs|join(" | "))"' "$f"
done
