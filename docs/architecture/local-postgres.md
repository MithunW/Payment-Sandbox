# Local Postgres on kind (Helm) — K8S-2

This guide brings up a **dev-only Postgres** instance *inside* the local Kubernetes cluster using Helm.

## Scope / cut line

- ✅ Local dev only (single instance)
- ✅ Simple credential handling via local values file (gitignored)
- ❌ No HA, no backups, no prod secrets management

---

## Namespace

We deploy Postgres into the dedicated namespace:

- `sandbox`

```bash
kubectl create namespace sandbox || true
```

---

## Install (Helm)

### Add/update the Bitnami repo

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### Dev values file (gitignored)

Create a dev-only values file and keep it out of version control.

```bash
mkdir -p deploy/values

cat > deploy/values/postgres-dev.yaml <<'YAML'
auth:
  username: ledger
  password: ledgerpw-change-me
  database: ledgerdb

primary:
  persistence:
    enabled: false   # kind-friendly: avoids PVC/StorageClass issues (dev-only)
  resources:
    requests:
      cpu: 50m
      memory: 128Mi

readReplicas:
  replicaCount: 0
YAML
```

Add to `.gitignore` (if not already present):

```bash
printf "\n# Local/dev-only\n/deploy/values/postgres-dev.yaml\n" >> .gitignore
```

### Install / upgrade

Release name: `postgres` (namespace: `sandbox`)

```bash
helm upgrade --install postgres bitnami/postgresql \
  -n sandbox \
  -f deploy/values/postgres-dev.yaml
```

---

## Verify

### Wait for readiness

```bash
kubectl -n sandbox wait --for=condition=ready pod \
  -l app.kubernetes.io/instance=postgres \
  --timeout=180s
```

### Check pods and services

```bash
kubectl -n sandbox get pods,svc -o wide
```

**Note on services:** you may see a second service suffixed with `-hl`.

- `*-hl` is a **headless service** (`CLUSTER-IP: None`) for StatefulSet DNS/pod identity
- Use the **non-headless ClusterIP** service for port-forward and app connections

---

## Port-forward

### Default port (5432)

```bash
kubectl -n sandbox port-forward svc/postgres-postgresql 5432:5432
```

### Fallback port (15432)

Use this if `5432` is already in use on your laptop:

```bash
kubectl -n sandbox port-forward svc/postgres-postgresql 15432:5432
```

If the service name differs, list services and choose the **non-headless** one:

```bash
kubectl -n sandbox get svc -o wide
```

---

## Connectivity check (psql)

In a second terminal (match your values file):

### If you forwarded 5432

```bash
export PGPASSWORD="ledgerpw-change-me"
psql -h 127.0.0.1 -p 5432 -U ledger -d ledgerdb -c "select now();"
psql -h 127.0.0.1 -p 5432 -U ledger -d ledgerdb -c "select version();"
```

### If you forwarded 15432

```bash
export PGPASSWORD="ledgerpw-change-me"
psql -h 127.0.0.1 -p 15432 -U ledger -d ledgerdb -c "select now();"
psql -h 127.0.0.1 -p 15432 -U ledger -d ledgerdb -c "select version();"
```

---

## Dev-only credentials (today) vs cloud-ready pattern (later)

**Today (dev-only):**
- Credentials live in `deploy/values/postgres-dev.yaml`
- File is **gitignored**
- Good enough for local iteration

**Later (cloud-ready):**
- Replace with Kubernetes **Secrets** and/or **ExternalSecrets** (backed by AWS Secrets Manager / SSM)
- Use IRSA + External Secrets Operator for EKS (out of current scope)

---

## Uninstall / cleanup

```bash
helm uninstall postgres -n sandbox
kubectl delete namespace sandbox
```
