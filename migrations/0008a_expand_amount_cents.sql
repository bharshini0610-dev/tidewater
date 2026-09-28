-- 0008a (release R1, expand) — replaces the original 0008.
-- Adds the new integer-cents columns next to the old numeric ones. Nothing is renamed,
-- retyped or dropped, so v1.7 pods (which read/write `amount`) keep working during and
-- after the rolling update, and rolling back to v1.7 needs no down-migration.
SET lock_timeout = '3s';

ALTER TABLE settlements ADD COLUMN IF NOT EXISTS amount_cents bigint;
-- Constant default on a nullable column is metadata-only in PG11+: no table rewrite.
ALTER TABLE settlements ADD COLUMN IF NOT EXISTS currency text DEFAULT 'EUR';
ALTER TABLE payouts     ADD COLUMN IF NOT EXISTS amount_cents bigint;

-- Keep both representations in sync whichever version wrote the row.
CREATE OR REPLACE FUNCTION settle_sync_amount() RETURNS trigger AS $$
BEGIN
    IF NEW.amount_cents IS NULL AND NEW.amount IS NOT NULL THEN
        NEW.amount_cents := round(NEW.amount * 100)::bigint;
    ELSIF NEW.amount IS NULL AND NEW.amount_cents IS NOT NULL THEN
        NEW.amount := NEW.amount_cents / 100.0;
    ELSIF TG_OP = 'UPDATE' AND NEW.amount IS DISTINCT FROM OLD.amount
          AND NEW.amount_cents IS NOT DISTINCT FROM OLD.amount_cents THEN
        NEW.amount_cents := round(NEW.amount * 100)::bigint;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS settlements_sync_amount ON settlements;
CREATE TRIGGER settlements_sync_amount BEFORE INSERT OR UPDATE ON settlements
    FOR EACH ROW EXECUTE FUNCTION settle_sync_amount();
DROP TRIGGER IF EXISTS payouts_sync_amount ON payouts;
CREATE TRIGGER payouts_sync_amount BEFORE INSERT OR UPDATE ON payouts
    FOR EACH ROW EXECUTE FUNCTION settle_sync_amount();
