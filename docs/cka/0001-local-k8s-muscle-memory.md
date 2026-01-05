# Local Kubernetes Muscle Memory Notes (kind + Helm)

## What we did (summary)
We set up a **local Kubernetes cluster using kind** (Kubernetes-in-Docker) to practice the operational loop you actually need day-to-day:
- create/delete clusters quickly
- deploy workloads using **YAML manifests** and **Helm charts**
- observe the system (pods/services/endpoints)
- port-forward for local access
- debug using logs, describe, and events
- redeploy using apply/rollout restart/delete+apply

### Why kind (vs k3d)
We chose **kind** because it tends to be closer to “upstream Kubernetes” behavior and ergonomics (cluster lifecycle, networking model, and overall assumptions) than k3d, which can matter when you want your local loop to resemble common cloud K8s environments.

---

## Core cluster lifecycle (kind)

### Create a cluster
```bash
kind create cluster --name local
kubectl cluster-info
kubectl get nodes -o wide
```
- `kind create cluster`: boots a Kubernetes cluster using Docker containers as nodes.
- `kubectl cluster-info`: confirms API server connectivity.
- `kubectl get nodes`: validates nodes are Ready and shows basic node details.

### Delete a cluster (clean slate)
```bash
kind delete cluster --name local
```
- Fast reset when the cluster state becomes messy or you want repeatable reps.

---

## Namespace setup (scope your work)

### Create and use a namespace
```bash
kubectl create namespace demo
kubectl config set-context --current --namespace=demo
kubectl get ns
```
- Namespaces isolate resources and keep your practice environment tidy.
- Setting the current namespace reduces `-n demo` repetition.

---

## Deploy with YAML manifests (apply/delete/redeploy)

### Apply a manifest
```bash
kubectl apply -f demo.yaml
```
- Creates or updates resources declaratively (idempotent “desired state” apply).

### Delete what you applied
```bash
kubectl delete -f demo.yaml
```
- Removes the resources defined in the file.

### Redeploy loop
```bash
kubectl delete -f demo.yaml
kubectl apply -f demo.yaml
```
- Common “reset the app” loop while practicing.

---

## Observe workloads (pods, deployments, services)

### Get resources (quick status)
```bash
kubectl get pods -o wide
kubectl get deploy -o wide
kubectl get svc -o wide
kubectl get all
```
- `pods`: running instances (what’s actually scheduled and executing).
- `deploy`: desired replica count and rollout state.
- `svc`: stable networking endpoint for pods.
- `all`: a broad snapshot (not literally everything, but useful).

### Watch pods become ready
```bash
kubectl get pods -w
```
- Streams changes (Pending → Running → Ready, CrashLoopBackOff, etc.).

---

## Debugging fundamentals (describe, logs, events)

### Describe a pod (root-cause starter)
```bash
kubectl describe pod <pod-name>
```
- Shows scheduling, container state, probes, mounts, and *why* something failed.
- Most valuable section: **Events** at the bottom.

### Logs (inspect runtime behavior)
```bash
kubectl logs <pod-name> --tail=200
kubectl logs -f <pod-name>
```
- `--tail=200`: quick last context.
- `-f`: follow logs in real time.

### Events (cluster truth over time)
```bash
kubectl get events --sort-by=.metadata.creationTimestamp | tail -n 40
```
- The best quick signal for: image pull failures, scheduling issues, probe failures, OOMKills.

---

## Access a service locally (port-forward)

### Port-forward to a Service
```bash
kubectl port-forward svc/<service-name> 8080:80
```
- Exposes a ClusterIP service locally without Ingress/LoadBalancer.
- Format: `local_port:service_port`.

### Port-forward to a Pod (direct)
```bash
kubectl port-forward pod/<pod-name> 8080:3000
```
- Useful when debugging a single pod or bypassing Service routing.

---

## Execute inside a container (last-mile debugging)

### Exec into a pod
```bash
kubectl exec -it <pod-name> -- sh
```
- Opens a shell inside the container (if available).
- Used to test DNS, connectivity, env vars, file mounts, etc.

---

## Rollouts and redeploys (without deleting resources)

### Check rollout status
```bash
kubectl rollout status deploy/<deployment-name>
kubectl rollout history deploy/<deployment-name>
```
- Confirms deployments completed successfully and shows revision history.

### Force restart pods in a deployment
```bash
kubectl rollout restart deploy/<deployment-name>
```
- Common when config/secret changed and the pod needs recycling.

---

## Helm basics (package manager workflow)

### Add a chart repository and update
```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```
- Registers a chart source and refreshes local index.

### Install a chart into a namespace
```bash
helm install <release-name> <repo/chart> -n <namespace> --create-namespace
```
- Deploys a packaged application (templates + values) as a Helm release.

### Inspect what Helm installed
```bash
helm list -n <namespace>
helm status <release-name> -n <namespace>
```
- `list`: shows releases and their state.
- `status`: shows resources created and useful notes.

### Upgrade with overrides
```bash
helm upgrade <release-name> <repo/chart> -n <namespace> --set replicaCount=2
```
- Updates the release with new values/config (and triggers a rollout if needed).

### Uninstall a release
```bash
helm uninstall <release-name> -n <namespace>
```
- Removes the Helm-managed resources cleanly.

---

## “Operator loop” checklist (the rep sequence)
1. Cluster up:
   ```bash
   kind create cluster --name local
   ```
2. Namespace:
   ```bash
   kubectl create ns demo
   kubectl config set-context --current --namespace=demo
   ```
3. Deploy:
   ```bash
   kubectl apply -f demo.yaml
   ```
4. Observe:
   ```bash
   kubectl get pods -w
   kubectl get svc -o wide
   ```
5. Access:
   ```bash
   kubectl port-forward svc/<service> 8080:80
   ```
6. Debug:
   ```bash
   kubectl describe pod <pod>
   kubectl logs -f <pod>
   kubectl get events --sort-by=.metadata.creationTimestamp | tail -n 40
   ```
7. Redeploy:
   ```bash
   kubectl rollout restart deploy/<deployment>
   # or:
   kubectl delete -f demo.yaml && kubectl apply -f demo.yaml
   ```
8. Clean up:
   ```bash
   kind delete cluster --name local
   ```

---

## Notes / gotchas we observed
- **Secret/ConfigMap env vars**: if injected as env vars, pods usually need a restart (`kubectl rollout restart`) to pick up changes.
- **Events are gold**: when something is failing, `describe` + `get events` is often faster than guessing.
- **Port-forward is the fastest local access**: avoids setting up Ingress/LoadBalancer for simple local testing.

---

## Appendix: `demo.yaml` (sample manifest we practiced)
This is a minimal Deployment + ClusterIP Service you can apply to validate the loop (apply → observe → port-forward → logs → delete).

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  namespace: demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.27
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: demo
spec:
  selector:
    app: web
  ports:
    - name: http
      port: 80
      targetPort: 80
  type: ClusterIP
```

### Quick run with the above `demo.yaml`
```bash
kubectl create namespace demo
kubectl apply -f demo.yaml
kubectl get pods -n demo -w
kubectl port-forward -n demo svc/web 8080:80
curl -I http://localhost:8080
kubectl logs -n demo -l app=web --tail=50
kubectl delete -f demo.yaml
```
