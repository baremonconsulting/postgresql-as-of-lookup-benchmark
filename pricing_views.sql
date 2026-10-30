-- Per-shipment pricing with each query-time method, as views. Every view returns the chargeable
-- weight, the start date of the price list that was applied and the price, one row per shipment.
-- tests.sql creates them twice: against the edge-case tables and against the benchmark tables.
-- Unqualified table names bind to the first schema on the search_path that has them.

CREATE VIEW sized AS
SELECT s.shipment_id,
       s.customer_id,
       (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date AS ship_day,
       left(s.dest_postcode, 2)                          AS dest_prefix,
       ceil(greatest(s.weight_kg,
                     s.length_cm * s.width_cm * s.height_cm / 5000.0)) AS chargeable_kg
FROM shipment s;

-- Method 1: window function over all candidates
CREATE VIEW price_window AS
SELECT shipment_id, chargeable_kg, rate_valid_from, freight_eur
FROM (
    SELECT sz.shipment_id,
           sz.chargeable_kg,
           r.valid_from                                 AS rate_valid_from,
           r.base_eur + r.per_kg_eur * sz.chargeable_kg AS freight_eur,
           row_number() OVER (PARTITION BY sz.shipment_id ORDER BY r.valid_from DESC) AS rn
    FROM sized sz
    JOIN zone z      ON z.postcode_prefix = sz.dest_prefix
    JOIN rate_card r ON r.zone_id = z.zone_id
                    AND sz.chargeable_kg >= r.kg_from
                    AND sz.chargeable_kg <  r.kg_to
                    AND r.valid_from <= sz.ship_day
) c
WHERE rn = 1;

-- Method 2: DISTINCT ON
CREATE VIEW price_distinct_on AS
SELECT DISTINCT ON (sz.shipment_id)
       sz.shipment_id,
       sz.chargeable_kg,
       r.valid_from                                 AS rate_valid_from,
       r.base_eur + r.per_kg_eur * sz.chargeable_kg AS freight_eur
FROM sized sz
JOIN zone z      ON z.postcode_prefix = sz.dest_prefix
JOIN rate_card r ON r.zone_id = z.zone_id
                AND sz.chargeable_kg >= r.kg_from
                AND sz.chargeable_kg <  r.kg_to
                AND r.valid_from <= sz.ship_day
ORDER BY sz.shipment_id, r.valid_from DESC;

-- Method 4: correlated top-1 lookup
CREATE VIEW price_lateral AS
SELECT sz.shipment_id,
       sz.chargeable_kg,
       rate.valid_from                                    AS rate_valid_from,
       rate.base_eur + rate.per_kg_eur * sz.chargeable_kg AS freight_eur
FROM sized sz
JOIN zone z ON z.postcode_prefix = sz.dest_prefix
CROSS JOIN LATERAL (
    SELECT r.valid_from, r.base_eur, r.per_kg_eur
    FROM rate_card r
    WHERE r.zone_id = z.zone_id
      AND sz.chargeable_kg >= r.kg_from
      AND sz.chargeable_kg <  r.kg_to
      AND r.valid_from <= sz.ship_day
    ORDER BY r.valid_from DESC
    LIMIT 1
) rate;

-- Method 4 with LEFT JOIN LATERAL: shipments without a rate stay visible
CREATE VIEW price_lateral_left AS
SELECT sz.shipment_id,
       sz.chargeable_kg,
       rate.valid_from                                    AS rate_valid_from,
       rate.base_eur + rate.per_kg_eur * sz.chargeable_kg AS freight_eur
FROM sized sz
LEFT JOIN zone z ON z.postcode_prefix = sz.dest_prefix
LEFT JOIN LATERAL (
    SELECT r.valid_from, r.base_eur, r.per_kg_eur
    FROM rate_card r
    WHERE r.zone_id = z.zone_id
      AND sz.chargeable_kg >= r.kg_from
      AND sz.chargeable_kg <  r.kg_to
      AND r.valid_from <= sz.ship_day
    ORDER BY r.valid_from DESC
    LIMIT 1
) rate ON true;

-- Method 5: explicit validity periods
CREATE VIEW price_period AS
SELECT sz.shipment_id,
       sz.chargeable_kg,
       r.valid_from                                 AS rate_valid_from,
       r.base_eur + r.per_kg_eur * sz.chargeable_kg AS freight_eur
FROM sized sz
JOIN zone z             ON z.postcode_prefix = sz.dest_prefix
JOIN rate_card_period r ON r.zone_id = z.zone_id
                       AND sz.chargeable_kg >= r.kg_from
                       AND sz.chargeable_kg <  r.kg_to
                       AND sz.ship_day >= r.valid_from
                       AND sz.ship_day <  r.valid_to;
