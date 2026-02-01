KIND_CLUSTER ?= payments-sandbox
KIND_CONFIG ?= deploy/kind/cluster.yaml

VALUES_FILE ?= deploy/values/postgres-dev.yaml
HELM_RELEASE ?= postgres
NAMESPACE ?= sandbox

.PHONY: kind-up kind-down postgres-install postgres-uninstall ledger-run

kind-up:
	kind create cluster --name $(KIND_CLUSTER) --config $(KIND_CONFIG)

kind-down:
	kind delete cluster --name $(KIND_CLUSTER)

postgres-install:
	kubectl create namespace $(NAMESPACE) || true
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm repo update
	helm upgrade --install $(HELM_RELEASE) bitnami/postgresql -n $(NAMESPACE) -f $(VALUES_FILE)

postgres-uninstall:
	helm uninstall $(HELM_RELEASE) -n $(NAMESPACE)
	kubectl delete namespace $(NAMESPACE) || true

ledger-run:
	cd services/ledger && ./gradlew bootRun
