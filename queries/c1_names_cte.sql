WITH sized AS (
    SELECT s.shipment_id,
           s.customer_id,
           (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date AS ship_day,
           left(s.dest_postcode, 2)                          AS dest_prefix,
           ceil(greatest(s.weight_kg,
                         s.length_cm * s.width_cm * s.height_cm / 5000.0)) AS chargeable_kg
    FROM shipment s
),
zoned AS (
    SELECT sz.*, z.zone_id
    FROM sized sz
    JOIN zone z ON z.postcode_prefix = sz.dest_prefix
)
SELECT c.customer_name,
       zn.zone_id,
       count(*)              AS shipments,
       sum(zn.chargeable_kg) AS chargeable_kg
FROM zoned zn
JOIN customer c ON c.customer_id = zn.customer_id
JOIN dim_date d ON d.day = zn.ship_day
WHERE c.segment = 'Enterprise'
  AND d.fiscal_period = '2026-Q2'
GROUP BY c.customer_name, zn.zone_id
ORDER BY c.customer_name, zn.zone_id;
