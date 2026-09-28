#!/usr/bin/env bash
# verify.sh <expected-version>
# Post-deploy verification. Every check runs; the release passes only if all pass.
#  1 rollout healthy        4 POST /settlements 202     7 new pods: 5xx ratio < 1%
#  2 /readyz + /version     5 GET /reports/daily 200    8 new pods: p99 < 1 s
#  3 GET /settlements 200   6 soak under load           9 no merchant paid twice
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
EXPECTED=${1:?expected version}
set +e   # every check must run and be reported, even if an earlier one fails
SOAK=${SOAK_SECONDS:-90}
fail=0
declare -a rows
check() {  # check <name> <ok:0/1> <detail>
  local status="PASS"; [[ "$2" == 1 ]] || { status="FAIL"; fail=1; }
  rows+=("| $1 | $status | $3 |"); log "$status  $1 — $3"
}

ensure_port_forward "$MON_NS" kps-kube-prometheus-stack-prometheus 9090:9090
HASH=$(kubectl -n "$NS" get rs -l app=settle-api -o json | python3 -c '
import json,sys
rs=[r for r in json.load(sys.stdin)["items"] if (r["spec"].get("replicas") or 0)>0]
rs.sort(key=lambda r:int(r["metadata"]["annotations"].get("deployment.kubernetes.io/revision","0")))
print(rs[-1]["metadata"]["labels"]["pod-template-hash"])')

ok=1; kubectl -n "$NS" rollout status deployment/settle-api --timeout=10s >/dev/null || ok=0
check "rollout status (readiness)" $ok "ReplicaSet $HASH"

v=$(curl -s -m 5 "$INGRESS_URL/version" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version"))' 2>/dev/null || echo none)
r=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$INGRESS_URL/readyz")
check "/readyz and /version" "$([[ $r == 200 && $v == "$EXPECTED" ]] && echo 1 || echo 0)" "readyz=$r version=$v expected=$EXPECTED"

log "soak: ${SOAK}s of mixed traffic"
"$ROOT/scripts/load.sh" "$SOAK"
sleep 20   # two scrape intervals so the last requests are in Prometheus

codes=""; ok=1
for _ in 1 2 3; do c=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$INGRESS_URL/settlements?limit=5"); codes+="$c "; [[ $c == 200 ]] || ok=0; done
check "GET /settlements x3" $ok "HTTP $codes"

c=$(curl -s -o /dev/null -w '%{http_code}' -m 5 -X POST -H 'X-Request-ID: verify-post-1' "$INGRESS_URL/settlements?merchant_id=1")
check "POST /settlements" "$([[ $c == 202 ]] && echo 1 || echo 0)" "HTTP $c"

c=$(curl -s -o /dev/null -w '%{http_code} %{time_total}s' -m 25 "$INGRESS_URL/reports/daily")
check "GET /reports/daily" "$([[ ${c%% *} == 200 ]] && echo 1 || echo 0)" "HTTP $c"

err=$(prom_query "sum(rate(settle_http_requests_total{pod_template_hash=\"$HASH\",status=~\"5..\"}[2m])) / sum(rate(settle_http_requests_total{pod_template_hash=\"$HASH\"}[2m]))")
[[ $err == NaN ]] && err=0
check "5xx ratio, new pods, 2m" "$(python3 -c "print(1 if float('$err') < 0.01 else 0)")" "$(python3 -c "print(f'{float(\"$err\"):.2%}')") (threshold 1%)"

p99=$(prom_query "histogram_quantile(0.99, sum by (le) (rate(settle_http_request_duration_seconds_bucket{pod_template_hash=\"$HASH\",route!=\"/reports/daily\"}[2m])))")
check "p99 latency, new pods, excl. reports" "$(python3 -c "import math; v=float('$p99'); print(1 if not math.isnan(v) and v < 1.0 else 0)")" "${p99}s (threshold 1s)"

stats=$(kubectl -n "$NS" exec deploy/mockbank -- python -c 'import urllib.request;print(urllib.request.urlopen("http://localhost:8080/stats").read().decode())')
dups=$(echo "$stats" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["paid_more_than_once"]))' 2>/dev/null || echo unknown)
check "no merchant paid twice (bank ledger)" "$([[ $dups == 0 ]] && echo 1 || echo 0)" "$stats"

summary "### Post-deploy verification — $EXPECTED"
summary "| Check | Result | Detail |"
summary "|---|---|---|"
for row in "${rows[@]}"; do summary "$row"; done
printf '%s\n' "${rows[@]}" > /tmp/verify-"$EXPECTED".md
[[ $fail == 0 ]] && log "VERIFICATION PASSED for $EXPECTED" || log "VERIFICATION FAILED for $EXPECTED"
exit $fail
