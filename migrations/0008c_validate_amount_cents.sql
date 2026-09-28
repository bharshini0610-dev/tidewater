-- 0008c (release R2, migrate) — enforce presence without a long ACCESS EXCLUSIVE lock:
-- NOT VALID is instant; VALIDATE only takes SHARE UPDATE EXCLUSIVE (reads/writes continue).
SET lock_timeout = '3s';
ALTER TABLE settlements DROP CONSTRAINT IF EXISTS settlements_amount_cents_present;
ALTER TABLE settlements ADD CONSTRAINT settlements_amount_cents_present CHECK (amount_cents IS NOT NULL) NOT VALID;
ALTER TABLE settlements VALIDATE CONSTRAINT settlements_amount_cents_present;
