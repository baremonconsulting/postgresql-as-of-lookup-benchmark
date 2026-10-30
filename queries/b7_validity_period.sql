WITH sized AS (
    SELECT s.shipment_id,
           s.customer_id,
           (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date AS ship_day,
           left(s.dest_postcode, 2)                          AS dest_prefix,
           ceil(greatest(s.weight_kg,
                         s.length_cm * s.width_cm * s.height_cm / 5000.0)) AS chargeable_kg
    FROM shipment s
)
SELECT c.customer_name,
       count(*)              AS shipments,
       sum(sz.chargeable_kg) AS chargeable_kg,
       sum(r.base_eur + r.per_kg_eur * sz.chargeable_kg) AS freight_eur
FROM sized sz
JOIN customer c         ON c.customer_id = sz.customer_id
JOIN dim_date d         ON d.day = sz.ship_day
JOIN zone z             ON z.postcode_prefix = sz.dest_prefix
JOIN rate_card_period r ON r.zone_id = z.zone_id
                       AND sz.chargeable_kg >= r.kg_from
                       AND sz.chargeable_kg <  r.kg_to
                       AND sz.ship_day >= r.valid_from
                       AND sz.ship_day <  r.valid_to
GROUP BY c.customer_name
ORDER BY c.customer_name;
