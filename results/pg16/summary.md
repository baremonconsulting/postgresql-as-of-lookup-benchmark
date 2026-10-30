# Results: pg16

PostgreSQL 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1) on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0, 64-bit

Execution Time from EXPLAIN (ANALYZE, BUFFERS, TIMING OFF): one warm-up run, then five timed runs in interleaved, shuffled rounds (order.txt).

- Run started  2026-10-29 12:31:36 UTC
- Run finished 2026-10-29 13:15:55 UTC

| Query | Median (s) | Min (s) | Max (s) | Result hash |
|---|---:|---:|---:|---|
| a1_window | 35.60 | 34.07 | 37.48 | 2e045ca9 |
| a2_distinct_on | 30.66 | 30.31 | 34.00 | 2e045ca9 |
| a3_window_joins_inside | 0.53 | 0.52 | 0.56 | 2e045ca9 |
| a4_window_partition_pushdown | 7.60 | 7.46 | 7.91 | 2e045ca9 |
| a5_lateral_top1 | 0.68 | 0.63 | 0.73 | 2e045ca9 |
| a6_cte_names_lateral_top1 | 0.70 | 0.68 | 0.99 | 2e045ca9 |
| a7_validity_period | 0.45 | 0.42 | 0.51 | 2e045ca9 |
| a8_precomputed | 0.21 | 0.19 | 0.22 | 2e045ca9 |
| a9_distinct_on_joins_inside | 0.57 | 0.52 | 0.62 | 2e045ca9 |
| b1_window | 39.56 | 37.97 | 41.38 | 50241c24 |
| b2_distinct_on | 32.34 | 31.49 | 34.07 | 50241c24 |
| b5_lateral_top1 | 49.93 | 47.80 | 50.98 | 50241c24 |
| b7_validity_period | 24.66 | 23.84 | 25.25 | 50241c24 |
| b8_precomputed | 1.48 | 1.31 | 1.56 | 50241c24 |
| b9_validity_period_stored_columns | 29.45 | 27.43 | 30.57 | 50241c24 |
| c1_names_cte | 0.27 | 0.24 | 0.32 | 90d5d516 |
| c2_names_lateral | 0.26 | 0.25 | 0.29 | 90d5d516 |

## Sensitivity checks

| Query | Median (s) | Min (s) | Max (s) | Result hash |
|---|---:|---:|---:|---|
| a1_window__work_mem_1GB | 36.56 | 35.37 | 41.39 | 2e045ca9 |
| a3_window_joins_inside__jit_off | 0.54 | 0.50 | 0.59 | 2e045ca9 |
| a5_lateral_top1__jit_off | 0.67 | 0.62 | 0.76 | 2e045ca9 |
| a6_cte_names_lateral_top1__jit_off | 0.66 | 0.55 | 0.79 | 2e045ca9 |
| a7_validity_period__jit_off | 0.42 | 0.42 | 0.46 | 2e045ca9 |
| a8_precomputed__jit_off | 0.23 | 0.18 | 0.24 | 2e045ca9 |
| a9_distinct_on_joins_inside__jit_off | 0.54 | 0.53 | 0.59 | 2e045ca9 |
| b7_validity_period__memoize_off | 24.63 | 22.75 | 25.79 | 50241c24 |
| b7_validity_period__memoize_off_jit_full | 24.69 | 22.92 | 26.54 | 50241c24 |
| b7_validity_period__memoize_off_jit_off | 25.15 | 24.26 | 25.61 | 50241c24 |
| b9_validity_period_stored_columns__memoize_off | 13.38 | 12.95 | 13.70 | 50241c24 |
| b9_validity_period_stored_columns__memoize_off_jit_full | 13.63 | 12.77 | 13.78 | 50241c24 |
| b9_validity_period_stored_columns__memoize_off_jit_off | 13.73 | 13.14 | 14.61 | 50241c24 |

## Initial population of shipment_charge (setup_methods.sql)

CREATE TABLE ... AS: Time: 33449.623 ms (00:33.450)

Primary key: Time: 2857.022 ms (00:02.857)

## Functional tests (tests.txt)

- edge: band boundary, rounding, local day and missing rate (window)|PASS
- edge: band boundary, rounding, local day and missing rate (DISTINCT ON)|PASS
- edge: band boundary, rounding, local day and missing rate (LATERAL)|PASS
- edge: band boundary, rounding, local day and missing rate (validity periods)|PASS
- edge: LEFT JOIN LATERAL keeps the shipment without a rate|PASS
- edge: a UTC day picks the previous price list for shipment 4|PASS
- edge: changed band boundaries are rejected by the exclusion constraint|PASS
- full data: window matches shipment_charge for every shipment (4000000 shipments)|PASS
- full data: DISTINCT ON matches shipment_charge for every shipment (4000000 shipments)|PASS
- full data: LATERAL matches shipment_charge for every shipment (4000000 shipments)|PASS
- full data: method 3a with a window function matches shipment_charge for the key-account report (28206 shipments)|PASS
- full data: method 3a with DISTINCT ON matches shipment_charge for the key-account report (28206 shipments)|PASS
- full data: method 3b matches shipment_charge for the key-account report (28206 shipments)|PASS
