"""Check the plan statements of the article against every timed run of a results directory.

Usage: python3 tools/check_plans.py <results-dir>
Example: python3 tools/check_plans.py results/pg18

Prints one line per statement: OK, or FAIL with the runs that contradict it, and exits
with status 1 if any statement fails. The expected row counts and loops are those of the
published data set (setup.sql); a run with a changed generator will fail them.
"""
import re
import sys
from pathlib import Path

res = Path(sys.argv[1])
S = res / "sensitivity"


def plans(name, d=res):
    return {i: (d / f"{name}.run{i}.txt").read_text() for i in range(1, 6)}


def jit(t):
    m = re.search(r"Options: Inlining (\w+), Optimization (\w+)", t)
    return None if not m else (m.group(1) == "true", m.group(2) == "true")


checks = []


def claim(text, name, test, d=res):
    bad = [i for i, t in plans(name, d).items() if not test(t)]
    checks.append((text, name, bad))


# Method 1: window over 14.3 million candidates, sort spills to disk, parallel below Gather Merge
claim("a1: WindowAgg over Gather Merge of 14318273 rows, external merge sort", "a1_window",
      lambda t: "WindowAgg" in t and "Gather Merge" in t and re.search(r"actual rows=14318273(\.00)? ", t) is not None
      and "Sort Method: external merge" in t and "Incremental Sort" not in t)
claim("a1 work_mem=1GB: quicksort in memory, no external merge", "a1_window__work_mem_1GB",
      lambda t: "Sort Method: quicksort" in t and "external merge" not in t.split("WindowAgg")[1], S)
claim("b1: rate probes (Index Scan on rate_card_pkey, loops=4000000) below Gather Merge", "b1_window",
      lambda t: re.search(r"Index Scan using rate_card_pkey.*loops=4000000", t) is not None
      and t.index("Gather Merge") < t.index("Index Scan using rate_card_pkey"))
# Method 2: same shape as method 1 with Unique, full sort
for q in ("a2_distinct_on", "b2_distinct_on"):
    claim(f"{q}: Unique over sorted 14318273 candidates, no incremental sort", q,
          lambda t: "Unique" in t and re.search(r"actual rows=14318273(\.00)? ", t) is not None and "Incremental Sort" not in t
          and "WindowAgg" not in t)
# Method 3a: parallel rate join below Gather Merge, no JIT
for q in ("a3_window_joins_inside", "a9_distinct_on_joins_inside"):
    claim(f"{q}: no JIT, rate join below Gather Merge", q,
          lambda t: jit(t) is None and "Gather" in t
          and t.index("Gather") < t.index("rate_card r"))
# Method 3b: ranking over the quarter only
claim("a4: scan of shipment filtered to the quarter", "a4_window_partition_pushdown",
      lambda t: re.search(r"Parallel Seq Scan on shipment s.*\n\s+Filter: .*2026-04-01.*2026-07-01", t) is not None)
# Method 4: lookups above Gather Merge in the leader, 28206 loops, JIT without inlining
claim("a5: Limit loops=28206 above Gather Merge; bitmap scan returns ~20 rows, 5 after filter", "a5_lateral_top1",
      lambda t: "Limit" in t and re.search(r"Limit .*actual rows=1(\.00)? loops=28206", t) is not None
      and t.index("Gather Merge") < t.index("Limit")
      and re.search(r"Bitmap Heap Scan on rate_card r .*actual rows=(5|4\.\d\d|5\.\d\d) loops=28206", t) is not None
      and re.search(r"Bitmap Index Scan on rate_card_pkey .*actual rows=(19|2[0-2])(\.\d\d)? loops=28206", t) is not None
      and "Recheck Cond:" in t and jit(t) == (False, False))
claim("a6: same lookup shape as a5", "a6_cte_names_lateral_top1",
      lambda t: re.search(r"Limit .*actual rows=1(\.00)? loops=28206", t) is not None)
claim("b5: no parallel workers, lookup runs 4000000 times", "b5_lateral_top1",
      lambda t: "Workers Launched" not in t and re.search(r"Limit .*loops=4000000", t) is not None)
# Method 5: parallel nested loop, one pkey probe per shipment, lower bounds in Index Cond, upper in Filter
for q, loops in (("a7_validity_period", "28206"), ("b7_validity_period", "4000000")):
    claim(f"{q}: parallel pkey probe per shipment, zone+lower bounds index cond, upper bounds filter", q,
          lambda t, loops=loops: re.search(r"Index Scan using rate_card_period_pkey .*loops=" + loops, t) is not None
          and re.search(r"Index Cond: \(\(zone_id = z\.zone_id\) AND \(kg_from <= .*\) AND \(valid_from <= .*\)\)", t) is not None
          and re.search(r"Filter: .*< valid_to.*< kg_to|Filter: .*< kg_to.*< valid_to", t) is not None
          and "Gather" in t and t.index("Gather") < t.index("rate_card_period_pkey")
          and "_excl" not in t)
# Stored columns, default settings: memoised plan that checks the zone after the index probe
claim("b9 default: Memoize, zone checked as join filter after the probe", "b9_validity_period_stored_columns",
      lambda t: "Memoize" in t and "Join Filter: (r.zone_id = z.zone_id)" in t)
for v in ("memoize_off", "memoize_off_jit_off", "memoize_off_jit_full"):
    claim(f"b9 {v}: no Memoize", f"b9_validity_period_stored_columns__{v}",
          lambda t: "Memoize" not in t, S)
    claim(f"b7 {v}: no Memoize", f"b7_validity_period__{v}", lambda t: "Memoize" not in t, S)
claim("b9 memoize_off: JIT inlining and optimisation", "b9_validity_period_stored_columns__memoize_off",
      lambda t: jit(t) == (True, True), S)
claim("b7 memoize_off: JIT without inlining and optimisation", "b7_validity_period__memoize_off",
      lambda t: jit(t) == (False, False), S)
for q in ("b7_validity_period", "b9_validity_period_stored_columns"):
    claim(f"{q} jit_off: no JIT", f"{q}__memoize_off_jit_off", lambda t: jit(t) is None, S)
    claim(f"{q} jit_full: inlining and optimisation", f"{q}__memoize_off_jit_full",
          lambda t: jit(t) == (True, True), S)
# JIT-off sensitivity entries really ran without JIT
for q in ("a3_window_joins_inside", "a5_lateral_top1", "a6_cte_names_lateral_top1", "a7_validity_period",
          "a8_precomputed", "a9_distinct_on_joins_inside"):
    claim(f"{q} jit_off: no JIT", f"{q}__jit_off", lambda t: jit(t) is None, S)
# Naming control: same plan both ways
c1, c2 = plans("c1_names_cte"), plans("c2_names_lateral")
strip = lambda t: re.sub(r"\(actual.*?\)|Buffers:.*|Execution Time.*|Planning.*|Memory.*|Worker \d.*|Heap Blocks.*|Index Searches:.*", "", t)
checks.append(("c1/c2: identical plans (estimates and nodes)", "c1_names_cte vs c2_names_lateral",
               [i for i in range(1, 6) if strip(c1[i]) != strip(c2[i])]))

for text, name, bad in checks:
    print(("OK   " if not bad else "FAIL ") + text + ("" if not bad else f"  runs {bad}"))

sys.exit(1 if any(bad for _, _, bad in checks) else 0)
