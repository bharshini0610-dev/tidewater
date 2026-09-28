-- 0009a (expand) — columns the worker needs to pay each merchant/date at most once.
-- Historical rows (including the 14 Aug duplicates finance is reconciling) keep NULL keys,
-- so the unique index below can be created without deleting money records.
SET lock_timeout = '3s';
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS idempotency_key text;
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS status text DEFAULT 'sent';
ALTER TABLE payouts ADD COLUMN IF NOT EXISTS bank_ref text;
