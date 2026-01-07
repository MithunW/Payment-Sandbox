# docs/runbooks/0000-template.md

# Runbook: <Scenario/Incident Name>

**Last updated:** YYYY-MM-DD  
**Owners:** <name(s)>  
**Severity:** Low | Medium | High (guidance)  
**Related services:** <services>  
**Related docs:** <links>

## When to use this runbook
Describe symptoms and the scope (what this runbook covers and what it doesn’t).

## Symptoms
- What the user/system sees
- Example error messages (if known)
- Typical triggers (deploy, config change, traffic spike, dependency down)

## First 5 minutes (Immediate checks)
Fast checks to confirm what is broken:
- `kubectl get pods -n <ns>`
- `kubectl describe pod <pod> -n <ns>`
- `kubectl logs <pod> -n <ns> --tail=200`
- Dependency health checks (DB, network, DNS)
- Recent changes (deployments, config updates)

## Impact assessment
- Who/what is impacted (which flows)
- Approximate blast radius
- Data integrity risk (especially important for ledger)

## Likely causes (ranked)
List top causes, most probable first:
1. ...
2. ...
3. ...

## Diagnostics (Deeper checks)
- Application-level checks (logs, config, feature flags)
- Database checks (connections, locks, migrations, credentials)
- Kubernetes checks (events, probes, resource limits, DNS)
- Network checks (service endpoints, port-forward sanity)

## Mitigation / Immediate actions
Steps to reduce impact quickly (ordered by safest first):
- Restart / rollout undo
- Scale up/down
- Temporarily disable a feature (if applicable)
- Fallback mode (if applicable)

## Data integrity / Safety checks (Ledger-focused)
If ledger is involved, include:
- How to detect partial writes or duplicates
- Idempotency key checks
- Reconciliation steps (lightweight placeholders are fine)

## Recovery verification
How to confirm the system is healthy again:
- What commands to run
- What metrics/log patterns indicate recovery
- What test action to perform (e.g., post a known small transaction)

## Prevention / Follow-ups
What to improve after the incident:
- Add/adjust alerts
- Add missing logs/metrics/traces
- Add regression test
- Document a new ADR decision if needed

## Escalation
Who to contact / what to capture:
- Logs snippets
- `kubectl describe` output
- Config values used
- Timeline of actions taken
