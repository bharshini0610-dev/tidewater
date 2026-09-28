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
v=$(curl -s -m 5 "$INGRESS_URL/version")
c=$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$INGRESS_URL/settlements?limit=5")
log "after rollback: version=$v GET /settlements=$c"
summary "### Automatic rollback"
summary "- \`kubectl rollout undo\` → serving \`$v\`, \`GET /settlements\` → **$c**"
[[ $c == 200 ]]
