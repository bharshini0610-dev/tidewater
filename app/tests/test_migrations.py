from sqlalchemy import text


def test_v17_and_v18_can_run_side_by_side_after_expand(db):
    """v1.7 writes/reads `amount`; v1.8 reads amount_cents. Both must work at once."""
    with db.begin() as c:
        c.execute(text("INSERT INTO merchants (id, name) VALUES (1, 'm')"))
        # v1.7 style write
        c.execute(
            text("INSERT INTO settlements (merchant_id, settlement_date, amount) VALUES (1, '2026-08-14', 10.50)")
        )
        # v1.8 style write
        c.execute(
            text("INSERT INTO settlements (merchant_id, settlement_date, amount_cents) VALUES (1, '2026-08-14', 250)")
        )
    with db.connect() as c:
        v17 = c.execute(text("SELECT amount FROM settlements ORDER BY id")).scalars().all()
        v18 = c.execute(text("SELECT amount_cents FROM settlements ORDER BY id")).scalars().all()
    assert [float(x) for x in v17] == [10.5, 2.5]
    assert v18 == [1050, 250]


def test_migrations_are_idempotent_and_contract_is_not_auto_applied(db):
    from conftest import MIGRATIONS

    from settle import migrate

    assert migrate.run(MIGRATIONS) == []
    with db.connect() as c:
        cols = (
            c.execute(text("SELECT column_name FROM information_schema.columns WHERE table_name='settlements'"))
            .scalars()
            .all()
        )
    assert "amount" in cols  # contract step (drop) did not run
