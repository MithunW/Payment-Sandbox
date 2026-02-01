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
