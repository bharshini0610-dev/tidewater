# settle — local workflow. Requires: docker, k3d, kubectl, helm, kustomize, python3.
SHELL := /bin/bash
CLUSTER ?= settle
RELEASE ?= 1.9.0
IMAGE_REPO ?= settle-api

.PHONY: help up down build deploy verify rollback release seed chaos-db chaos-db-off alert-demo \
        grafana prometheus test lint tf-check

help:  ## list targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-14s %s\n", $$1, $$2}'

up:  ## create k3d cluster + ingress-nginx + Prometheus/Grafana + settle 1.9.0
	k3d cluster list $(CLUSTER) >/dev/null 2>&1 || k3d cluster create --config local/k3d-cluster.yaml
	scripts/install-platform.sh
	kubectl apply -k observability/ 2>/dev/null || (sleep 10 && kubectl apply -k observability/)
	$(MAKE) release RELEASE=1.9.0

down:  ## delete the cluster
	k3d cluster delete $(CLUSTER)

build:  ## build RELEASE (1.9.0 | 1.9.1-rc) locally and import it into k3d
	rm -rf /tmp/settle-build && git worktree add -f /tmp/settle-build HEAD >/dev/null
	if [ "$(RELEASE)" = "1.9.1-rc" ]; then (cd /tmp/settle-build && git apply images/settle-api-1.9.1-rc/regression.patch); fi
	docker build -f /tmp/settle-build/app/Dockerfile --build-arg APP_VERSION=$(RELEASE) -t $(IMAGE_REPO):$(RELEASE) /tmp/settle-build
	git worktree remove --force /tmp/settle-build
	k3d image import -c $(CLUSTER) $(IMAGE_REPO):$(RELEASE)

release: build  ## build + deploy + verify RELEASE; roll back automatically on failure
	@digest=$$(docker image inspect $(IMAGE_REPO):$(RELEASE) --format '{{.Id}}'); \
	img="docker.io/library/$(IMAGE_REPO):$(RELEASE)"; \
	scripts/deploy-local.sh "$$img" "$(RELEASE)" "$$digest"

seed:  ## insert demo merchants/settlements
	scripts/seed.sh

verify:  ## run post-deploy verification against RELEASE
	scripts/verify.sh $(RELEASE)

rollback:  ## manual rollback to the previous ReplicaSet
	scripts/rollback.sh

chaos-db:  ## inject 3 s latency on every Postgres round-trip
	scripts/chaos-db.sh on 3000

chaos-db-off:  ## remove the latency
	scripts/chaos-db.sh off

alert-demo:  ## chaos-db + traffic until SettleApiErrorBudgetBurn fires, then recover
	scripts/alert-demo.sh

grafana:  ## port-forward Grafana on :3000 and print the generated admin password
	@echo "user: admin  password: $$(kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d)"
	kubectl -n monitoring port-forward svc/kps-grafana 3000:80

prometheus:  ## port-forward Prometheus on :9090
	kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090

test:  ## unit tests (needs a local Postgres + the env in app/tests/conftest.py)
	cd app && python -m pytest -q

lint:  ## ruff + kubeconform + hadolint
	cd app && ruff check . && ruff format --check .
	kustomize build deploy/k8s/overlays/local | kubeconform -strict -summary -ignore-missing-schemas
	docker run --rm -i hadolint/hadolint:v2.15.1 < app/Dockerfile

tf-check:  ## terraform fmt/validate + tflint + checkov
	infra/terraform/check.sh
