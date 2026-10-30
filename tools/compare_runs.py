"""Compare the medians of two benchmark runs, for example PostgreSQL 18 against 16.

Usage: python3 tools/compare_runs.py <results-dir-a> <results-dir-b>
Example: python3 tools/compare_runs.py results/pg18 results/pg16

Prints median, A/B ratio and range of every query present in both runs, then the order
of the methods by median in each run. The published runs ran on different instances of
the same VM, so their absolute times are not directly comparable.
"""
import statistics
import sys
from pathlib import Path


def medians(d):
    out = {}
    for sub in ("", "sensitivity"):
        runs = {}
        for line in (Path(d) / sub / "timings.csv").read_text().splitlines()[1:]:
            q, _, ms = line.split(",")
            runs.setdefault(q, []).append(float(ms) / 1000)
        out.update({q: (statistics.median(v), min(v), max(v)) for q, v in runs.items()})
    return out


a, b = medians(sys.argv[1]), medians(sys.argv[2])
print(f"{'query':58} {'A med':>8} {'B med':>8} {'A/B':>6}   A range        B range")
for q in sorted(set(a) | set(b)):
    if q in a and q in b:
        print(f"{q:58} {a[q][0]:8.2f} {b[q][0]:8.2f} {a[q][0] / b[q][0]:6.2f}   "
              f"{a[q][1]:.2f}-{a[q][2]:.2f}    {b[q][1]:.2f}-{b[q][2]:.2f}")

for prefix in ("a", "b"):
    qs = [q for q in a if q.startswith(prefix) and "__" not in q and q in b]
    oa = sorted(qs, key=lambda q: a[q][0])
    ob = sorted(qs, key=lambda q: b[q][0])
    print(f"\norder {prefix}* A: " + " < ".join(q.split('_')[0] for q in oa))
    print(f"order {prefix}* B: " + " < ".join(q.split('_')[0] for q in ob))
