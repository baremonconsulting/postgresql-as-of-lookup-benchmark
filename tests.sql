-- Functional tests behind the article's claims. Output: one "test|PASS" or "test|FAIL ..." line each.
-- Every comparison is per shipment and covers the chargeable weight, the start date of the price list
-- that was applied and the price. Part 1 uses a small hand-made data set in schema "edge"; part 2
-- checks the benchmark data against the prices stored in shipment_charge (priced with the period
-- join of method 5). Both schemas are dropped at the end, so the benchmark tables are left untouched.
\set ON_ERROR_STOP on
SET client_min_messages = warning;
CREATE TEMP TABLE test_result (n serial, test text, result text);

-- Rows of a view against reference rows, matched by shipment_id:
-- n = rows in the view, ref_n = rows in the reference, d = shipments that are missing on either side
-- or differ in weight, price list or price.
CREATE FUNCTION pg_temp.compare(v text, ref text, OUT n bigint, OUT ref_n bigint, OUT d bigint)
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format('SELECT count(*) FROM %I', ref) INTO ref_n;
    EXECUTE format($q$
        SELECT count(p.shipment_id),
               count(*) FILTER (WHERE (p.shipment_id, p.chargeable_kg, p.rate_valid_from, p.freight_eur)
                                      IS DISTINCT FROM
                                      (r.shipment_id, r.chargeable_kg, r.rate_valid_from, r.freight_eur))
        FROM %I p FULL JOIN %I r ON r.shipment_id = p.shipment_id $q$, v, ref) INTO n, d;
END
$$;

-- Part 1: edge cases ---------------------------------------------------------------------------
DROP SCHEMA IF EXISTS edge CASCADE;
CREATE SCHEMA edge;
SET search_path = edge, public;

CREATE TABLE zone (postcode_prefix text PRIMARY KEY, zone_id int NOT NULL);
INSERT INTO zone VALUES ('10', 1);                 -- postcode region 99 deliberately has no zone

CREATE TABLE rate_card (
    zone_id int NOT NULL, kg_from numeric NOT NULL, kg_to numeric NOT NULL, valid_from date NOT NULL,
    base_eur numeric NOT NULL, per_kg_eur numeric NOT NULL,
    PRIMARY KEY (zone_id, kg_from, valid_from));
INSERT INTO rate_card VALUES
    (1, 0, 5,      '2026-01-01', 5.00, 0.00),
    (1, 5, 100000, '2026-01-01', 6.00, 0.50),
    (1, 0, 5,      '2026-04-01', 5.50, 0.00),
    (1, 5, 100000, '2026-04-01', 6.60, 0.55);

CREATE TABLE shipment (
    shipment_id bigint PRIMARY KEY, customer_id int NOT NULL, shipped_at timestamptz NOT NULL,
    dest_postcode text NOT NULL, weight_kg numeric(6,2) NOT NULL,
    length_cm int NOT NULL, width_cm int NOT NULL, height_cm int NOT NULL);
INSERT INTO shipment VALUES
    (1, 1, '2026-03-15 12:00+01', '10000', 5.00, 10, 10, 10),  -- exactly on the 5 kg band boundary
    (2, 1, '2026-03-15 12:00+01', '10000', 4.20, 10, 10, 10),  -- rounds up to 5 kg
    (3, 1, '2026-03-15 12:00+01', '10000', 3.70, 10, 10, 10),  -- rounds up to 4 kg
    (4, 1, '2026-04-01 00:30+02', '10000', 3.70, 10, 10, 10),  -- 1 April locally, 31 March in UTC
    (5, 1, '2026-03-31 23:30+02', '10000', 3.70, 10, 10, 10),  -- 31 March locally
    (6, 1, '2026-03-15 12:00+01', '99000', 3.70, 10, 10, 10);  -- no zone, therefore no rate

CREATE TABLE expected (shipment_id bigint PRIMARY KEY, chargeable_kg numeric,
                       rate_valid_from date, freight_eur numeric);
INSERT INTO expected VALUES
    (1, 5, '2026-01-01', 6.00 + 0.50 * 5),
    (2, 5, '2026-01-01', 6.00 + 0.50 * 5),
    (3, 4, '2026-01-01', 5.00),
    (4, 4, '2026-04-01', 5.50),
    (5, 4, '2026-01-01', 5.00),
    (6, 4, NULL,         NULL);
CREATE VIEW expected_priced AS SELECT * FROM expected WHERE rate_valid_from IS NOT NULL;

CREATE TABLE rate_card_period (
    zone_id int NOT NULL, kg_from numeric NOT NULL, kg_to numeric NOT NULL,
    valid_from date NOT NULL, valid_to date NOT NULL, base_eur numeric NOT NULL, per_kg_eur numeric NOT NULL,
    PRIMARY KEY (zone_id, kg_from, valid_from),
    EXCLUDE USING gist (zone_id WITH =, numrange(kg_from, kg_to, '[)') WITH &&,
                        daterange(valid_from, valid_to, '[)') WITH &&));
INSERT INTO rate_card_period
SELECT zone_id, kg_from, kg_to, valid_from,
       lead(valid_from, 1, 'infinity') OVER (PARTITION BY zone_id, kg_from ORDER BY valid_from),
       base_eur, per_kg_eur
FROM rate_card;

\ir pricing_views.sql

-- Methods with inner joins: shipments 1-5 exactly as expected, shipment 6 absent
INSERT INTO test_result (test, result)
SELECT 'edge: band boundary, rounding, local day and missing rate (' || m || ')',
       CASE WHEN c.d = 0 AND c.n = c.ref_n THEN 'PASS' ELSE 'FAIL (' || c.d || ' differing shipments)' END
FROM (VALUES (1, 'window', 'price_window'), (2, 'DISTINCT ON', 'price_distinct_on'),
             (3, 'LATERAL', 'price_lateral'), (4, 'validity periods', 'price_period')) t(i, m, v),
     LATERAL pg_temp.compare(t.v, 'expected_priced') c
ORDER BY t.i;

-- LEFT JOIN LATERAL keeps shipment 6, with no price list and no price
INSERT INTO test_result (test, result)
SELECT 'edge: LEFT JOIN LATERAL keeps the shipment without a rate',
       CASE WHEN c.d = 0 AND c.n = c.ref_n THEN 'PASS' ELSE 'FAIL (' || c.d || ' differing shipments)' END
FROM pg_temp.compare('price_lateral_left', 'expected') c;

-- A UTC day would price shipment 4 from the old list
INSERT INTO test_result (test, result)
SELECT 'edge: a UTC day picks the previous price list for shipment 4',
       CASE WHEN (s.shipped_at AT TIME ZONE 'UTC')::date = DATE '2026-03-31'
             AND (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date = DATE '2026-04-01' THEN 'PASS' ELSE 'FAIL' END
FROM shipment s WHERE s.shipment_id = 4;

-- Changing band boundaries breaks the lead() conversion; the exclusion constraint rejects the result
DO $$
BEGIN
    INSERT INTO edge.rate_card VALUES (1, 0, 6, '2026-07-01', 5.80, 0.00), (1, 6, 100000, '2026-07-01', 7.00, 0.60);
    DELETE FROM edge.rate_card_period;
    INSERT INTO edge.rate_card_period
    SELECT zone_id, kg_from, kg_to, valid_from,
           lead(valid_from, 1, 'infinity') OVER (PARTITION BY zone_id, kg_from ORDER BY valid_from),
           base_eur, per_kg_eur
    FROM edge.rate_card;
    INSERT INTO test_result (test, result)
    VALUES ('edge: changed band boundaries are rejected by the exclusion constraint', 'FAIL (no conflict raised)');
EXCEPTION WHEN exclusion_violation THEN
    INSERT INTO test_result (test, result)
    VALUES ('edge: changed band boundaries are rejected by the exclusion constraint', 'PASS');
END
$$;

-- Part 2: the benchmark data -------------------------------------------------------------------
DROP SCHEMA IF EXISTS verify CASCADE;
CREATE SCHEMA verify;
SET search_path = verify, public;
\ir pricing_views.sql

CREATE VIEW ref_all AS
SELECT shipment_id, chargeable_kg, rate_valid_from, freight_eur FROM shipment_charge;

-- The shipments of the key-account report
CREATE VIEW ref_key_accounts AS
SELECT sc.shipment_id, sc.chargeable_kg, sc.rate_valid_from, sc.freight_eur
FROM shipment_charge sc
JOIN customer c ON c.customer_id = sc.customer_id
JOIN dim_date d ON d.day = sc.ship_day
WHERE c.segment = 'Enterprise'
  AND d.fiscal_period = '2026-Q2';

-- Method 3a, window function: report joins inside the ranking step
CREATE VIEW price_3a_window AS
SELECT shipment_id, chargeable_kg, rate_valid_from, freight_eur
FROM (
    SELECT sz.shipment_id,
           sz.chargeable_kg,
           r.valid_from                                 AS rate_valid_from,
           r.base_eur + r.per_kg_eur * sz.chargeable_kg AS freight_eur,
           row_number() OVER (PARTITION BY sz.shipment_id ORDER BY r.valid_from DESC) AS rn
    FROM sized sz
    JOIN customer c  ON c.customer_id = sz.customer_id
    JOIN dim_date d  ON d.day = sz.ship_day
    JOIN zone z      ON z.postcode_prefix = sz.dest_prefix
    JOIN rate_card r ON r.zone_id = z.zone_id
                    AND sz.chargeable_kg >= r.kg_from
                    AND sz.chargeable_kg <  r.kg_to
                    AND r.valid_from <= sz.ship_day
    WHERE c.segment = 'Enterprise'
      AND d.fiscal_period = '2026-Q2'
) x
WHERE rn = 1;

-- Method 3a, DISTINCT ON: report joins inside the ranking step
CREATE VIEW price_3a_distinct_on AS
SELECT DISTINCT ON (sz.shipment_id)
       sz.shipment_id,
       sz.chargeable_kg,
       r.valid_from                                 AS rate_valid_from,
       r.base_eur + r.per_kg_eur * sz.chargeable_kg AS freight_eur
FROM sized sz
JOIN customer c  ON c.customer_id = sz.customer_id
JOIN dim_date d  ON d.day = sz.ship_day
JOIN zone z      ON z.postcode_prefix = sz.dest_prefix
JOIN rate_card r ON r.zone_id = z.zone_id
                AND sz.chargeable_kg >= r.kg_from
                AND sz.chargeable_kg <  r.kg_to
                AND r.valid_from <= sz.ship_day
WHERE c.segment = 'Enterprise'
  AND d.fiscal_period = '2026-Q2'
ORDER BY sz.shipment_id, r.valid_from DESC;

-- Method 3b: ship_day in the PARTITION BY, quarter restated as a date range outside
CREATE VIEW price_3b AS
SELECT rt.shipment_id, rt.chargeable_kg, rt.rate_valid_from, rt.freight_eur
FROM (
    SELECT sz.shipment_id,
           sz.customer_id,
           sz.ship_day,
           sz.chargeable_kg,
           r.valid_from                                 AS rate_valid_from,
           r.base_eur + r.per_kg_eur * sz.chargeable_kg AS freight_eur,
           row_number() OVER (PARTITION BY sz.shipment_id, sz.ship_day ORDER BY r.valid_from DESC) AS rn
    FROM sized sz
    JOIN zone z      ON z.postcode_prefix = sz.dest_prefix
    JOIN rate_card r ON r.zone_id = z.zone_id
                    AND sz.chargeable_kg >= r.kg_from
                    AND sz.chargeable_kg <  r.kg_to
                    AND r.valid_from <= sz.ship_day
) rt
JOIN customer c ON c.customer_id = rt.customer_id
JOIN dim_date d ON d.day = rt.ship_day
WHERE rt.rn = 1
  AND c.segment = 'Enterprise'
  AND d.fiscal_period = '2026-Q2'
  AND rt.ship_day >= DATE '2026-04-01'
  AND rt.ship_day <  DATE '2026-07-01';

INSERT INTO test_result (test, result)
SELECT 'full data: ' || t.m || ' matches shipment_charge for ' || t.scope || ' (' || c.n || ' shipments)',
       CASE WHEN c.d = 0 AND c.n = c.ref_n THEN 'PASS'
            ELSE 'FAIL (' || c.d || ' differing shipments, ' || c.n || ' rows against ' || c.ref_n || ')' END
FROM (VALUES (1, 'window', 'price_window', 'every shipment', 'ref_all'),
             (2, 'DISTINCT ON', 'price_distinct_on', 'every shipment', 'ref_all'),
             (3, 'LATERAL', 'price_lateral', 'every shipment', 'ref_all'),
             (4, 'method 3a with a window function', 'price_3a_window', 'the key-account report', 'ref_key_accounts'),
             (5, 'method 3a with DISTINCT ON', 'price_3a_distinct_on', 'the key-account report', 'ref_key_accounts'),
             (6, 'method 3b', 'price_3b', 'the key-account report', 'ref_key_accounts')) t(i, m, v, scope, ref),
     LATERAL pg_temp.compare(t.v, t.ref) c
ORDER BY t.i;

RESET search_path;
DROP SCHEMA edge CASCADE;
DROP SCHEMA verify CASCADE;

SELECT test, result FROM test_result ORDER BY n;
