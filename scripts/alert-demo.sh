#!/usr/bin/env bash
# Show one alert firing end-to-end (and Task F: graceful degradation under a slow DB).
# 3 s latency on every Postgres round-trip + normal traffic ->
#   SettleApiErrorBudgetBurn fires; API pods are NOT restarted (liveness is process-local);
#   latency removed -> service recovers without any manual action.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
ALERT=${ALERT:-SettleApiErrorBudgetBurn}
ensure_port_forward "$MON_NS" kps-kube-prometheus-stack-prometheus 9090:9090
restarts() { kubectl -n "$NS" get pods -l app=settle-api -o jsonpath='{range .items[*]}{.status.containerStatuses[0].restartCount}{"\n"}{end}' | awk '{s+=$1} END {print s+0}'; }
before=$(restarts)
t0=$(date -u +%H:%M:%S)
"$ROOT/scripts/load.sh" 900 >/dev/null 2>&1 &
LOAD=$!
trap 'kill $LOAD 2>/dev/null || true' EXIT
sleep 30
"$ROOT/scripts/chaos-db.sh" on 3000
t_chaos=$(date -u +%H:%M:%S); s_chaos=$SECONDS
state=inactive
for _ in $(seq 1 60); do
  state=$(curl -s "$PROM_URL/api/v1/alerts" | python3 -c "
import json,sys
a=[x for x in json.load(sys.stdin)['data']['alerts'] if x['labels']['alertname']=='$ALERT']
print(a[0]['state'] if a else 'inactive')")
  log "$ALERT: $state   error ratio 5m=$(prom_query 'settle:slo_error_ratio:rate5m')  api restarts=$(restarts)"
  [[ $state == firing ]] && break
  sleep 10
done
t_fire=$(date -u +%H:%M:%S); s_fire=$SECONDS
curl -s "$PROM_URL/api/v1/alerts" | python3 -m json.tool > /tmp/alerts-firing.json
if [[ -n "${SCREENSHOT_DIR:-}" ]]; then python3 "$ROOT/scripts/screenshots.py" firing "$SCREENSHOT_DIR" || true; fi
"$ROOT/scripts/chaos-db.sh" off
sleep 90
err_after=$(prom_query 'sum(rate(settle_http_requests_total{status=~"5.."}[1m])) / sum(rate(settle_http_requests_total[1m]))')
p99_after=$(prom_query 'histogram_quantile(0.99, sum by (le) (rate(settle_http_request_duration_seconds_bucket{route!="/reports/daily"}[1m])))')
after=$(restarts)
kill $LOAD 2>/dev/null || true
summary "### Alert demo — $ALERT (chaos-db: +3 s per Postgres round-trip)"
summary "| Step | Time (UTC) | Observation |"
summary "|---|---|---|"
summary "| traffic started | $t0 | load.sh through ingress |"
summary "| latency injected | $t_chaos | toxiproxy latency toxic 3000 ms |"
summary "| alert **$state** | $t_fire | $((s_fire - s_chaos)) s after injection |"
summary "| latency removed + 90 s | $(date -u +%H:%M:%S) | 5xx ratio 1m = $err_after, p99 = ${p99_after}s |"
summary "| API container restarts | — | before: $before, after: $after (liveness does not depend on Postgres) |"
log "alert $ALERT state=$state after $((s_fire - s_chaos))s; restarts $before -> $after"
[[ $state == firing && $after == "$before" ]]
