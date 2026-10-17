# Local workflow. `make up` builds the whole platform on a kind cluster.
CLUSTER              ?= gitops-demo
ENV                  ?= dev
ARGOCD_CHART_VERSION ?= 10.10.3

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

.PHONY: validate
validate: ## Render everything and run schema + policy checks (same as CI)
	./hack/validate.sh

.PHONY: test-policies
test-policies: ## Kyverno policy unit tests only
	kyverno test policies/tests --warnings-as-errors

.PHONY: up
up: cluster argocd bootstrap wait ## kind cluster + Argo CD + everything in clusters/$(ENV)

.PHONY: cluster
cluster: ## Create the kind cluster
	kind create cluster --config bootstrap/kind-config.yaml --name $(CLUSTER)

.PHONY: argocd
argocd: ## Install Argo CD (the only manual install)
	helm repo add argo https://argoproj.github.io/argo-helm --force-update
	helm upgrade --install argocd argo/argo-cd --version $(ARGOCD_CHART_VERSION) \
		--namespace argocd --create-namespace \
		--values bootstrap/argocd-values.yaml --wait --timeout 10m

.PHONY: bootstrap
bootstrap: ## Create the root Application for $(ENV)
	kubectl apply -f bootstrap/root-$(ENV).yaml

.PHONY: wait
wait: ## Wait until every Application is Synced and Healthy
	./hack/wait-for-apps.sh 1200 8

.PHONY: ui
ui: ## Argo CD UI on http://localhost:8443 (prints the admin password)
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
	kubectl -n argocd port-forward svc/argocd-server 8443:80

.PHONY: demo
demo: ## Call podinfo through the Envoy gateway
	@svc=$$(kubectl -n envoy-gateway-system get svc -l gateway.envoyproxy.io/owning-gateway-name=public -o name); \
	kubectl -n envoy-gateway-system port-forward $$svc 8080:80 >/dev/null 2>&1 & pid=$$!; sleep 3; \
	curl -s -H 'Host: podinfo.dev.local' http://127.0.0.1:8080/; kill $$pid

.PHONY: down
down: ## Delete the kind cluster
	kind delete cluster --name $(CLUSTER)
