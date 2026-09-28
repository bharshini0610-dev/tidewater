-- 0008: shipped in v1.8.0 — store money as integer cents
ALTER TABLE settlements RENAME COLUMN amount TO amount_cents;
ALTER TABLE settlements ALTER COLUMN amount_cents TYPE bigint USING (amount_cents * 100)::bigint;
ALTER TABLE settlements ADD COLUMN currency text NOT NULL;
ALTER TABLE payouts RENAME COLUMN amount TO amount_cents;
ALTER TABLE payouts ALTER COLUMN amount_cents TYPE bigint USING (amount_cents * 100)::bigint;
