# Results: pg18

PostgreSQL 18.6 on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0, 64-bit

Execution Time from EXPLAIN (ANALYZE, BUFFERS, TIMING OFF): one warm-up run, then five timed runs in interleaved, shuffled rounds (order.txt).

- Run started  2026-10-29 15:08:09 UTC
- Run finished 2026-10-29 16:04:58 UTC

| Query | Median (s) | Min (s) | Max (s) | Result hash |
|---|---:|---:|---:|---|
| a1_window | 42.13 | 40.05 | 43.42 | 2e045ca9 |
| a2_distinct_on | 37.66 | 36.87 | 39.12 | 2e045ca9 |
| a3_window_joins_inside | 0.73 | 0.62 | 0.84 | 2e045ca9 |
| a4_window_partition_pushdown | 9.38 | 9.10 | 10.04 | 2e045ca9 |
| a5_lateral_top1 | 0.78 | 0.75 | 0.84 | 2e045ca9 |
| a6_cte_names_lateral_top1 | 0.84 | 0.82 | 0.96 | 2e045ca9 |
| a7_validity_period | 0.54 | 0.51 | 0.65 | 2e045ca9 |
| a8_precomputed | 0.25 | 0.23 | 0.32 | 2e045ca9 |
| a9_distinct_on_joins_inside | 0.65 | 0.59 | 0.70 | 2e045ca9 |
| b1_window | 46.64 | 45.39 | 51.30 | 50241c24 |
| b2_distinct_on | 39.62 | 38.49 | 40.33 | 50241c24 |
| b5_lateral_top1 | 63.82 | 62.29 | 67.37 | 50241c24 |
| b7_validity_period | 34.09 | 31.83 | 34.85 | 50241c24 |
| b8_precomputed | 1.31 | 1.27 | 1.44 | 50241c24 |
| b9_validity_period_stored_columns | 33.94 | 33.41 | 35.93 | 50241c24 |
| c1_names_cte | 0.33 | 0.28 | 0.39 | 90d5d516 |
| c2_names_lateral | 0.30 | 0.29 | 0.34 | 90d5d516 |

## Sensitivity checks

| Query | Median (s) | Min (s) | Max (s) | Result hash |
|---|---:|---:|---:|---|
| a1_window__work_mem_1GB | 44.59 | 43.56 | 46.34 | 2e045ca9 |
| a3_window_joins_inside__jit_off | 0.68 | 0.60 | 0.87 | 2e045ca9 |
| a5_lateral_top1__jit_off | 0.75 | 0.72 | 0.76 | 2e045ca9 |
| a6_cte_names_lateral_top1__jit_off | 0.83 | 0.75 | 1.07 | 2e045ca9 |
| a7_validity_period__jit_off | 0.54 | 0.51 | 0.64 | 2e045ca9 |
| a8_precomputed__jit_off | 0.27 | 0.25 | 0.29 | 2e045ca9 |
| a9_distinct_on_joins_inside__jit_off | 0.66 | 0.61 | 0.72 | 2e045ca9 |
| b7_validity_period__memoize_off | 33.47 | 32.01 | 34.87 | 50241c24 |
| b7_validity_period__memoize_off_jit_full | 34.44 | 31.82 | 37.07 | 50241c24 |
| b7_validity_period__memoize_off_jit_off | 33.16 | 32.84 | 37.13 | 50241c24 |
| b9_validity_period_stored_columns__memoize_off | 17.52 | 16.36 | 20.28 | 50241c24 |
| b9_validity_period_stored_columns__memoize_off_jit_full | 17.45 | 16.66 | 19.25 | 50241c24 |
| b9_validity_period_stored_columns__memoize_off_jit_off | 17.70 | 17.48 | 18.82 | 50241c24 |

## Initial population of shipment_charge (setup_methods.sql)

CREATE TABLE ... AS: Time: 43863.794 ms (00:43.864)

Primary key: Time: 3030.386 ms (00:03.030)

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
