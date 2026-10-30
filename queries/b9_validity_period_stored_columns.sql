SELECT c.customer_name,
       count(*)             AS shipments,
       sum(s.chargeable_kg) AS chargeable_kg,
       sum(r.base_eur + r.per_kg_eur * s.chargeable_kg) AS freight_eur
FROM shipment_stored s
JOIN customer c         ON c.customer_id = s.customer_id
JOIN dim_date d         ON d.day = s.ship_day
JOIN zone z             ON z.postcode_prefix = s.dest_prefix
JOIN rate_card_period r ON r.zone_id = z.zone_id
                       AND s.chargeable_kg >= r.kg_from
                       AND s.chargeable_kg <  r.kg_to
                       AND s.ship_day >= r.valid_from
                       AND s.ship_day <  r.valid_to
GROUP BY c.customer_name
ORDER BY c.customer_name;
