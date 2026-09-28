-- migrate:no-transaction
-- 0009b — CONCURRENTLY: builds without blocking writes; must run outside a transaction.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS payouts_idempotency_key_uq
    ON payouts (idempotency_key) WHERE idempotency_key IS NOT NULL;
