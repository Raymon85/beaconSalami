#!/usr/bin/env bash
# Checks that the app responds with 200 on the given URL.
# Usage: ./scripts/health-check.sh <url> [attempts]

set -euo pipefail

URL="${1:?Provide the URL as the first argument}"
ATTEMPTS="${2:-10}"
DELAY=5

echo "Checking $URL"
echo "Max $ATTEMPTS attempts, $DELAY seconds apart"

for i in $(seq 1 "$ATTEMPTS"); do
  STATUS=$(curl \
    --silent \
    --output /dev/null \
    --write-out "%{http_code}" \
    --max-time 10 "$URL" || true)

  if [ "$STATUS" = "200" ]; then
    echo "OK: app responded 200 on attempt $i."
    exit 0
  fi

  # No point waiting after the last attempt - there is nothing left to wait for.
  if [ "$i" -lt "$ATTEMPTS" ]; then
    echo "Attempt $i of $ATTEMPTS: got status $STATUS. Waiting $DELAY s..."
    sleep "$DELAY"
  else
    echo "Attempt $i of $ATTEMPTS: got status $STATUS. Giving up."
  fi
done

echo "FAILED: app never responded 200 after $ATTEMPTS attempts."
exit 1