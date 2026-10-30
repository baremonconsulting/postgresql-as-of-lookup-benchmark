-- Extra structures used by the alternative methods.
-- Run after setup.sql. The original tables are not modified.

-- Method 5: explicit validity periods, with the non-overlap rule enforced.
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TABLE rate_card_period (
    zone_id      int     NOT NULL,
    kg_from      numeric NOT NULL,
    kg_to        numeric NOT NULL,
    valid_from   date    NOT NULL,
    valid_to     date    NOT NULL,   -- exclusive; 'infinity' for the current price list
    base_eur     numeric NOT NULL,
    per_kg_eur   numeric NOT NULL,
    PRIMARY KEY (zone_id, kg_from, valid_from),
    CHECK (kg_from < kg_to),
    CHECK (valid_from < valid_to),
    EXCLUDE USING gist (zone_id WITH =,
                        numrange(kg_from, kg_to, '[)') WITH &&,
                        daterange(valid_from, valid_to, '[)') WITH &&)
);

INSERT INTO rate_card_period
SELECT zone_id, kg_from, kg_to, valid_from,
       lead(valid_from, 1, 'infinity') OVER (PARTITION BY zone_id, kg_from ORDER BY valid_from),
       base_eur, per_kg_eur
FROM rate_card;

-- Method 6: shipments priced once, at load time.
-- Here the whole history is priced in one statement; an ETL job would price each new batch.
\timing on
CREATE TABLE shipment_charge AS
WITH sized AS (
    SELECT s.shipment_id, s.customer_id,
           (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date AS ship_day,
           left(s.dest_postcode, 2) AS dest_prefix,
           ceil(greatest(s.weight_kg,
                         s.length_cm * s.width_cm * s.height_cm / 5000.0)) AS chargeable_kg
    FROM shipment s
)
SELECT sz.shipment_id, sz.customer_id, sz.ship_day, sz.chargeable_kg,
       r.valid_from AS rate_valid_from,
       r.base_eur + r.per_kg_eur * sz.chargeable_kg AS freight_eur
FROM sized sz
JOIN zone z ON z.postcode_prefix = sz.dest_prefix
JOIN rate_card_period r ON r.zone_id = z.zone_id
                       AND sz.chargeable_kg >= r.kg_from
                       AND sz.chargeable_kg <  r.kg_to
                       AND sz.ship_day >= r.valid_from
                       AND sz.ship_day <  r.valid_to;
ALTER TABLE shipment_charge ADD PRIMARY KEY (shipment_id);
\timing off

-- Derived values stored once, as generated columns (used to measure expression cost).
CREATE TABLE shipment_stored (
    LIKE shipment INCLUDING ALL,
    ship_day      date    GENERATED ALWAYS AS ((shipped_at AT TIME ZONE 'Europe/Berlin')::date) STORED,
    dest_prefix   text    GENERATED ALWAYS AS (left(dest_postcode, 2)) STORED,
    chargeable_kg numeric GENERATED ALWAYS AS (ceil(greatest(weight_kg,
                              length_cm * width_cm * height_cm / 5000.0))) STORED
);
INSERT INTO shipment_stored (shipment_id, customer_id, shipped_at, dest_postcode,
                             weight_kg, length_cm, width_cm, height_cm)
SELECT shipment_id, customer_id, shipped_at, dest_postcode,
       weight_kg, length_cm, width_cm, height_cm
FROM shipment;

VACUUM ANALYZE;
