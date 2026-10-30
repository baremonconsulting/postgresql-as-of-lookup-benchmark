-- Data checks quoted in the article. Output: one "label|value" line per check.

-- Every shipment has exactly one applicable rate
SELECT 'shipments', count(*) FROM shipment;
SELECT 'shipments priced in shipment_charge', count(*) FROM shipment_charge;

-- Local shipping days covered by the data
SELECT 'first and last local shipping day',
       min((shipped_at AT TIME ZONE 'Europe/Berlin')::date) || ' .. ' ||
       max((shipped_at AT TIME ZONE 'Europe/Berlin')::date)
FROM shipment;

-- Selectivity of the key-account report
SELECT 'shipments in 2026-Q2, all customers', count(*)
FROM shipment s
JOIN dim_date d ON d.day = (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date
WHERE d.fiscal_period = '2026-Q2';
SELECT 'shipments in the key-account report', count(*)
FROM shipment s
JOIN customer c ON c.customer_id = s.customer_id
JOIN dim_date d ON d.day = (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date
WHERE c.segment = 'Enterprise' AND d.fiscal_period = '2026-Q2';

-- Shipments that would fall under a different price list if the day were taken in UTC
WITH price_list AS (
    SELECT valid_from, lead(valid_from, 1, 'infinity') OVER (ORDER BY valid_from) AS valid_to
    FROM (SELECT DISTINCT valid_from FROM rate_card) v
)
SELECT 'shipments priced from another list with a UTC day', count(*)
FROM shipment s
JOIN price_list l ON (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date >= l.valid_from
                 AND (s.shipped_at AT TIME ZONE 'Europe/Berlin')::date <  l.valid_to
WHERE NOT ((s.shipped_at AT TIME ZONE 'UTC')::date >= l.valid_from
       AND (s.shipped_at AT TIME ZONE 'UTC')::date <  l.valid_to);
