# Ledger Schema v0 (January)

## Purpose
Define the minimum schema to support **double-entry postings** and **auditability** for the Payments Sandbox. This version is intentionally small and correctness-first.

## Scope (January)
In scope:
- Append-only journal: `journal_entries` (header) + `journal_lines` (debit/credit lines)
- Amounts stored as **integer minor units** (no floating money)
- Immutability stance stated and enforced
- Constraints for: debit/credit shape, currency consistency, balanced entry

Out of scope (cut line):
- No balance tables / materialized balances / optimizations
- No fee engine / FX / multi-currency per entry (v0 uses single currency per entry)
- No backfills/migrations of historical data

---

## Conceptual Entities

### Account
A ledger address that journal lines post against (e.g., `MERCHANT_RECEIVABLE:m_123`, `CUSTOMER_FUNDING`).

Notes:
- In v0, accounts can be **free-form strings** in `journal_lines.account_id`.
- Optional `accounts` table can exist as a static reference for validation/discoverability.

### JournalEntry (header)
Represents a single accounting event (e.g., AUTHORIZATION, CAPTURE, REFUND) tied to a `transaction_id` (typically `payment_id`).

Key properties:
- Immutable fact
- Traceable via `correlation_id` / `causation_id`
- Single currency per entry (v0)

### JournalLine (debit/credit lines)
An immutable debit or credit posting to an `account_id`, belonging to a `journal_entry`.

Key properties:
- Exactly one side is non-zero (debit XOR credit)
- Amounts are integer minor units
- Currency must match entry currency
- Lines within an entry must balance (sum debits = sum credits)

---

## Data Model (Tables)

### Optional: `accounts` (static reference)
Purpose: Optional reference of known accounts and types. Not required to support balanced entries.

Columns (suggested):
- `account_id TEXT PRIMARY KEY`
- `account_type TEXT NOT NULL` (ASSET/LIABILITY/REVENUE/EXPENSE)
- `currency CHAR(3)` optional
- `created_at TIMESTAMPTZ`

### `journal_entries` (header)
Purpose: Immutable header for one posting event.

Required columns:
- `entry_id TEXT PRIMARY KEY`  
  *Caller-supplied ID recommended (supports idempotency across retries).*
- `transaction_id TEXT NOT NULL`  
  *Typically `payment_id`.*
- `occurred_at TIMESTAMPTZ NOT NULL`
- `currency CHAR(3) NOT NULL`
- `posting_type TEXT NOT NULL` (AUTHORIZATION/CAPTURE/REFUND/CHARGEBACK)
- `correlation_id TEXT NOT NULL`
- `causation_id TEXT NULL`
- `metadata_json JSONB NOT NULL DEFAULT '{}'`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`

Indexes:
- `(transaction_id)`
- `(occurred_at)`

### `journal_lines` (debit/credit lines)
Purpose: Immutable lines for a journal entry.

Required columns:
- `line_id BIGSERIAL PRIMARY KEY`
- `entry_id TEXT NOT NULL REFERENCES journal_entries(entry_id)`
- `line_no INT NOT NULL` (stable ordering within entry)
- `account_id TEXT NOT NULL` (optionally FK to `accounts.account_id`)
- `debit_amount BIGINT NOT NULL DEFAULT 0` (minor units)
- `credit_amount BIGINT NOT NULL DEFAULT 0` (minor units)
- `currency CHAR(3) NOT NULL`
- `description TEXT NULL`
- `metadata_json JSONB NOT NULL DEFAULT '{}'`
- `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`

Constraints:
- Unique `(entry_id, line_no)`
- Non-negative amounts: `debit_amount >= 0` and `credit_amount >= 0`
- XOR constraint: exactly one side is non-zero  
  `(debit_amount > 0 AND credit_amount = 0) OR (debit_amount = 0 AND credit_amount > 0)`

Indexes:
- `(entry_id)`
- `(account_id)`
- `(currency)`

---

## Money Representation
All monetary amounts are stored as **integer minor units**:
- GBP 25.99 → `2599`
- Avoid `DECIMAL` / `FLOAT` for money in the journal.

Rationale:
- Prevents floating-point rounding issues
- Makes invariants and reconciliation deterministic

---

## Immutability Stance (Auditability)
Ledger journal data is **append-only**:
- No UPDATE/DELETE on `journal_entries` or `journal_lines`
- Corrections are recorded using **new journal entries** (reversal/adjustment), never rewriting history.

Enforcement:
- DB triggers reject UPDATE/DELETE (see migration `V001__ledger_journal.sql`)

---

## Ledger Invariants (Correctness Rules)

### 1) Balanced entry
For each `entry_id`:
- `SUM(journal_lines.debit_amount) == SUM(journal_lines.credit_amount)`

### 2) Currency consistency per entry (v0)
For each `entry_id`:
- `journal_lines.currency == journal_entries.currency` for all lines

### 3) Line shape (debit XOR credit)
Each line must be either a debit line or a credit line, not both.

Implementation approach (v0):
- Line shape enforced via CHECK constraints on `journal_lines`
- Balanced entry + currency consistency enforced via **DEFERRABLE constraint trigger at COMMIT**
  (cross-row checks require triggers or application logic)

---

## Example Entry (Two lines, balanced)

Scenario: AUTHORIZATION of **£25.99** (2599 minor units) for `payment_id=pay_01H...` and `merchant_id=m_123`.

```sql
BEGIN;

INSERT INTO journal_entries (
  entry_id, transaction_id, occurred_at, currency, posting_type,
  correlation_id, causation_id, metadata_json
) VALUES (
  'le_01HZZ...', 'pay_01H...', now(), 'GBP', 'AUTHORIZATION',
  'corr_8f3c...', 'cmd_1234...', '{"merchant_id":"m_123"}'
);

INSERT INTO journal_lines (
  entry_id, line_no, account_id, debit_amount, credit_amount, currency, description
) VALUES
  ('le_01HZZ...', 1, 'MERCHANT_RECEIVABLE:m_123', 2599, 0, 'GBP', 'Authorize: merchant receivable'),
  ('le_01HZZ...', 2, 'CUSTOMER_FUNDING',          0, 2599, 'GBP', 'Authorize: customer funding');

COMMIT;
