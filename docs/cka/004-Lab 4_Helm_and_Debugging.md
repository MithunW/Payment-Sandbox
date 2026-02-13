# CKA-4 — Lab 4: Helm + debugging under time pressure

This lab is designed to build **Helm execution speed** and a **repeatable debugging loop** under time pressure (CKA-style).

---

## Objectives

By the end you can do these quickly (muscle memory):

- `helm install` a chart into a namespace
- Override values via `-f values.yaml` and `--set`
- `helm upgrade` and inspect revisions with `helm history`
- Recover fast with `helm rollback`
- Debug common failures via: **pods → describe → logs → events → svc/endpoints**

---

## Defaults used

- Namespace: `cka-lab4`
- Chart: `bitnami/nginx`
- Release name: `web`

---

## 0) Setup

```bash
kubectl create namespace cka-lab4 || true
kubectl config set-context --current --namespace=cka-lab4

helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

---

## 1) Baseline install (known-good)

```bash
helm install web bitnami/nginx
helm status web

kubectl get pods,svc -o wide
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=web --timeout=180s
```

### Smoke test (port-forward)

```bash
kubectl port-forward svc/web-nginx 8080:80
```

In another terminal:

```bash
curl -I http://localhost:8080 | head -n 5
```

**Success criteria**
- Pod(s) `Running` + `Ready`
- `curl -I` returns `HTTP/1.1 200 OK` (or similar)

---

## 2) Override values (upgrade)

Create overrides:

```bash
cat > values-lab4.yaml <<'YAML'
service:
  type: ClusterIP
  ports:
    http: 8081
containerPorts:
  http: 8080
replicaCount: 2
resources:
  requests:
    cpu: 50m
    memory: 64Mi
YAML
```

Upgrade:

```bash
helm upgrade web bitnami/nginx -f values-lab4.yaml
helm history web
kubectl get pods,svc -o wide
```

**What to check**
- `helm history web` shows new revision
- Replica count increases to 2
- Service ports reflect overrides

---

## 3) Deliberate failure #1 — ImagePullBackOff (bad image tag)

Break it:

```bash
helm upgrade web bitnami/nginx --set image.tag=does-not-exist
kubectl get pods -w
```

### Debug loop (fast, exam style)

```bash
helm status web
kubectl get pods
kubectl describe pod -l app.kubernetes.io/instance=web | sed -n '1,160p'
kubectl get events --sort-by=.lastTimestamp | tail -n 20
```

**What you should see**
- Pod status: `ImagePullBackOff` / `ErrImagePull`
- `describe` / events show failed image pull for tag `does-not-exist`

### Recovery (rollback)

```bash
helm history web
helm rollback web 2   # choose last known-good revision from history (adjust number)
kubectl rollout status deploy/web-nginx
kubectl get pods
```

**Success criteria**
- Pods return to `Running`
- `helm history web` shows rollback revision

---

## 4) Deliberate failure #2 — Service misconfig (pods run, traffic fails)

Break service port mapping so the service points to an unexpected port:

```bash
helm upgrade web bitnami/nginx --set service.ports.http=9999
kubectl get svc web-nginx -o yaml | sed -n '1,120p'
```

Port-forward will now target a service port that doesn't serve HTTP as expected:

```bash
kubectl port-forward svc/web-nginx 8080:9999
curl -I http://localhost:8080 | head -n 5
```

### Debug service wiring

```bash
kubectl describe svc web-nginx | sed -n '1,160p'
kubectl get endpoints web-nginx -o wide
kubectl get pods -o wide
```

**Interpretation**
- If pods are `Running` but `curl` fails, suspect **Service/Endpoints/port** mismatch.
- `describe svc` shows service ports.
- `endpoints` shows where traffic should route.

### Recovery (rollback)

```bash
helm history web
helm rollback web 2   # choose last known-good revision from history (adjust number)
kubectl get svc web-nginx -o wide
```

---

## 5) Timed checklist (5 minutes, exam style)

When something is broken, run **in this order**:

1) Helm view:
```bash
helm status <release>
helm history <release>
helm get values <release> --all
```

2) Pod health:
```bash
kubectl get pods
kubectl describe pod <pod> | sed -n '1,160p'
kubectl logs <pod> --tail=50
kubectl logs <pod> --previous --tail=50   # if CrashLoopBackOff
kubectl get events --sort-by=.lastTimestamp | tail -n 20
```

3) If traffic/service issue:
```bash
kubectl get svc -o wide
kubectl describe svc <svc> | sed -n '1,160p'
kubectl get endpoints <svc> -o wide
```

4) Fastest recovery path:
- If you changed values recently and need to get back to “known-good”:  
  **Rollback**:
```bash
helm rollback <release> <last-good-revision>
```

---

## 6) Cleanup

```bash
helm uninstall web
kubectl delete namespace cka-lab4
rm -f values-lab4.yaml
```

---

## Notes / takeaways

- **Helm history is your timeline.** Under pressure, it tells you *what changed* and *what you can roll back to*.
- **Describe + events** are the fastest truth source for why pods/services misbehave.
- Practice two failure archetypes:
    - `ImagePullBackOff`: bad image tag / registry issue
    - Service misconfig: pods healthy, routing broken

---

## Optional speed drills

- Re-run with a timer (goal: recover to green in < 3 minutes):
    - break image tag → rollback
    - break service port → rollback
