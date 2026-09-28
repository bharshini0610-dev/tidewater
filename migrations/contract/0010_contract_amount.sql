-- 0010 (release R4, contract) — NOT applied by the pipeline automatically.
-- Run only when no deployable/rollback-target version reads or writes `amount`
-- (i.e. v1.7 is out of the rollback window). See migrations/README.md.
SET lock_timeout = '3s';
DROP TRIGGER IF EXISTS settlements_sync_amount ON settlements;
DROP TRIGGER IF EXISTS payouts_sync_amount ON payouts;
DROP FUNCTION IF EXISTS settle_sync_amount();
-- Instant in PG12+: the validated CHECK proves no NULLs, so no table scan.
ALTER TABLE settlements ALTER COLUMN amount_cents SET NOT NULL;
ALTER TABLE settlements DROP CONSTRAINT IF EXISTS settlements_amount_cents_present;
ALTER TABLE settlements DROP COLUMN amount;
ALTER TABLE payouts DROP COLUMN amount;
