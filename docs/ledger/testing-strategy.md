# Ledger Correctness Testing Strategy (v0)

This document outlines how we will prove and protect the correctness of the ledger over time.  It addresses testing at multiple levels, maps each invariant to the appropriate test type, and enumerates common failure modes with mitigation ideas.  It does *not* provide a full automated suite; rather, it defines the strategy and principles for building one.

## Testing Philosophy

The ledger is the system of financial truth for the payments sandbox.  We must be confident that each change preserves correctness and auditability.  To achieve this, tests should target both **application logic** (validating invariants before data hits the database) and **database constraints/triggers** (enforcing rules at the persistence layer).  Property‑based tests are used selectively to explore a wide range of input combinations.

Testing layers:

- **Unit tests** – Validate business logic in isolation (e.g., posting command handler checks balancing, currency consistency, idempotency).  Fast feedback; no external dependencies.
- **Integration tests** – Exercise the full stack with a real database.  Verify Flyway migrations apply, constraints and triggers fire, and that rollback occurs on invariant violations.  Ensure idempotent behaviour under concurrent calls.
- **Property tests** – Generate random sequences of journal lines to assert invariants across many cases (e.g., random debit/credit combinations that should always balance).  Use property test frameworks (e.g., jqwik for Java).

## Test Matrix Mapping Invariants to Test Types

| Invariant | Unit Test | Integration Test | Property Test | Rationale |
|---|:--:|:--:|:--:|---|
| **Balanced entry** | ✓ | ✓ | ✓ | Unit tests ensure the posting service rejects unbalanced arrays.  Integration tests verify DB triggers reject unbalanced inserts.  Property tests generate random balanced/unbalanced line sets to stress the logic. |
| **Currency consistency** | ✓ | ✓ | ✓ | Unit tests confirm a single currency parameter across all lines.  Integration tests rely on the trigger to reject mismatched currencies.  Property tests check randomly generated multi‑currency line sets. |
| **Line shape (debit XOR credit)** | ✓ | ✓ | ✓ | Unit tests assert that exactly one of debit or credit is non‑zero.  DB constraints enforce this; integration tests verify.  Property tests can generate lines with various shapes. |
| **Non‑negative amounts** | ✓ | ✓ | ✓ | Unit tests reject zero or negative amounts.  DB constraints enforce positivity.  Property tests explore a range of integers. |
| **Idempotent entry ID** | ✓ | ✓ | — | Unit tests verify that duplicate `entry_id` with identical payload returns same result; with different payload returns conflict.  Integration tests exercise concurrency and repeated calls.  Property tests not needed, as invariants revolve around deterministic behaviour. |
| **Immutability** | — | ✓ | — | Integration tests attempt UPDATE and DELETE operations and expect exceptions.  This is enforced purely at the database layer via triggers. |
| **Minimum two lines** | ✓ | ✓ | ✓ | Unit tests ensure arrays of fewer than two lines are rejected.  Integration tests verify DB rejection.  Property tests can generate 1–n lines to ensure failures for n<2. |
| **Unique line ordering** | ✓ | ✓ | ✓ | Unit tests enforce unique, contiguous `line_no`.  Integration tests rely on DB unique constraint.  Property tests generate random duplicates/missing numbers. |
| **Valid occurred_at timestamp** | ✓ | ✓ | — | Unit tests reject null or future timestamps.  Integration tests confirm DB acceptance/rejection when using `CHECK` or app logic.  Property tests unnecessary given simple domain. |
| **Mandatory transaction_id** | ✓ | ✓ | — | Unit tests ensure transaction ID presence; integration tests verify DB not‑null constraint. |
| **Account presence** | ✓ | ✓ | — | Once the chart of accounts is implemented, unit tests verify that unknown accounts are rejected; integration tests confirm FK constraint. |
| **Single writer** | — | ✓ | — | Integration tests ensure other services cannot directly insert rows (e.g., by verifying DB role permissions). |
| **Integer minor units** | ✓ | ✓ | ✓ | Unit tests confirm amounts are integer.  Integration tests confirm column type.  Property tests can generate random amounts including large values to ensure no overflow. |
| **Metadata non‑interference** | ✓ | — | — | Unit tests ensure that metadata does not influence balance calculations or idempotency. |
| **ISO 4217 currency codes** | ✓ | ✓ | — | Unit tests validate currency codes against a whitelist.  Integration tests rely on DB check or enumeration (if implemented). |

Legend:
- ✓ – Test type should be implemented
- — – Test type optional or not applicable

## Failure Modes & Mitigation Ideas

| Failure Mode | Detection | Mitigation |
|---|---|---|
| **Unbalanced or invalid entry submitted** | Application logs a clear error; integration tests fail; DB trigger raises exception. | Reject at API layer with informative message; DO NOT partially insert lines.  Client may retry after correcting payload. |
| **Duplicate entry_id with conflicting payload** | Idempotency logic detects mismatch and returns conflict; may log audit record. | Enforce idempotency rule: return 409 Conflict and require client to reconcile.  Include payload hash in idempotency store to detect collisions. |
| **Partial writes / transaction failure** | Integration tests simulate DB errors; application logs show partial insert attempts; outbox table not updated. | Use ACID transactions: group `journal_entries` and `journal_lines` inserts in one transaction; include outbox insert.  On failure, rollback everything. |
| **Database connectivity loss** | Application logs connection errors; health endpoint reports `DOWN`. | Implement connection retries with backoff; expose circuit breaker; alert via monitoring.  Use persistent outbox to retry later. |
| **Concurrent submissions causing race** | Concurrency tests simulate two threads posting same entry ID. | Use `entry_id` as primary key; DB will reject duplicate insert.  Application catches and converts to idempotency response. |
| **Negative or zero amounts** | Unit test fails; DB constraint rejects. | Validate amounts before hitting DB. |
| **Currency code typo or mismatch** | Unit test fails; DB check/triggers reject mismatches. | Keep a currency code whitelist; enforce in API layer. |
| **Malformed metadata affecting core logic** | Unit tests simulate malicious metadata. | Keep metadata as opaque JSON; never deserialize into business logic. |
| **Out‑of‑order line numbers / duplicates** | Unit test fails; DB unique constraint rejects duplicates. | Validate `line_no` sequence in code. |
| **Timestamp anomalies (future dates)** | Unit tests check; DB `CHECK` constraint if needed. | Reject such entries; require accurate `occurred_at`. |
| **Schema drift / missing migrations** | Integration tests run migrations against a clean DB and verify expected tables and triggers. | CI pipelines should run migrations automatically and fail if `flyway_schema_history` missing expected rows. |

## What to Log or Measure Later

- **Idempotency key usage:** Count of duplicate postings vs conflicts.  Helpful for debugging client retries.
- **Outbox processing metrics:** Time between journal insertion and successful event publish.  Indicates lag or failures.
- **Constraint violation counts:** Rate of rejected postings due to invariant violations.  Could highlight misuse of API.
- **Latency of posting call:** Baseline and P95/P99 for ledger posting to ensure latency meets SLOs.
- **Database health:** Connection pool saturation, transaction rollback rate, deadlock counts.

## Next Steps

- Flesh out property‑based tests using a library like jqwik; focus on invariants that involve combinatorial variation.
- Implement concurrency tests in integration layer to simulate high‑load idempotent posting.
- Integrate metrics collection (Prometheus + Grafana) to observe ledger health and failure modes in real time.
