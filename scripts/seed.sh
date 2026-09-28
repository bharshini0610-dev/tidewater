#!/usr/bin/env bash
# Idempotent demo data: 20 merchants with settlements for the last 3 days.
# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"
kubectl -n "$NS" exec statefulset/postgres -- sh -c 'psql -q -U "$POSTGRES_USER" -d settle' <<'SQL'
INSERT INTO merchants (id, name) SELECT g, 'merchant-' || g FROM generate_series(1, 20) g ON CONFLICT DO NOTHING;
INSERT INTO settlements (merchant_id, settlement_date, amount)
SELECT m, current_date - d, round((random() * 5000)::numeric, 2)
FROM generate_series(1, 20) m, generate_series(0, 2) d
WHERE NOT EXISTS (SELECT 1 FROM settlements LIMIT 1);
SQL
log "seed data present"
