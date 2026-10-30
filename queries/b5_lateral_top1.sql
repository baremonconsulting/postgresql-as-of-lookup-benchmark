SELECT c.customer_name,
       count(*)               AS shipments,
       sum(chg.chargeable_kg) AS chargeable_kg,
       sum(price.freight_eur) AS freight_eur
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
CROSS JOIN LATERAL (
    SELECT r.base_eur, r.per_kg_eur
    FROM rate_card r
    WHERE r.zone_id = z.zone_id
      AND chg.chargeable_kg >= r.kg_from
      AND chg.chargeable_kg <  r.kg_to
      AND r.valid_from <= k.ship_day
    ORDER BY r.valid_from DESC
    LIMIT 1
) rate
CROSS JOIN LATERAL (
    SELECT rate.base_eur + rate.per_kg_eur * chg.chargeable_kg AS freight_eur
) price
GROUP BY c.customer_name
ORDER BY c.customer_name;
