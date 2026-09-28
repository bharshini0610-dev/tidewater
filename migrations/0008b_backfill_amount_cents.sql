-- migrate:no-transaction
-- 0008b (release R2, migrate) — backfill in small committed batches so no long lock is
-- held and replication/WAL stay calm. Safe to re-run.
DO $$
DECLARE n integer;
BEGIN
    LOOP
        UPDATE settlements SET amount_cents = round(amount * 100)::bigint
        WHERE id IN (SELECT id FROM settlements WHERE amount_cents IS NULL LIMIT 5000);
        GET DIAGNOSTICS n = ROW_COUNT;
        UPDATE payouts SET amount_cents = round(amount * 100)::bigint
        WHERE id IN (SELECT id FROM payouts WHERE amount_cents IS NULL LIMIT 5000);
        COMMIT;
        EXIT WHEN n = 0 AND NOT EXISTS (SELECT 1 FROM payouts WHERE amount_cents IS NULL);
    END LOOP;
END $$;
