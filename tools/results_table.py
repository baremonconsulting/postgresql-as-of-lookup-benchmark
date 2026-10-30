"""Print the results table of a benchmark run as Markdown: median report execution time per method.

Usage: python3 tools/results_table.py <results-dir>
Example: python3 tools/results_table.py results/pg18
"""
import re
import statistics
import sys
from pathlib import Path

ROWS = [
    ("1. Window function, ranking before the report filters", "a1_window", "b1_window"),
    ("2. `DISTINCT ON`, ranking before the report filters", "a2_distinct_on", "b2_distinct_on"),
    ("3a. Report joins inside the ranking step, window function", "a3_window_joins_inside", None),
    ("3a. Report joins inside the ranking step, `DISTINCT ON`", "a9_distinct_on_joins_inside", None),
    ("3b. `ship_day` in `PARTITION BY`, quarter restated as a date range", "a4_window_partition_pushdown", None),
    ("4. Correlated `LATERAL ... ORDER BY ... LIMIT 1`", "a5_lateral_top1", "b5_lateral_top1"),
    ("4, derived values named in CTEs instead of `LATERAL`", "a6_cte_names_lateral_top1", None),
    ("5. Explicit validity periods", "a7_validity_period", "b7_validity_period"),
    ("5, derived values stored as generated columns", None, "b9_validity_period_stored_columns"),
    ("6. Priced at load time (reads stored prices)", "a8_precomputed", "b8_precomputed"),
]


def fmt(sec):
    return f"{sec:.1f}" if sec >= 10 else f"{sec:.2f}"


res = Path(sys.argv[1])
runs = {}
for line in (res / "timings.csv").read_text().splitlines()[1:]:
    q, _, ms = line.split(",")
    runs.setdefault(q, []).append(float(ms) / 1000)
med = {q: statistics.median(v) for q, v in runs.items()}
version = re.search(r"^PostgreSQL (\d+\.\d+)", (res / "environment.txt").read_text(), re.M).group(1)
setup = [float(v) / 1000 for v in re.findall(r"^Time: ([0-9.]+) ms", (res / "setup_methods.log").read_text(), re.M)]

print(f"| Method (PostgreSQL {version}) | Key-account report | Full-history report |")
print("|---|---:|---:|")
for label, a, b in ROWS:
    cells = [f"{fmt(med[q])} s" if q else "–" for q in (a, b)]
    print(f"| {label} | {cells[0]} | {cells[1]} |")
print()
print(f"Median of five interleaved runs after a warm-up, report execution time only. Method 6 excludes the initial "
      f"pricing of the history, `CREATE TABLE ... AS` {fmt(setup[0])} s and primary key {fmt(setup[1])} s "
      f"(one run each, `setup_methods.log`), and any later refresh or correction.")
