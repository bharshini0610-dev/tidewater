#!/usr/bin/env bash
# ingress-nginx + kube-prometheus-stack (Prometheus, Alertmanager, Grafana, kube-state-metrics)
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null
log "installing ingress-nginx"
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --version 4.15.1 \
  -n ingress-nginx --create-namespace -f "$ROOT/local/ingress-nginx-values.yaml" \
  --wait --timeout 5m >/dev/null
log "installing kube-prometheus-stack"
helm upgrade --install kps prometheus-community/kube-prometheus-stack --version 91.8.0 \
  -n "$MON_NS" --create-namespace -f "$ROOT/observability/kube-prometheus-stack-values.yaml" \
  --wait --timeout 10m >/dev/null
log "platform ready"
