# Runbook: Ledger Posting Failures

## When to use this runbook
Use this runbook when the ledger service returns errors or fails to process posting requests. Symptoms may include HTTP 4xx/5xx responses from the `/internal/v1/ledger/entries` endpoint, repeated retry failures in payments-api, or missing ledger entries despite successful upstream events.

## Symptoms
- Payments API receives HTTP 409 (idempotency conflict), 400 (validation error), or 500 responses when posting to ledger.
- No new rows appear in `journal_entries` / `journal_lines` for a given `entry_id`.
- Elevated error or warning logs in the ledger service (e.g., "Unbalanced entry", "Currency mismatch").
- Increased retry attempts or DLQ events for `LedgerEntryPosted`.
- Alerting on "ledger posting failures" SLO (if configured later).

## First checks (first 5 minutes)
1. **Is the ledger pod healthy?**  
   - `kubectl -n sandbox get pods` → Ready 1/1?  
   - Check liveness and readiness probes.
2. **Check service logs**  
   - `kubectl -n sandbox logs deploy/ledger-ledger` for errors around the time of failure.  
   - Look for stack traces, validation errors, or DB connectivity issues.
3. **Check database connectivity**  
   - `kubectl -n sandbox exec -it <ledger-pod> -- psql -U ledger -d ledger -c 'select 1'`.  
   - Ensure Postgres pod is running (`kubectl -n sandbox get pods`), and port-forward if local.
4. **Idempotency / duplicate request**  
   - Was the same `entry_id` used with different payloads? Check `journal_entries` for existing `entry_id`.
5. **Payload validation**  
   - Confirm the posting payload is balanced, uses correct ISO currency, and has non-negative integer amounts.  
   - Check that account IDs are correct and exist (if account validation is enabled).
6. **Migrations**  
   - Was the schema applied? Check `flyway_schema_history` and presence of ledger tables.

## Likely causes
- **Invalid payload:** unbalanced debits/credits, multiple currencies, negative amounts, or missing mandatory fields.  
- **Idempotency conflict:** same `entry_id` with different payload. Ledger correctly rejects with 409.  
- **Database down or unreachable:** Postgres pod crash, network issues, wrong credentials in the ledger deployment.  
- **Flyway migrations not applied:** tables missing or constraints not enforced.  
- **Ledger pod not ready:** application crash due to configuration or code bug.  
- **Invalid account_id:** account not recognised (if using accounts table).  
- **Version drift:** breaking changes between services (e.g., payments-api sends unsupported fields).

## Mitigation steps
1. **Fix payload and retry:**  
   - Correct the JSON payload (ensure balanced lines and correct currency) and resend.  
   - Use a new `entry_id` if the previous one was rejected.
2. **Restart or scale ledger service:**  
   - If the pod is unhealthy, restart it: `kubectl -n sandbox rollout restart deploy/ledger-ledger`.  
   - Scale replicas if needed.
3. **Restore database connectivity:**  
   - If Postgres is down, restart the `postgres-postgresql` deployment.  
   - Verify credentials and `LEDGER_DB_URL` environment variables in the ledger Deployment.
4. **Reapply migrations:**  
   - Ensure Flyway has run on startup; if not, manually run the migration SQL.  
   - For new environments, run `./gradlew -p services/ledger bootRun` to apply migrations.
5. **Check idempotency conflicts:**  
   - If conflict, adjust upstream to use a new `entry_id` per attempt.  
   - Investigate why duplicate requests with different payloads are being sent.
6. **Escalate to engineering:**  
   - If above mitigations fail, capture logs, payload, and environment details and notify the on-call engineer.

## Prevention notes (for later)
- Implement structured error codes from ledger API to surface specific validation failures.  
- Add metrics: count of posting failures by reason, DB connection latency, idempotency conflicts.  
- Implement alerts on high failure rate or DB connectivity issues.  
- Use a pre-publish validation in payments-api to reject invalid requests before sending to ledger.  
- Add unit and integration tests covering edge cases (multi-currency, zero/negative amounts, unknown account IDs).
- Document account naming conventions and maintain a central chart of accounts.

## Escalation notes (for later)
- Provide runbook link to on-call engineer.  
- Include contact info for DB administrators if Postgres failure.  
- Provide guidelines for when to rollback a deployment (e.g., new release causing errors).  
- Keep a post-incident review template for ledger posting incidents.

## What to log/measure later
- Total and per-reason counts of posting attempts, successes, and failures.  
- Latency of posting calls and DB transactions.  
- DB connection pool metrics (connection count, errors).  
- Size and usage of Flyway `flyway_schema_history` to track migrations.  
- DLQ events for `LedgerEntryPosted` and how they were resolved.
