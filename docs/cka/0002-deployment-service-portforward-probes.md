# K8S Mini-Lab: Pods, Deployments, Services, Endpoints, and Probes

## Objective
Build hands-on understanding of the **core Kubernetes runtime objects** by:
- creating a Deployment
- exposing it via a Service
- validating traffic using port-forward
- adding readiness and liveness probes
- observing how failures surface via kubectl

This lab focuses on **muscle memory and mental models**, not theory.

---

## Environment
- Local Kubernetes cluster: **kind**
- Cluster access: **kubectl**
- Namespace: `demo`
- Workload: `nginx` (simple, predictable HTTP server)

---

## What We Built (High-Level)

Inside a single namespace (`demo`):

```
Namespace
  └─ Deployment
       └─ ReplicaSet
            └─ Pod (nginx)
                 ↑
               Service
                 ↓
             Endpoints
```

Traffic flow:
```
Client → Service → Endpoints → Ready Pod
```

---

## Step 1: Create Namespace

```bash
kubectl create namespace demo
kubectl config set-context --current --namespace=demo
```

### Why
- Namespaces provide isolation and scoping.
- Services can only route traffic to Pods **within the same namespace**.

### Learning
> Namespace is the boundary that ties Pods, Services, and Endpoints together.

---

## Step 2: Deployment + Service (Initial Version)

### Manifest (`demo-probes.yaml`)

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

### Apply
```bash
kubectl apply -f demo-probes.yaml
```

### Observe
```bash
kubectl get pods -w
kubectl get deploy,svc
```

### Learning
- **Deployment** maintains desired state.
- **Pod** is the actual running unit.
- **Service** selects Pods by label (not by Deployment).

---

## Step 3: Validate Access via Port-Forward

```bash
kubectl port-forward svc/web 8080:80
```

Test:
```bash
curl -I http://localhost:8080
```

---

## Step 4: Add Readiness and Liveness Probes

```yaml
readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 2
  periodSeconds: 5
  timeoutSeconds: 1
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 1
  failureThreshold: 3
```

Apply:
```bash
kubectl apply -f demo-probes.yaml
```

---

## Step 5: Inspect Runtime State

```bash
kubectl describe pod -l app=web
kubectl logs -l app=web --tail=100
kubectl get endpoints web
kubectl get events --sort-by=.metadata.creationTimestamp | tail -n 30
```

---

## Core Learnings (Mental Models)

- **Pod**: runs the container; ephemeral
- **Deployment**: ensures desired pod count
- **Service**: stable access point
- **Endpoints**: real routing table (Ready pods only)
- **Namespace**: isolation boundary

---

## Common Failure Symptoms

### Pod Running but READY = 0/1
- Cause: readiness probe failing
- Effect: removed from Service endpoints

### Service Exists but No Endpoints
- Cause: readiness failure, label mismatch, or namespace mismatch

### CrashLoopBackOff
- Cause: app crash or bad config
- Check:
```bash
kubectl logs <pod> --previous
kubectl describe pod
```

### Frequent Restarts
- Cause: liveness probe too aggressive
- Fix: increase delay or timeout

---

## Debugging Order of Operations

```bash
kubectl get pods
kubectl get svc
kubectl get endpoints web
kubectl describe pod
kubectl get events
```

---

## Cleanup

```bash
kubectl delete -f demo-probes.yaml
kubectl delete namespace demo
```

---

## Final Takeaway
Kubernetes becomes predictable once you understand the chain:

Deployment → Pod → Service → Endpoints

Readiness controls traffic.  
Liveness controls restarts.
