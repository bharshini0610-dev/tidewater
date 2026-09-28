# shellcheck shell=bash
set -euo pipefail
NS=${NS:-settle}
MON_NS=${MON_NS:-monitoring}
INGRESS_URL=${INGRESS_URL:-http://localhost:8080}
PROM_URL=${PROM_URL:-http://localhost:9090}
ts() { date -u +%H:%M:%SZ; }
log() { echo "[$(ts)] $*"; }
summary() { if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then echo "$*" >> "$GITHUB_STEP_SUMMARY"; fi; }
prom_query() {  # prom_query '<promql>' -> first value or "NaN"
  curl -fsS --get "$PROM_URL/api/v1/query" --data-urlencode "query=$1" \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "NaN")' || echo NaN
}
ensure_port_forward() {  # ensure_port_forward <ns> <svc> <local:remote>
  local ns=$1 svc=$2 ports=$3 local_port=${3%%:*}
  if ! curl -s -o /dev/null "http://localhost:${local_port}/" 2>/dev/null; then
    nohup kubectl -n "$ns" port-forward "svc/$svc" "$ports" >/tmp/pf-"$svc".log 2>&1 &
    for _ in $(seq 1 30); do curl -s -o /dev/null "http://localhost:${local_port}/" && return 0; sleep 1; done
    log "port-forward to $svc failed"; cat /tmp/pf-"$svc".log; return 1
  fi
}
