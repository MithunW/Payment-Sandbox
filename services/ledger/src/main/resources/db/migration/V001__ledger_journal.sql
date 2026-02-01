-- =========================
-- Ledger v0: Journal-first, append-only
-- =========================

-- Optional: static reference of accounts.
-- In January you can keep this, or omit and allow free-form account strings.
CREATE TABLE IF NOT EXISTS accounts (
                                        account_id          TEXT PRIMARY KEY,  -- e.g., "MERCHANT_RECEIVABLE:m_123"
                                        account_type        TEXT NOT NULL,      -- e.g., ASSET, LIABILITY, REVENUE, EXPENSE
                                        currency            CHAR(3),            -- optional: null means multi-currency allowed
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
    );

-- Journal entry header: immutable record representing one accounting event.
CREATE TABLE IF NOT EXISTS journal_entries (
                                               entry_id            TEXT PRIMARY KEY,             -- stable id for idempotency (e.g., le_01H...)
                                               transaction_id      TEXT NOT NULL,                -- e.g., payment_id (pay_01H...)
                                               occurred_at         TIMESTAMPTZ NOT NULL,
                                               currency            CHAR(3) NOT NULL,             -- enforce single currency per entry in v0
    posting_type        TEXT NOT NULL,                -- e.g., AUTHORIZATION, CAPTURE, REFUND
    correlation_id      TEXT NOT NULL,                -- audit traceability
    causation_id        TEXT,                         -- optional: upstream event/command id
    metadata_json       JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
    );

CREATE INDEX IF NOT EXISTS idx_journal_entries_txn ON journal_entries (transaction_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_occurred ON journal_entries (occurred_at);

-- Journal lines: immutable debits/credits for a given entry.
CREATE TABLE IF NOT EXISTS journal_lines (
                                             line_id             BIGSERIAL PRIMARY KEY,
                                             entry_id            TEXT NOT NULL REFERENCES journal_entries(entry_id),
    line_no             INT NOT NULL,                 -- stable ordering within entry
    account_id          TEXT NOT NULL,                -- optionally FK to accounts(account_id)
    debit_amount        BIGINT NOT NULL DEFAULT 0,    -- minor units
    credit_amount       BIGINT NOT NULL DEFAULT 0,    -- minor units
    currency            CHAR(3) NOT NULL,             -- must match entry currency
    description         TEXT,
    metadata_json       JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT uq_journal_lines_entry_lineno UNIQUE (entry_id, line_no),
    CONSTRAINT ck_debit_credit_non_negative CHECK (debit_amount >= 0 AND credit_amount >= 0),
    CONSTRAINT ck_debit_or_credit CHECK (
(debit_amount > 0 AND credit_amount = 0) OR
(debit_amount = 0 AND credit_amount > 0)
    )
    );

CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON journal_lines (entry_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON journal_lines (account_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_currency ON journal_lines (currency);

-- Optional hardening: prevent updates/deletes (append-only stance).
CREATE OR REPLACE FUNCTION reject_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'Ledger tables are append-only; updates/deletes are not allowed';
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tr_journal_entries_no_update ON journal_entries;
CREATE TRIGGER tr_journal_entries_no_update
    BEFORE UPDATE OR DELETE ON journal_entries
FOR EACH ROW EXECUTE FUNCTION reject_mutation();

DROP TRIGGER IF EXISTS tr_journal_lines_no_update ON journal_lines;
CREATE TRIGGER tr_journal_lines_no_update
    BEFORE UPDATE OR DELETE ON journal_lines
FOR EACH ROW EXECUTE FUNCTION reject_mutation();

-- Cross-row invariants:
-- 1) All lines currency must match entry currency
-- 2) Entry must balance: sum(debits)=sum(credits)
--
-- Implemented as DEFERRABLE constraint trigger so it runs at COMMIT
-- (allows multi-line insert within a transaction).
CREATE OR REPLACE FUNCTION validate_entry_invariants(p_entry_id TEXT) RETURNS VOID AS $$
DECLARE
entry_cur CHAR(3);
  deb BIGINT;
  cred BIGINT;
  bad_cur_count INT;
BEGIN
SELECT currency INTO entry_cur FROM journal_entries WHERE entry_id = p_entry_id;
IF entry_cur IS NULL THEN
    RAISE EXCEPTION 'Missing journal_entries row for entry_id=%', p_entry_id;
END IF;

SELECT COUNT(*) INTO bad_cur_count
FROM journal_lines
WHERE entry_id = p_entry_id AND currency <> entry_cur;

IF bad_cur_count > 0 THEN
    RAISE EXCEPTION 'Currency mismatch in journal_lines for entry_id=%', p_entry_id;
END IF;

SELECT COALESCE(SUM(debit_amount),0), COALESCE(SUM(credit_amount),0)
INTO deb, cred
FROM journal_lines
WHERE entry_id = p_entry_id;

IF deb <> cred THEN
    RAISE EXCEPTION 'Unbalanced journal entry: entry_id=% debits=% credits=%', p_entry_id, deb, cred;
END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION enforce_entry_invariants() RETURNS trigger AS $$
BEGIN
  -- Validate the entry impacted by inserted lines or entry insert.
  PERFORM validate_entry_invariants(COALESCE(NEW.entry_id, OLD.entry_id));
RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Constraint triggers (deferred)
DROP TRIGGER IF EXISTS tr_enforce_entry_invariants_lines ON journal_lines;
CREATE CONSTRAINT TRIGGER tr_enforce_entry_invariants_lines
AFTER INSERT ON journal_lines
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_entry_invariants();

DROP TRIGGER IF EXISTS tr_enforce_entry_invariants_entry ON journal_entries;
CREATE CONSTRAINT TRIGGER tr_enforce_entry_invariants_entry
AFTER INSERT ON journal_entries
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION enforce_entry_invariants();
