-- The generator adds day intervals to timestamptz values, and that arithmetic follows
-- the session time zone. Fix it so that the data is identical on every server.
SET TimeZone = 'Europe/Berlin';

CREATE TABLE customer (
    customer_id   int PRIMARY KEY,
    customer_name text NOT NULL,
    segment       text NOT NULL
);
CREATE TABLE dim_date (
    day           date PRIMARY KEY,
    fiscal_period text NOT NULL
);
CREATE TABLE zone (
    postcode_prefix text PRIMARY KEY,
    zone_id         int NOT NULL
);
CREATE TABLE rate_card (
    zone_id    int     NOT NULL,
    kg_from    numeric NOT NULL,
    kg_to      numeric NOT NULL,
    valid_from date    NOT NULL,
    base_eur   numeric NOT NULL,
    per_kg_eur numeric NOT NULL,
    PRIMARY KEY (zone_id, kg_from, valid_from)
);
CREATE TABLE shipment (
    shipment_id   bigint PRIMARY KEY,
    customer_id   int NOT NULL,
    shipped_at    timestamptz NOT NULL,
    dest_postcode text NOT NULL,
    weight_kg     numeric(6,2) NOT NULL,
    length_cm     int NOT NULL,
    width_cm      int NOT NULL,
    height_cm     int NOT NULL
);
SELECT setseed(0.42);
INSERT INTO customer
SELECT g, 'Customer ' || g,
       CASE WHEN g % 20 = 0 THEN 'Enterprise' WHEN g % 4 = 0 THEN 'Mid-market' ELSE 'SMB' END
FROM generate_series(1, 5000) g;
INSERT INTO dim_date
SELECT d::date, to_char(d, 'YYYY"-Q"Q')
FROM generate_series('2025-01-01'::date, '2026-12-31', interval '1 day') d;
INSERT INTO zone SELECT g::text, 1 + g % 8 FROM generate_series(10, 79) g;
INSERT INTO rate_card
SELECT z, b.kg_from, b.kg_to, v.valid_from,
       round((b.base * (1 + z * 0.15) * v.uplift)::numeric, 2),
       round((b.per_kg * (1 + z * 0.10) * v.uplift)::numeric, 3)
FROM generate_series(1, 8) z
CROSS JOIN (VALUES (0,2,3.90,0.00),(2,5,4.50,0.35),(5,10,5.20,0.30),
                   (10,20,6.80,0.26),(20,100000,9.50,0.22)) b(kg_from, kg_to, base, per_kg)
CROSS JOIN (VALUES ('2024-07-01'::date,1.00),('2025-01-01',1.03),('2025-07-01',1.05),
                   ('2026-01-01',1.09),('2026-04-01',1.11),('2026-07-01',1.14)) v(valid_from, uplift);
INSERT INTO shipment
SELECT g, 1 + (random() * 4999)::int,
       timestamptz '2025-01-01 00:00+01' + random() * interval '639 days',
       (10 + (random() * 69)::int)::text || lpad((random() * 999)::int::text, 3, '0'),
       round((0.1 + random() * 30)::numeric, 2),
       10 + (random() * 70)::int, 10 + (random() * 50)::int, 5 + (random() * 40)::int
FROM generate_series(1, 4000000) g;
VACUUM ANALYZE;
