#!/usr/bin/env bash
# chaos-db.sh on|off [latency_ms] — add/remove latency on every Postgres round-trip
# (via toxiproxy, which sits between the app and Postgres in the local overlay).
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
MODE=${1:-on}; LAT=${2:-3000}
if [[ $MODE == on ]]; then
  body="{\"name\":\"latency\",\"type\":\"latency\",\"stream\":\"downstream\",\"attributes\":{\"latency\":$LAT,\"jitter\":0}}"
  args=(-sS -X POST -H "Content-Type: application/json" -d "$body" http://pg-proxy:8474/proxies/postgres/toxics)
else
  args=(-sS -X DELETE http://pg-proxy:8474/proxies/postgres/toxics/latency)
fi
kubectl -n "$NS" run "chaos-$(date +%s)" --rm -i --restart=Never --labels=app=chaos \
  --image=curlimages/curl:8.10.1 --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}}}}' \
  --command -- curl "${args[@]}" || true
log "chaos-db $MODE ${LAT}ms"
