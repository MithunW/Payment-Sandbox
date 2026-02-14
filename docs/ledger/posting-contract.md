# Ledger Posting Contract

## Purpose

This document defines the minimal payload used to post a **journal entry** to the ledger service.  The goal is to support a double‑entry accounting model where each request consists of a header plus a list of debit/credit lines.  Even though the ledger implementation may evolve, the contract should remain stable so callers can rely on idempotency and clear validation rules.

## Request Schema

The request body is a JSON object with the following fields:

- `transaction_id` (string, required): A unique identifier for the business transaction (e.g., payment ID).  Used for correlation and search; not an idempotency key.
- `entry_id` (string, required): An idempotency key for this journal entry.  **Must be stable across retries.**  Submitting the same `entry_id` and identical payload again should return the same result; submitting the same `entry_id` with different content must be rejected.
- `occurred_at` (ISO 8060 timestamp, required): When the accounting event happened.  The ledger uses this for ordering and reporting.  Cannot be in the future.
- `currency` (string, required): The three‑letter ISO 4217 code (e.g., `GBP`, `USD`).  All lines in the entry must use the same currency.  Multi‑currency entries are not supported in v0.
- `lines` (array of objects, required): Each element describes a debit or credit posting.  Fields:
  - `account_id` (string, required): The account to post against (e.g., `MERCHANT_RECEIVABLE:m_123`).
  - `direction` (string, required): Either `DEBIT` or `CREDIT`.  Each line must specify exactly one side.
  - `amount_minor` (integer, required): Amount in minor units (e.g., pence).  Must be **greater than zero**.
  - `narrative` (string, optional): Human‑readable description for the line.  Not used for invariants.
- `metadata` (object, optional): A JSON object for additional contextual information.  The ledger stores metadata as JSONB.  Recommended keys:
  - `posting_type` (e.g., `AUTHORIZATION`, `CAPTURE`, `REFUND`)
  - `correlation_id` and `causation_id` for audit/tracing
  - any other relevant domain properties

### Example Request

```
{
  "transaction_id": "pay_01HZ6ABCD",
  "entry_id": "le_01HZ6XYZ",
  "occurred_at": "2026-02-01T12:00:05Z",
  "currency": "GBP",
  "lines": [
    {
      "account_id": "MERCHANT_RECEIVABLE:m_123",
      "direction": "DEBIT",
      "amount_minor": 2599,
      "narrative": "Authorize: merchant receivable"
    },
    {
      "account_id": "CUSTOMER_FUNDING",
      "direction": "CREDIT",
      "amount_minor": 2599,
      "narrative": "Authorize: customer funding"
    }
  ],
  "metadata": {
    "posting_type": "AUTHORIZATION",
    "correlation_id": "corr_abcd1234",
    "causation_id": "cmd_9876"
  }
}
```

## Response Shape

The ledger service responds synchronously.  A successful post returns HTTP `201 Created` with the `entry_id` echoed back.  A rejected post returns an HTTP `4xx` status with an error code and human‑readable message.

### Success

```
{
  "entry_id": "le_01HZ6XYZ",
  "result": "ACCEPTED",
  "timestamp": "2026-02-01T12:00:05Z"
}
```

### Failure (example)

```
{
  "result": "REJECTED",
  "reason": "UNBALANCED_ENTRY",
  "message": "Sum of debits (2599) does not equal sum of credits (2600)"
}
```

The service may also return `reason` values like `INVALID_CURRENCY`, `NEGATIVE_AMOUNT`, or `IDEMPOTENCY_CONFLICT`.  In an idempotency conflict (same `entry_id` with different payload), an HTTP 409 Conflict is returned.

## Validation Rules

The ledger enforces several invariants on incoming journal entries:

1. **Balanced amounts**: The sum of `amount_minor` for `DEBIT` lines must equal the sum for `CREDIT` lines.  Entries where the amounts don’t balance are rejected (reason `UNBALANCED_ENTRY`).
2. **Currency consistency**: The `currency` at the entry level must be a valid ISO 4217 code.  All lines must implicitly use this currency; multi‑currency entries are not supported in v0.
3. **Non‑negative, non‑zero amounts**: Each line’s `amount_minor` must be an integer greater than zero.  Zero or negative amounts are not allowed (reason `NEGATIVE_AMOUNT`).
4. **Direction mandatory**: Each line must specify `direction` as either `DEBIT` or `CREDIT`.  Lines missing a direction or specifying both sides are invalid.
5. **Idempotency**: The `entry_id` acts as an idempotency key.  The first submission of a given `entry_id` is processed; subsequent submissions with the same `entry_id` and identical payload return the same success response.  Submissions with the same `entry_id` but different content are rejected (reason `IDEMPOTENCY_CONFLICT`).
6. **Optional: Account existence**: In some environments, the ledger may verify that `account_id` exists in the `accounts` reference table and reject unknown accounts (reason `UNKNOWN_ACCOUNT`).  In v0 this check can be deferred if account validation happens upstream.

These rules ensure the ledger’s double‑entry invariants and provide a clear, stable contract for callers.  Future versions may extend the request (e.g., multi‑currency entries) but must preserve backward compatibility and idempotency semantics.
