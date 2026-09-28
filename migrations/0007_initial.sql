-- 0007: schema in production before v1.8.0
CREATE TABLE IF NOT EXISTS merchants (
    id          bigserial PRIMARY KEY,
    name        text NOT NULL
);
CREATE TABLE IF NOT EXISTS settlements (
    id              bigserial PRIMARY KEY,
    merchant_id     bigint NOT NULL REFERENCES merchants(id),
    settlement_date date   NOT NULL,
    amount          numeric(14,2) NOT NULL,
    status          text   NOT NULL DEFAULT 'pending'
);
CREATE TABLE IF NOT EXISTS payouts (
    id              bigserial PRIMARY KEY,
    merchant_id     bigint NOT NULL,
    settlement_date date   NOT NULL,
    amount          numeric(14,2) NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now()
);
