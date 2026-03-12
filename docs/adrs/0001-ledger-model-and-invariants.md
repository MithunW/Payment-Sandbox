# ADR-0001: Ledger Model and Invariants

**Status:** Accepted  
**Date:** 2026-03-10  
**Owners:** Engineering Team  
**Related:** `docs/ledger/schema-v0.md`, `docs/ledger/posting-contract.md`, `docs/architecture/service-boundaries.md`

## Context

As we began to build the Payments Sandbox, we needed a **source of financial truth** that could support
payments operations (authorise, capture, refund, chargeback) and meet fintech requirements like auditability,
idempotency and regulatory scrutiny. A simple key‑value store or single‑entry ledger would not provide the
necessary correctness guarantees. We were therefore forced to decide **how to model the ledger** — what
data structures to use, how to store money, and how to enforce invariants — before adding higher‑level
functionality such as settlement or risk.

Drivers and constraints:

- **Correctness & auditability:** We must guarantee that every money movement is balanced and traceable.
- **Idempotency:** APIs may be called repeatedly; duplicate postings must not corrupt the ledger.
- **Operational simplicity:** We need to ship a working ledger quickly, with clear invariants and low
  operational overhead.
- **Scalability & extensibility:** The model should support future extensions (e.g. multi‑currency,
  fees, FX) without rewriting history.

## Options Considered

- **Option A (Chosen): Double‑entry journal with immutable records.** Each transaction is represented
  by a `journal_entry` header and multiple `journal_line` records. Each line is either a debit or
  credit in integer minor units. `entry_id` acts as an idempotency key. Invariants (balanced entries,
  currency consistency, debit/credit shape) are enforced via database triggers. Corrections are made by
  posting new reversing entries rather than editing existing ones.
  - *Pros:* Strong correctness guarantees; familiar accounting model; supports auditability and
    idempotency; easy to derive balances; history is preserved.
  - *Cons:* More complex than single‑entry; requires careful schema design and triggers; slower to
    implement.

- **Option B: Single‑entry ledger (e.g. one amount per transaction)** where only one side of the
  transaction is recorded (positive for credit, negative for debit). Balancing is done in code.
  - *Pros:* Simpler schema; fewer joins; easier to reason about at first.
  - *Cons:* Lacks double‑entry guarantees; difficult to prove correctness; audit trail and
    reconciliation are fragile; poor industry fit for financial systems.

- **Option C: Use an off‑the‑shelf ledger service (e.g. a managed ledger API)** instead of building
  our own.  
  - *Pros:* Fastest to get started; outsources correctness and operations; potentially mature feature
    set.
  - *Cons:* Limited control over schema and invariants; cost; vendor lock‑in; may not support our
    specific posting semantics; hinders learning outcomes for this project.

- **Option D: Build the ledger inside the payments‑API database.**  
  - *Pros:* Fewer moving parts; no separate service to deploy; simpler to call.
  - *Cons:* Blurs service boundaries; payments‑API would own financial truth and state machine; makes
    migration and separation impossible later; violates our “DB‑per‑service” principle.

## Decision

We chose **Option A: a bespoke double‑entry ledger with an append‑only journal**.  Every accounting
event will create a `journal_entry` record identified by a **client‑supplied `entry_id`** (the
idempotency key) and one or more `journal_line` records. Each line posts to an `account_id` with a
direction (`DEBIT` or `CREDIT`) and an `amount_minor` in **integer minor units** (e.g. pence).  The
sum of debits and credits must be equal for each entry.  All lines in an entry share a single
`currency` defined on the entry header.  We store all monetary values as `BIGINT` to avoid floating
point rounding errors.  The schema is enforced by Postgres constraints and deferred triggers that
validate cross‑row invariants.  Updates or deletes are **rejected**; corrections are posted as
separate reversing entries.  The ledger lives in its own database (`ledger-db`) and is the sole
writer of this data; other services integrate via synchronous API calls or asynchronous events.

## Invariants (10–15 key rules)

1. **Balanced entries:** For every `entry_id`, the sum of debit amounts equals the sum of credit
   amounts.
2. **Currency consistency:** All `journal_lines.currency` values must equal the
   `journal_entry.currency` for that entry.
3. **Debit/Credit shape:** Each line must have either a debit amount or a credit amount > 0, but not
   both.
4. **Non‑negative integer amounts:** All amounts are stored as non‑negative integers representing
   minor currency units (e.g. pence or cents).  Floating‑point values and negative amounts are not
   allowed.
5. **Idempotent posting:** `entry_id` is unique.  Submitting the same `entry_id` and identical
   payload returns the same result; submitting the same `entry_id` with different payloads is
   rejected.
6. **Immutable journal:** `journal_entries` and `journal_lines` are append‑only.  UPDATE and DELETE
   operations are prohibited; corrections require new reversing entries.
7. **Minimum of two lines:** Every entry must contain at least one debit line and one credit line.
8. **Unique line numbers:** Within an entry, each `line_no` is unique and defines a deterministic
   ordering of lines.
9. **Timestamp validity:** The `occurred_at` of an entry must not be in the future (relative to the
   ledger’s clock).  Optionally, it may be subject to a reasonable max lag (e.g. no older than 30 days).
10. **Mandatory transaction reference:** Each entry must have a non‑null `transaction_id` linking the
    posting to a domain command (e.g. payment ID), enabling correlation and traceability.
11. **Valid accounts:** Every `account_id` in `journal_lines` must refer to an account defined in
    the system’s chart of accounts (if such a table is used).  Unknown accounts are rejected.
12. **Single writer:** Only the ledger service may write to the ledger database.  Other services are
    prohibited from reading or writing tables directly; integration happens via APIs/events.
13. **Monetary bounds:** Amounts must fit within a 64‑bit integer range to prevent overflow.
14. **At least one metadata field:** Entries must carry sufficient metadata (e.g. `posting_type`,
    `correlation_id`, `causation_id`) to support auditing and troubleshooting.
15. **Currency codes:** Currency codes must conform to ISO 4217; unrecognised codes are rejected.

## Consequences

- **Auditability & correctness:** The ledger is provably correct: every posting balances and is
  immutable.  Investigations and reconciliations are simplified because history cannot be silently
  altered.
- **Operational overhead:** Triggers enforce invariants at commit time, which can add latency and
  complexity, especially at high transaction volumes.  We trade some performance to gain
  correctness.
- **Learning curve:** Engineers must understand double‑entry concepts (debits/credits, minor units,
  reversing entries).  This increases onboarding time but is essential for a fintech portfolio.
- **Extensibility:** The model supports future additions (multi‑currency entries, fee postings,
  derived balance tables) without discarding core invariants.  However, adding features like
  multi‑currency will require new invariants and careful FX handling.
- **Operational isolation:** Keeping the ledger in its own service and database enforces clear
  boundaries but means additional deployment and runtime management compared to embedding the ledger
  into another service.
- **Rollback complexity:** Because entries are immutable, corrections are handled via new entries
  rather than updates.  This can make human‑readable histories longer, but ensures audit trails.

## Links

- [Ledger Schema v0](../../docs/ledger/schema-v0.md)
- [Posting Contract](../../docs/ledger/posting-contract.md)
- [Service Boundaries](../../docs/architecture/service-boundaries.md)
- [ADR Template](0000-template.md)
