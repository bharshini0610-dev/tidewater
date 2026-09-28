#!/usr/bin/env bash
# deploy.sh <image@sha256:digest> <version>
# 1. secrets  2. migration Job with the SAME image (expand-only, must succeed first)
# 3. apply manifests pinned to the digest  4. wait for the rollout
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=${1:?image@digest}
VERSION=${2:?version}
[[ "$IMAGE" == *@sha256:* || -n "${ALLOW_TAG:-}" ]] || { echo "refusing to deploy a mutable tag: $IMAGE"; exit 1; }
RELEASE_ID=$(echo "$VERSION-$(date +%s)" | tr '.' '-' | tr '[:upper:]' '[:lower:]')

"$ROOT/scripts/create-secrets.sh"

WORK=$(mktemp -d)
cp -r "$ROOT/deploy" "$WORK/"
# The mock bank keeps the image it was first deployed with, so its payout ledger survives
# application releases (and rollbacks) and verification can assert "nobody paid twice".
MOCKBANK_IMAGE=$(kubectl -n "$NS" get deploy mockbank -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true)
( cd "$WORK/deploy/k8s/overlays/local" && kustomize edit set image "settle-api=${IMAGE}" "settle-mockbank=${MOCKBANK_IMAGE:-$IMAGE}" )

# Infra (postgres/redis/...) must exist before the migration Job can run.
kubectl kustomize "$WORK/deploy/k8s/overlays/local" > "$WORK/all.yaml"
python3 - "$WORK/all.yaml" "$WORK" <<'PY'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
app = {"settle-api", "settle-worker"}
infra = [d for d in docs if not (d["kind"] in ("Deployment", "HorizontalPodAutoscaler") and d["metadata"]["name"] in app)]
apps = [d for d in docs if d not in infra]
yaml.safe_dump_all(infra, open(f"{sys.argv[2]}/infra.yaml", "w"))
yaml.safe_dump_all(apps, open(f"{sys.argv[2]}/apps.yaml", "w"))
PY
kubectl apply -f "$WORK/infra.yaml" >/dev/null
kubectl -n "$NS" rollout status statefulset/postgres --timeout=180s
kubectl -n "$NS" rollout status deployment/redis deployment/toxiproxy --timeout=120s

log "running migrations for $VERSION"
IMAGE="$IMAGE" RELEASE_ID="$RELEASE_ID" envsubst < "$ROOT/deploy/k8s/jobs/migrate.yaml" | kubectl -n "$NS" apply -f - >/dev/null
if ! kubectl -n "$NS" wait --for=condition=complete "job/settle-migrate-$RELEASE_ID" --timeout=240s; then
  kubectl -n "$NS" logs "job/settle-migrate-$RELEASE_ID" --tail=50 || true
  log "migration failed -> not rolling out $VERSION (running version untouched)"
  exit 1
fi
kubectl -n "$NS" logs "job/settle-migrate-$RELEASE_ID" --tail=20

log "rolling out $VERSION ($IMAGE)"
kubectl apply -f "$WORK/apps.yaml"
kubectl -n "$NS" annotate deployment/settle-api deployment/settle-worker --overwrite \
  kubernetes.io/change-cause="deploy $VERSION $IMAGE" >/dev/null
kubectl -n "$NS" rollout status deployment/settle-api --timeout=180s
kubectl -n "$NS" rollout status deployment/settle-worker --timeout=180s
kubectl -n "$NS" rollout status deployment/mockbank --timeout=120s
log "rollout of $VERSION complete"
