SELECT c.customer_name,
       z.zone_id,
       count(*)               AS shipments,
       sum(chg.chargeable_kg) AS chargeable_kg
FROM shipment s
CROSS JOIN LATERAL (
    SELECT (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date AS ship_day,
           left(s.dest_postcode, 2)                          AS dest_prefix,
           s.length_cm * s.width_cm * s.height_cm / 5000.0   AS volumetric_kg
) k
CROSS JOIN LATERAL (
    SELECT ceil(greatest(s.weight_kg, k.volumetric_kg)) AS chargeable_kg
) chg
JOIN dim_date d ON d.day = k.ship_day
JOIN customer c ON c.customer_id = s.customer_id
JOIN zone z     ON z.postcode_prefix = k.dest_prefix
WHERE c.segment = 'Enterprise'
  AND d.fiscal_period = '2026-Q2'
GROUP BY c.customer_name, z.zone_id
ORDER BY c.customer_name, z.zone_id;
