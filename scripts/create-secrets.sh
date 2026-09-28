#!/usr/bin/env bash
# Creates the runtime secrets at deploy time. Nothing secret is committed, baked into the
# image or printed: values come from the environment (CI secrets) or are generated once
# per cluster and then reused. Output is only the kubectl "configured/unchanged" lines.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
kubectl get ns "$NS" >/dev/null 2>&1 || kubectl create ns "$NS"

if kubectl -n "$NS" get secret postgres-auth >/dev/null 2>&1; then
  PG_PASSWORD=$(kubectl -n "$NS" get secret postgres-auth -o jsonpath='{.data.password}' | base64 -d)
else
  PG_PASSWORD=${PG_PASSWORD:-$(openssl rand -hex 24)}
fi
[[ -n "${GITHUB_ACTIONS:-}" ]] && echo "::add-mask::$PG_PASSWORD"

kubectl -n "$NS" create secret generic postgres-auth \
  --from-literal=username=settle --from-literal=password="$PG_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
# App goes through toxiproxy (pg-proxy) locally so chaos can be injected; it is a
# transparent TCP proxy unless a toxic is added.
kubectl -n "$NS" create secret generic settle-secrets \
  --from-literal=DATABASE_URL="postgresql+psycopg://settle:${PG_PASSWORD}@pg-proxy:5432/settle" \
  --from-literal=REDIS_URL="redis://redis:6379/0" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null

if [[ -n "${REGISTRY_TOKEN:-}" ]]; then
  kubectl -n "$NS" create secret docker-registry ghcr-pull \
    --docker-server=ghcr.io --docker-username="${REGISTRY_USER:-x}" --docker-password="$REGISTRY_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  for sa in default settle-api settle-worker settle-migrate; do
    kubectl -n "$NS" get sa "$sa" >/dev/null 2>&1 || kubectl -n "$NS" create sa "$sa" >/dev/null
    kubectl -n "$NS" patch sa "$sa" -p '{"imagePullSecrets":[{"name":"ghcr-pull"}]}' >/dev/null
  done
fi
log "secrets present in namespace $NS (values not shown)"
