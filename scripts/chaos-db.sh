#!/usr/bin/env bash
# chaos-db.sh on|off [latency_ms] — add/remove latency on every Postgres round-trip.
# toxiproxy sits between the app and Postgres in the local overlay; its admin API is
# reached through a kubectl port-forward (not exposed to other pods).
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
MODE=${1:-on}; LAT=${2:-3000}
ensure_port_forward "$NS" pg-proxy 8474:8474
if [[ $MODE == on ]]; then
  curl -fsS -X POST -H "Content-Type: application/json" \
    -d "{\"name\":\"latency\",\"type\":\"latency\",\"stream\":\"downstream\",\"attributes\":{\"latency\":$LAT,\"jitter\":0}}" \
    http://localhost:8474/proxies/postgres/toxics >/dev/null
else
  curl -sS -X DELETE http://localhost:8474/proxies/postgres/toxics/latency >/dev/null || true
fi
curl -fsS http://localhost:8474/proxies/postgres/toxics
echo
log "chaos-db $MODE ${LAT}ms"
