#!/usr/bin/env bash
# Automatic rollback: previous ReplicaSet (same schema-compatible image), no down-migration.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
log "ROLLING BACK settle-api and settle-worker"
kubectl -n "$NS" rollout undo deployment/settle-api
kubectl -n "$NS" rollout undo deployment/settle-worker
kubectl -n "$NS" rollout status deployment/settle-api --timeout=180s
kubectl -n "$NS" rollout status deployment/settle-worker --timeout=180s
kubectl -n "$NS" rollout history deployment/settle-api | tail -4
# Wait until the rejected pods have finished terminating (preStop keeps them serving ~10 s).
for app in settle-api settle-worker; do
  hash=$(kubectl -n "$NS" get rs -l app=$app -o json | python3 -c '
import json,sys
rs=[r for r in json.load(sys.stdin)["items"] if (r["spec"].get("replicas") or 0)>0]
rs.sort(key=lambda r:int(r["metadata"]["annotations"].get("deployment.kubernetes.io/revision","0")))
print(rs[-1]["metadata"]["labels"]["pod-template-hash"])')
  kubectl -n "$NS" wait --for=delete pod -l "app=$app,pod-template-hash!=$hash" --timeout=120s >/dev/null 2>&1 || true
done
sleep 5
v=$(curl -s -m 5 "$INGRESS_URL/version")
c=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$INGRESS_URL/settlements?limit=5")
log "after rollback: version=$v GET /settlements=$c"
summary "### Automatic rollback"
summary "- \`kubectl rollout undo\` → serving \`$v\`, \`GET /settlements\` → **$c**"
[[ $c == 200 ]]
