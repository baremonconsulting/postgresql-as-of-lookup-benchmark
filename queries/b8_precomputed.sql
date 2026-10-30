SELECT c.customer_name,
       count(*)              AS shipments,
       sum(sc.chargeable_kg) AS chargeable_kg,
       sum(sc.freight_eur)   AS freight_eur
FROM shipment_charge sc
JOIN customer c ON c.customer_id = sc.customer_id
JOIN dim_date d ON d.day = sc.ship_day
GROUP BY c.customer_name
ORDER BY c.customer_name;
