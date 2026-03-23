# Ledger Invariants (v0)

This document records the core invariants that govern the correctness of the payments sandbox ledger.  Each invariant expresses a rule that must **always** hold for journal entries and lines.  Rationale is provided so that future changes understand why the invariant exists.

> **Note**
> These invariants apply to v0 of the ledger.  They can be extended in later versions, but they should never be silently broken.  The ledger’s correctness—its ability to reconcile money—is derived from enforcing these rules.

## Invariants and Rationales

| No. | Invariant | Rationale |
|---|---|---|
| **1** | **Balanced entry:** For every `entry_id`, the sum of debit amounts equals the sum of credit amounts. | Double‑entry bookkeeping’s fundamental law.  A balanced entry ensures that total assets equal total liabilities plus equity, preserving accounting integrity. |
| **2** | **Currency consistency:** All `journal_lines` for a given `entry_id` must use the same currency code as the `journal_entries.currency` field. | Mixing currencies within one journal entry obscures exchange rates and prevents balancing; currency conversions must be explicit separate entries. |
| **3** | **Line shape (debit XOR credit):** Each journal line must have exactly one side non‑zero: `(debit_amount > 0 XOR credit_amount > 0)`. | Prevents ambiguous postings and ensures that each line has a clear direction.  It also enables simple summation logic when checking balances. |
| **4** | **Non‑negative amounts:** `debit_amount` and `credit_amount` must be positive integers; zero or negative amounts are not permitted. | Prevents recording nonsensical or reversing flows at the line level.  Reversals should be expressed as separate entries rather than negative lines. |
| **5** | **Idempotent entry ID:** `entry_id` uniquely identifies a journal entry.  Submitting the same `entry_id` multiple times with different payloads must be rejected. | Ensures exactly‑once semantics for posting commands, avoids duplicate entries, and enables safe retries by clients. |
| **6** | **Immutability:** Once inserted, rows in `journal_entries` and `journal_lines` cannot be updated or deleted.  Corrections must be done via new journal entries. | Supports auditability and forensic traceability; immutability allows you to prove that history was not rewritten. |
| **7** | **Minimum two lines:** Each journal entry must have at least two lines (one debit, one credit). | Prevents creation of unbalanced or one‑sided entries.  A single‑line entry would violate the double‑entry paradigm. |
| **8** | **Unique line ordering:** Within an `entry_id`, each `line_no` must be unique and contiguous starting at 1. | Provides deterministic ordering for lines, which simplifies change logs, debugging, and derivation of account balances. |
| **9** | **Valid occurred_at timestamp:** `occurred_at` must not be null and cannot be in the future. | Ensures temporal integrity; postings should reflect when events actually happened, and future‑dated entries could distort analytics or settlement. |
| **10** | **Mandatory transaction_id:** Each entry must reference a `transaction_id` (e.g., payment ID) for correlation with business operations. | Enables end‑to‑end traceability from ledger entries back to business actions and supports reconciliation with external systems. |
| **11** | **Account presence:** `account_id` values should correspond to known ledger accounts (once a chart of accounts is defined). | Prevents posting to invalid accounts and reduces data entry errors.  In v0, free‑form IDs are allowed, but validation will be required later. |
| **12** | **Single writer:** Only the ledger service may write to `journal_entries` and `journal_lines`.  Other services must interact via APIs. | Preserves the integrity of invariants and allows the ledger to enforce constraints centrally. |
| **13** | **Integer minor units:** All monetary values are stored as 64‑bit signed integers representing minor units (e.g., pence). | Eliminates floating‑point rounding errors and ensures deterministic calculations across languages and databases. |
| **14** | **Metadata non‑interference:** Optional `metadata_json` must not affect core invariants (e.g., cannot change balances or idempotency semantics). | Keeps core financial logic separate from auxiliary data such as context, correlation IDs, or descriptions. |
| **15** | **ISO 4217 currency codes:** `currency` values must be valid ISO 4217 codes (e.g., GBP, USD). | Ensures standardization and prevents typos or invalid currencies from entering the ledger. |

## Extension Notes

- Future versions may introduce multi‑currency entries or fee lines; if so, invariants must extend to require explicit FX rates and additional balancing logic.
- Additional invariants may be required for interest accrual, fee recognition, or cross‑ledger posting.
