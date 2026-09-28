# Migrations — expand / migrate / contract

## What was wrong with the original 0008 (shipped in v1.8.0)

```sql
ALTER TABLE settlements RENAME COLUMN amount TO amount_cents;           -- v1.7 SELECTs `amount` -> 500s
ALTER TABLE settlements ALTER COLUMN amount_cents TYPE bigint USING ...; -- full table rewrite under ACCESS EXCLUSIVE lock
ALTER TABLE settlements ADD COLUMN currency text NOT NULL;              -- fails on a non-empty table (no default)
```

1. **Breaks the running version.** During a rolling update v1.7 and v1.8 pods serve
   traffic at the same time. The moment the rename commits, every v1.7 query that
   names `amount` fails.
2. **Locks the hot table.** The type change rewrites the table while holding an
   ACCESS EXCLUSIVE lock; every request touching `settlements` queues behind it and
   holds a DB connection while it waits.
3. **Rollback is unsafe.** Re-deploying v1.7 after it ran needs a down-migration that
   converts cents back to numeric — on a money table, under incident pressure.

## Redesign

| Release | App version | Migration (runs *before* rollout) | Reads | Writes | Safe rollback target |
|---|---|---|---|---|---|
| R0 | v1.7 | 0007 (current prod) | `amount` | `amount` | — |
| R1 | v1.8 / 1.9.0 | **0008a expand**: add nullable `amount_cents`, `currency` with default, sync trigger | `COALESCE(amount_cents, amount*100)` | both (trigger fills the other) | v1.7 ✅ |
| R2 | v1.8.x | **0008b backfill** (batched) + **0008c** CHECK NOT VALID → VALIDATE | `amount_cents` | both | v1.7 ✅, v1.8 ✅ |
| R3 | v1.9 | 0009a/b payout idempotency (expand + CONCURRENTLY index) | `amount_cents` | `amount_cents` (trigger keeps `amount`) | v1.8 ✅ |
| R4 | v2.0 (after v1.7 leaves the rollback window) | **contract/0010**: drop trigger + `amount`, SET NOT NULL | `amount_cents` | `amount_cents` | v1.9 ✅ |

Rules the pipeline enforces (`settle/migrate.py`, `.github/workflows/deploy.yml`):

* Migrations are **forward-only** and run as a Kubernetes Job **before** the new pods roll
  out. Each migration must work with the version currently running (the previous one).
* Only files in `migrations/` are applied automatically. `migrations/contract/` needs an
  explicit, separate, manually-approved run (`--include-contract`).
* Every transactional file sets `lock_timeout` so a migration waits at most 3 s for a lock
  and fails instead of queueing the whole application behind it.
* Files starting with `-- migrate:no-transaction` contain exactly one statement
  (e.g. `CREATE INDEX CONCURRENTLY`, or a batched backfill that COMMITs).
* **Rollback = redeploy the previous image.** The schema is always compatible with the
  previous version, so there is never a down-migration.
