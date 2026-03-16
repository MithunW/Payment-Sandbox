# docs/architecture/overview.md

# Architecture Overview — Payments Sandbox (2026)

## Purpose
One-page explanation of the system: boundaries, data ownership, interactions, and the “cut line” for each phase/sprint. This is the entry point for anyone reading the project.

## Goals
- Build a finance-grade ledger foundation (double-entry, auditability, correctness invariants)
- Learn and demonstrate Kubernetes delivery (local → cloud later)
- Produce senior-level artifacts (ADRs, diagrams, runbooks, test strategy)

## Non-Goals (January cut line)
Explicitly list what is intentionally out of scope for January (e.g., full payment flows, EKS/MSK, production observability, compliance deep dives).

## System Context
### Problem statement
What problem are we solving (in sandbox terms)? What is the value of this system?

### Key constraints and assumptions
- Sandbox scope (not production)
- Timebox (Jan 2026 foundations)
- Cost tolerance (small cloud spend later)
- Primary domain focus (finance/banking/credit cards)

## Services and Responsibilities (Boundaries)
Describe each service in 5–10 lines max.
[Service Boundaries](service-boundaries.md)

## Data Ownership
- DB-per-service: rationale and ownership map
- What data is authoritative where
- How other services obtain data (query vs events vs read models — high level)

## Interaction Model (High level)
### Synchronous interactions
List the key sync calls (if any) and why they must be sync.

### Asynchronous interactions
List the key events (placeholder is fine in January) and why async is preferred.

## Domain Model (Conceptual)
Explain the core domain nouns and their relationships at a high level:
- Account
- Journal Entry
- Journal Line
- Transaction ID / idempotency keys
- State transitions (if relevant)

## Correctness and Invariants (Ledger-centric)
Summarise the invariant philosophy and point to the detailed docs:
- Where invariants are defined
- How correctness will be tested
- Failure modes mindset

## Observability (Placeholder for later)
- What will be logged (structured logs, correlation IDs)
- What metrics would exist later (latency, error rates, queue depth, posting rejects)
- Tracing stance (placeholder)

## Local Development and Deployment
- Toolchain: kind + Helm
- [Local run steps](local-postgres.md)

## Diagrams
- [Container Diagram](containers.mmd) https://lucid.app/lucidchart/b961eca6-fbee-4597-8d95-c892b04b1cc8/edit?viewport_loc=-936%2C-1010%2C3182%2C1668%2C0_0&invitationId=inv_34fc3b93-de66-4452-b90f-e1f95a652cbc
- Any other diagrams: <links>

## Related Documents

- **Service boundaries & data ownership:** [Service Boundaries](service-boundaries.md)
- **Ledger schema:** [Ledger schema v0](../ledger/schema-v0.md)
- **Ledger posting contract:** [Posting Contract](../ledger/posting-contract.md)
- **ADR:** [Ledger model and invariants (ADR-0001)](../adrs/0001-ledger-model-and-invariants.md)
- **Runbook:** [Ledger posting failures](../runbooks/ledger-posting-failures.md)
- **Local development:** [Local PostgreSQL on kind](../local-postgres.md)

## ADR Index

- **ADR ‑0001:** Ledger model & invariants (double-entry, immutability, minor units)

## Runbooks Index

- **Ledger posting failures:** [Runbook](../runbooks/ledger-posting-failures.md)
- **Local K8s troubleshooting:** _placeholder for future docs_

## What’s Next (February preview)

- Implement `payments-api` skeleton with REST endpoints for authorize/capture/refund/chargeback, idempotency, and outbox.
- Integrate risk stub service returning simple risk decisions.
- Set up Kafka/MSK integration and publish CloudEvents via the outbox.
- Extend ledger service to expose a posting API and read models.
- Begin settlement service design and event consumption patterns.


## ADR Index
List ADRs with short titles and statuses:
- ADR-0001: ...
- ADR-0002: ...

## Runbooks Index
- Ledger posting failures: <link>
- Local K8s troubleshooting: <link>

## What’s Next (February preview)
Single sprint goal + 3–5 likely backlog items.
