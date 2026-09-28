#!/usr/bin/env bash
# load.sh <seconds> — steady mixed traffic through the ingress (like real clients).
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
DURATION=${1:-60}
end=$((SECONDS + DURATION))
i=0
while (( SECONDS < end )); do
  i=$((i + 1))
  curl -s -o /dev/null -m 5 -H "X-Request-ID: load-$i" "$INGRESS_URL/settlements?limit=20" &
  curl -s -o /dev/null -m 5 "$INGRESS_URL/version" &
  if (( i % 5 == 0 )); then
    curl -s -o /dev/null -m 5 -X POST -H "X-Request-ID: load-post-$i" \
      "$INGRESS_URL/settlements?merchant_id=$(( (i / 5) % 20 + 1 ))" &
  fi
  sleep 0.2
done
wait
