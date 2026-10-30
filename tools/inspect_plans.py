"""Summarise the raw EXPLAIN output of a results directory: timings, JIT options, workers, key nodes.

Usage: python3 tools/inspect_plans.py <results-dir>
Example: python3 tools/inspect_plans.py results/pg18
"""
import re
import statistics
import sys
from pathlib import Path

res = Path(sys.argv[1])


def describe(path):
    t = path.read_text()
    jit = re.search(r"Options: Inlining (\w+), Optimization (\w+)", t)
    jit = f"inl={jit.group(1)[0]} opt={jit.group(2)[0]}" if jit else "no JIT"
    workers = sorted(set(re.findall(r"Workers Launched: (\d+)", t)))
    cost = re.match(r"\S.*?\(cost=[0-9.]+\.\.([0-9.]+)", t)
    feats = []
    for k in ("Memoize", "Incremental Sort", "WindowAgg", "Unique", "Bitmap Heap Scan", "Hash Join",
              "Merge Join", "external merge"):
        if k in t:
            feats.append(k)
    return jit, ",".join(workers) or "-", cost.group(1) if cost else "?", " ".join(feats)


for d in (res, res / "sensitivity"):
    rows = {}
    for line in (d / "timings.csv").read_text().splitlines()[1:]:
        q, run, ms = line.split(",")
        rows.setdefault(q, []).append((int(run), float(ms) / 1000))
    print(f"\n## {d.name}")
    print(f"{'query':52} {'median':>7} {'min':>7} {'max':>7}  jit/workers/cost per run")
    for q in sorted(rows):
        v = [s for _, s in rows[q]]
        per_run = []
        for run, _ in sorted(rows[q]):
            jit, w, cost, feats = describe(d / f"{q}.run{run}.txt")
            per_run.append((jit, w, cost, feats))
        uniq = sorted(set(per_run))
        print(f"{q:52} {statistics.median(v):7.2f} {min(v):7.2f} {max(v):7.2f}  " +
              " | ".join(f"{j} w={w} cost={c} [{f}]" for j, w, c, f in uniq))
