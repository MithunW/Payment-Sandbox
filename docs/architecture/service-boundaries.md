# Service Boundaries + Data Ownership (ARCH-2, v0)

## Purpose
Define responsibilities, non-responsibilities, data ownership, and integration stance so implementation proceeds without ambiguity.

## Service responsibilities / non-responsibilities

### payments-api (orchestrator + public API boundary)
**Responsibilities**
- Owns external REST API and payment lifecycle state machine: authorize → capture → refund → chargeback (simulated).
- Owns API idempotency (Idempotency-Key + request_hash + persisted response; conflict on same key different body).
- Owns correlation/trace propagation (X-Correlation-Id, traceparent) and audit trail of state transitions.
- Orchestrates synchronous calls to ledger (post accounting entries) and risk (decision) where applicable.
- Emits domain events for downstream processing (outbox now; Kafka later).

**Non-responsibilities**
- Not the system-of-record for balances or accounting truth.
- Does not store PAN; uses card_token only.
- Does not implement settlement/clearing/reconciliation.

---

### ledger (double-entry system of record)
**Responsibilities**
- Owns immutable journal entries + lines; enforces invariants: sum(debits)=sum(credits), integer minor units, immutability.
- Provides idempotent “post entry” command semantics (dedupe by entry_id / idempotency key).
- Provides balance queries (derived or cached) while preserving auditability.
- Emits ledger events (e.g., LedgerEntryPosted) for settlement/reconciliation (later).

**Non-responsibilities**
- Does not own payment state machine.
- Does not do risk decisions.
- Does not do settlement batching.

---

### risk (placeholder in January; target boundary)
**Responsibilities (target)**
- Provides fast decisioning (approve/deny/review) using rules/velocity.
- Persists decisions for audit (later).
- Emits risk decision events (later).

**Non-responsibilities**
- Does not post ledger entries.
- Does not own payment lifecycle or settlement.

---

### settlement (placeholder in January; target boundary)
**Responsibilities (target)**
- Consumes payment + ledger events to produce settlement batches and reconciliation artifacts.
- Owns settlement lifecycle and reporting.

**Non-responsibilities**
- Does not approve payments (risk) or expose public API (payments-api).
- Does not mutate ledger history outside ledger’s posting API.

## Data ownership (DB-per-service)
Principle: each service owns its database/tables. No cross-service reads/writes. Integration happens via APIs/events.

### payments-db (owned by payments-api)
Owns: payments, authorizations, captures, refunds, chargebacks, idempotency_keys, outbox.

### ledger-db (owned by ledger)
Owns: journal_entries, journal_lines, (optional) account_balances.

### risk-db (owned by risk) — not built in January
Owns: rules, decisions (later).

### settlement-db (owned by settlement) — not built in January
Owns: batches, items, reconciliation (later).

January practicality: local dev may run a single Postgres instance, but separation is enforced logically (separate DBs/schemas) and by policy (no cross-service queries).

## Integration stance (Now vs Later)
**Now (January/early Q1)**
- Sync HTTP commands on the critical path:
    - payments-api → ledger: post entry (idempotent)
    - payments-api → risk: stubbed/placeholder (optional)
- Events are recorded via outbox table, but publishing may be stubbed.

**Later (Q2/Q3 target)**
- Kafka via managed MSK Serverless; publish CloudEvents 1.0 envelopes.
- Partition key: payment_id for per-payment ordering.
- DLQ strategy via DLQ topics + metadata (failed_consumer, attempts, last_error).

## January cut line (explicitly not built yet)
- No MSK/Kafka in AWS; no operating streaming infra in January.
- No real risk engine; only stub decisions if needed.
- No settlement/clearing/reconciliation workflows.
- No full external rails; sandbox only.
- No detailed sequence diagrams or full API specification in this artifact.
