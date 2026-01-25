# CKA-3 — Lab 3: ConfigMaps/Secrets + Troubleshooting

This note exports the completed learning for **CKA Lab 3** in a clean, study-friendly order.  
Goal: build muscle memory for **ConfigMaps**, **Secrets**, and **CrashLoopBackOff troubleshooting**.

---

## Learning objectives

By the end of this lab you should be able to:

- Create a **ConfigMap** from literals and files (and apply via `--dry-run=client -o yaml | kubectl apply -f -`).
- Create a **Secret** (dev-only) and mount it via **env** and **files**.
- Validate consumption via `kubectl logs`, `kubectl exec`, and filesystem inspection.
- Troubleshoot a deliberately broken workload (CrashLoopBackOff) using a repeatable on-call sequence.
- Patch a running Deployment to remediate a failure.

---

## Prereqs

- A working cluster (kind) and `kubectl` configured.
- Images used: `busybox:1.36` (lightweight; ideal for exam labs)

---

## 1) Lab namespace + context

Create an isolated namespace and set it as the default for your current context:

```bash
kubectl create namespace cka-lab3 || true
kubectl config set-context --current --namespace=cka-lab3
```

Quick sanity:

```bash
kubectl get ns
kubectl get pods
```

---

## 2) ConfigMap: create from env + file

### 2.1 Create a local config file

```bash
cat > app.properties <<'EOF'
APP_NAME=ledger
FEATURE_FLAG_X=true
EOF
```

### 2.2 Create the ConfigMap (CKA-friendly apply pattern)

Create a ConfigMap named `app-cm` from:
- `--from-file` (mounted as a file later)
- `--from-literal` (used as an env var later)

```bash
kubectl create configmap app-cm \
  --from-file=app.properties=./app.properties \
  --from-literal=LOG_LEVEL=debug \
  --dry-run=client -o yaml | kubectl apply -f -
```

Verify:

```bash
kubectl get configmap app-cm -o yaml
```

**Exam habit:** prefer `--dry-run=client -o yaml | apply` because it is idempotent and easily reviewed.

---

## 3) Secret: create (dev-only) and mount

### 3.1 Create a Secret (dev-only)

```bash
kubectl create secret generic app-secret \
  --from-literal=DB_PASSWORD='devpw-change-me' \
  --from-literal=API_KEY='dev-key-change-me' \
  --dry-run=client -o yaml | kubectl apply -f -
```

Verify existence:

```bash
kubectl get secret app-secret
```

**Important:** Kubernetes Secrets are **base64-encoded, not encrypted** by default.  
In real systems: enforce RBAC + enable encryption-at-rest + use an external secret store (Vault / AWS Secrets Manager via External Secrets Operator). For this lab: dev-only is fine.

---

## 4) Workload: consume ConfigMap + Secret via env + files

Create a simple Deployment that:
- prints env vars from ConfigMap + Secret
- prints the mounted ConfigMap file
- lists mounted Secret files
- then sleeps (so you can `exec` into it)

### 4.1 Apply the manifest

```bash
cat > cm-secret-demo.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cm-secret-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cm-secret-demo
  template:
    metadata:
      labels:
        app: cm-secret-demo
    spec:
      containers:
        - name: demo
          image: busybox:1.36
          command: ["/bin/sh","-c"]
          args:
            - |
              echo "=== ENV ===";
              env | egrep 'LOG_LEVEL|DB_PASSWORD|API_KEY' || true;
              echo "=== CM FILE ===";
              cat /etc/config/app.properties || true;
              echo "=== SECRET FILES ===";
              ls -l /etc/secret || true;
              echo "DB_PASSWORD file:"; cat /etc/secret/DB_PASSWORD || true;
              echo "Sleeping...";
              sleep 3600
          env:
            - name: LOG_LEVEL
              valueFrom:
                configMapKeyRef:
                  name: app-cm
                  key: LOG_LEVEL
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: app-secret
                  key: DB_PASSWORD
            - name: API_KEY
              valueFrom:
                secretKeyRef:
                  name: app-secret
                  key: API_KEY
          volumeMounts:
            - name: cm-vol
              mountPath: /etc/config
              readOnly: true
            - name: secret-vol
              mountPath: /etc/secret
              readOnly: true
      volumes:
        - name: cm-vol
          configMap:
            name: app-cm
        - name: secret-vol
          secret:
            secretName: app-secret
YAML

kubectl apply -f cm-secret-demo.yaml
kubectl rollout status deploy/cm-secret-demo
kubectl get pods -o wide
```

### 4.2 Verify via logs (fastest)

```bash
kubectl logs deploy/cm-secret-demo --tail=200
```

Expected output includes:
- `LOG_LEVEL=debug`
- `DB_PASSWORD=...` and `API_KEY=...` present in env output
- `/etc/config/app.properties` contents printed
- secret files listed under `/etc/secret`

### 4.3 Optional: verify via exec

```bash
POD=$(kubectl get pod -l app=cm-secret-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it "$POD" -- sh
```

Inside the pod:
```sh
env | egrep 'LOG_LEVEL|DB_PASSWORD|API_KEY'
cat /etc/config/app.properties
ls -l /etc/secret
exit
```

---

## 5) Troubleshooting drill: create a CrashLoopBackOff

Create a Deployment that exits immediately (intentional failure):

```bash
cat > crashloop.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: crashloop-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: crashloop-demo
  template:
    metadata:
      labels:
        app: crashloop-demo
    spec:
      containers:
        - name: boom
          image: busybox:1.36
          command: ["/bin/sh","-c"]
          args: ["echo 'I will crash now' && exit 1"]
YAML

kubectl apply -f crashloop.yaml
kubectl get pods -l app=crashloop-demo -w
```

Expected state: `CrashLoopBackOff` after a few restarts.

---

## 6) Troubleshooting checklist (CKA muscle memory)

Use this exact sequence. It is fast, reliable, and aligns with the exam.

### 6.1 Identify status + restarts
```bash
kubectl get pods -l app=crashloop-demo
```

### 6.2 Describe (source of truth for events, exit codes, reasons)
```bash
kubectl describe pod -l app=crashloop-demo | sed -n '1,160p'
```

Look for:
- `State: Terminated` / `Reason: Error`
- `Exit Code`
- `Last State` (important for crash loops)
- Events at the bottom: image pulls, config errors, back-off messages

### 6.3 Logs (current)
```bash
kubectl logs -l app=crashloop-demo --tail=50
```

### 6.4 Logs (previous) — critical for CrashLoopBackOff
```bash
kubectl logs -l app=crashloop-demo --previous --tail=50
```

### 6.5 Cluster events (recent)
```bash
kubectl get events --sort-by=.lastTimestamp | tail -n 20
```

**Interpretation rule:**  
- If `describe` shows **CreateContainerConfigError**, suspect missing ConfigMap/Secret, bad env refs, invalid volume.
- If `describe` shows **ImagePullBackOff**, it’s image name/registry/network.
- If it’s **CrashLoopBackOff** with exit code, it’s usually app command/config/runtime.

---

## 7) Fix the CrashLoopBackOff (patch a Deployment)

Patch the args to keep the container alive:

```bash
kubectl patch deploy/crashloop-demo --type='json' -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/args","value":["echo fixed && sleep 3600"]}
]'
```

Verify recovery:

```bash
kubectl rollout status deploy/crashloop-demo
kubectl get pods -l app=crashloop-demo
kubectl logs deploy/crashloop-demo --tail=50
```

---

## 8) Cleanup

```bash
kubectl delete -f cm-secret-demo.yaml -f crashloop.yaml
kubectl delete configmap app-cm
kubectl delete secret app-secret
kubectl delete namespace cka-lab3

rm -f app.properties cm-secret-demo.yaml crashloop.yaml
```

---

## Concepts: what ConfigMap and Secret actually are

### ConfigMap
A namespaced Kubernetes object storing **non-sensitive configuration**:
- key/value pairs
- or file-like blobs (mounted as files)

Usage:
- env injection: `configMapKeyRef`, `envFrom`
- file mounts: ConfigMap volume

Operational notes:
- Updating a ConfigMap does **not** update env vars in already-running Pods. Typically you roll the Deployment.
- Volume-mounted updates can propagate, but apps often still need reload logic/restart.

### Secret
A namespaced Kubernetes object storing **sensitive configuration**:
- passwords, API keys, tokens, certs

Usage:
- env injection: `secretKeyRef`, `envFrom`
- file mounts: Secret volume (best for certs/keys)

Operational notes:
- Base64 encoding is not encryption; security relies on RBAC + encryption-at-rest + process discipline.
- In production, secrets usually come from an external secret store, not handcrafted kubectl commands.

### Practical rule
- **If disclosure causes an incident → Secret.** Otherwise → ConfigMap.

---

## Quick reference: commands you should memorize for CKA

```bash
# Context/namespace
kubectl config set-context --current --namespace=<ns>

# ConfigMap & Secret creation (idempotent pattern)
kubectl create configmap <name> --from-literal=K=V --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic <name> --from-literal=K=V --dry-run=client -o yaml | kubectl apply -f -

# Debug loop
kubectl get pods
kubectl describe pod <pod>
kubectl logs <pod> --tail=50
kubectl logs <pod> --previous --tail=50
kubectl get events --sort-by=.lastTimestamp | tail -n 20
```

---

## Next: apply this to your Payments Sandbox (forward-looking)

For the ledger service:
- **ConfigMap**: log level, feature flags, hostnames, non-sensitive tuning (e.g., pool size)
- **Secret**: DB password, API keys, tokens

In Helm (K8S-3), you’ll template:
- `configmap.yaml` + `secret.yaml` (dev-only for now)
- env refs in `deployment.yaml`
- optional mounts for file-based config (e.g., application config)
