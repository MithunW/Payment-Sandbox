# Payments Sandbox (2026) — Fintech Backend + Kubernetes

## Purpose
This repository is a 2026 portfolio project to build senior-level backend engineering capability in a finance/credit-cards context. The focus is to design and iterate on a payments sandbox with a finance-grade ledger foundation (double-entry, correctness invariants, idempotency, auditability) while developing strong Kubernetes delivery skills (CKA track). The goal is to produce shippable increments with clear engineering artifacts (ADRs, diagrams, runbooks) that support job and freelance pitching.

## Docs structure
All design and execution artifacts live under `/docs`:

- `/docs/architecture/` — system overview, service boundaries, diagrams, design notes
- `/docs/adrs/` — Architecture Decision Records (one decision per file)
- `/docs/ledger/` — ledger schema, posting contract, invariants, demo scenarios, test strategy
- `/docs/runbooks/` — operational runbooks (failure modes, troubleshooting, mitigations)
- `/docs/cka/` — weekly Kubernetes lab notes and exam prep checklists
- `/docs/networking/` — networking log (who/why/next step)
- `/docs/retro/` — retrospectives by month
- `/docs/plans/` — sprint/month plans and goals

Navigation start here: `/docs/architecture/overview.md`

## Local Kubernetes run (placeholder)
Local Kubernetes will be standardised using **k3d or kind** + **Helm**.

Planned workflow:
1. Create local cluster (k3d/kind)
2. Install Postgres via Helm into a dedicated namespace (e.g., `sandbox`)
3. Deploy the ledger service via a Helm chart (initially a skeleton)
4. Verify via port-forward and basic health checks
5. Iterate: change code/config, rebuild image, redeploy, re-verify

A concrete, copy/paste runbook will be added later:
- `docs/architecture/local-k8s-quickstart.md` (or README section)

## Status
January 2026: establish architecture boundaries, ledger foundation docs, and a local K8s dev loop.
