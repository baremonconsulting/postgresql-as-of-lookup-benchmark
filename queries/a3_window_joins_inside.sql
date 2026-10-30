WITH sized AS (
    SELECT s.shipment_id,
           s.customer_id,
           (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date AS ship_day,
           left(s.dest_postcode, 2)                          AS dest_prefix,
           ceil(greatest(s.weight_kg,
                         s.length_cm * s.width_cm * s.height_cm / 5000.0)) AS chargeable_kg
    FROM shipment s
),
candidates AS (
    SELECT sz.*,
           c.customer_name,
           r.base_eur + r.per_kg_eur * sz.chargeable_kg AS freight_eur,
           row_number() OVER (PARTITION BY sz.shipment_id
                              ORDER BY r.valid_from DESC) AS rn
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
),
rated AS (
    SELECT * FROM candidates WHERE rn = 1
)
SELECT rt.customer_name,
       count(*)              AS shipments,
       sum(rt.chargeable_kg) AS chargeable_kg,
       sum(rt.freight_eur)   AS freight_eur
FROM rated rt
GROUP BY rt.customer_name
ORDER BY rt.customer_name;
