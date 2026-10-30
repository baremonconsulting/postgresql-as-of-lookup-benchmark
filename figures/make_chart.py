"""Build the results chart of the article (HTML with inline SVG) from a results directory.

Usage: python3 figures/make_chart.py <results-dir> <out.html>
Example: python3 figures/make_chart.py results/pg18 figures/source/as-of-lookup-results.html

The chart shows the median Execution Time of each query (timings.csv), the server version
(environment.txt) and the time of the initial pricing for method 6 (setup_methods.log).
Render it to PNG with figures/render.py.
"""
import math
import re
import statistics
import sys
from pathlib import Path

res, out = Path(sys.argv[1]), sys.argv[2]
runs = {}
for line in (res / "timings.csv").read_text().splitlines()[1:]:
    q, _, ms = line.split(",")
    runs.setdefault(q, []).append(float(ms) / 1000)
med = {q: statistics.median(v) for q, v in runs.items()}
pg_version = re.search(r"^PostgreSQL (\d+\.\d+)", (res / "environment.txt").read_text(), re.M).group(1)
load_sec = float(re.search(r"^Time: ([0-9.]+) ms", (res / "setup_methods.log").read_text(), re.M).group(1)) / 1000

W, H = 1200, 904
BLUE, ORANGE = "#112B3C", "#F66B0F"   # Baremon navy and orange
NAVY, GREY, MUTED, GRID, ROWLINE = "#112B3C", "#586570", "#7A8792", "#E3E9ED", "#F2F5F7"

groups = [
    ("THE RULE STAYS IN THE QUERY", [
        ("1", "Window function, before filters", "a1_window", "b1_window"),
        ("2", "DISTINCT ON, before filters", "a2_distinct_on", "b2_distinct_on"),
        ("3a", "Window function, joins inside", "a3_window_joins_inside", None),
        ("3a", "DISTINCT ON, joins inside", "a9_distinct_on_joins_inside", None),
        ("3b", "Pushable date condition", "a4_window_partition_pushdown", None),
        ("4", "Correlated LATERAL lookup", "a5_lateral_top1", "b5_lateral_top1"),
    ]),
    ("THE RULE MOVES INTO THE DATA MODEL OR THE LOAD PROCESS", [
        ("5", "Validity periods", "a7_validity_period", "b7_validity_period"),
        ("6", "Reads prices stored at load time", "a8_precomputed", "b8_precomputed"),
    ]),
]

left, right = 432, 1010          # plot area: 0.1 s .. 100 s
xmin, xmax = 0.1, 100.0
row_h, head_h = 62, 40


def x(sec):
    return left + (math.log10(sec) - math.log10(xmin)) / (math.log10(xmax) - math.log10(xmin)) * (right - left)


def fmt(sec):
    return f"{sec:.1f}" if sec >= 10 else f"{sec:.2f}"


svg, y = [], 196
plot_top = y - 8
for title, rows in groups:
    svg.append(f'<text x="40" y="{y + 16}" class="group">{title}</text>')
    y += head_h
    for num, name, a, b in rows:
        cy = y + row_h / 2
        svg.append(f'<line x1="40" y1="{y:.1f}" x2="{W - 40}" y2="{y:.1f}" stroke="{ROWLINE}" stroke-width="1"/>')
        svg.append(f'<text x="40" y="{cy + 7}" class="num">{num}</text>')
        svg.append(f'<text x="82" y="{cy + 7}" class="name">{name}</text>')
        va, vb = med[a], (med[b] if b else None)
        if vb is not None:
            x1, x2 = sorted((x(va), x(vb)))
            svg.append(f'<line x1="{x1:.1f}" y1="{cy}" x2="{x2:.1f}" y2="{cy}" stroke="#CBD6DE" stroke-width="2" stroke-linecap="round"/>')
        close = vb is not None and abs(x(va) - x(vb)) < 22
        for val, colour, dy in [(va, BLUE, -6 if close else 0)] + ([(vb, ORANGE, 6 if close else 0)] if vb is not None else []):
            svg.append(f'<circle cx="{x(val):.1f}" cy="{cy + dy}" r="9" fill="{colour}" stroke="#FFFFFF" stroke-width="2"/>')
        if vb is None:
            svg.append(f'<text x="{x(va) + 18:.1f}" y="{cy + 6}" class="val">{fmt(va)} s</text>')
            svg.append(f'<text x="{W - 40}" y="{cy + 6}" text-anchor="end" class="note">no full-history variant</text>')
        else:
            # smaller value to the left of its dot, larger value to the right of its dot
            lo, hi = sorted((va, vb))
            svg.append(f'<text x="{x(lo) - 18:.1f}" y="{cy + 6}" text-anchor="end" class="val">{fmt(lo)} s</text>')
            svg.append(f'<text x="{x(hi) + 18:.1f}" y="{cy + 6}" class="val">{fmt(hi)} s</text>')
        y += row_h
    y += 10
plot_bottom = y - 10

grid = []
for t in (0.1, 0.3, 1, 3, 10, 30, 100):
    gx = x(t)
    grid.append(f'<line x1="{gx:.1f}" y1="{plot_top}" x2="{gx:.1f}" y2="{plot_bottom}" stroke="{GRID}" stroke-width="1"/>')
    label = {0.1: "0.1 s", 100: "100 s"}.get(t, f"{t:g}")
    grid.append(f'<text x="{gx:.1f}" y="{plot_bottom + 30}" text-anchor="middle" class="tick">{label}</text>')

html = f"""<!doctype html>
<html lang="en-GB"><head><meta charset="utf-8"><title>As-of lookup results</title>
<style>
html, body {{ margin: 0; background: #FFFFFF; }}
body {{ width: {W}px; height: {H}px; font-family: Inter, Arial, sans-serif; color: {NAVY}; position: relative; }}
.wrap {{ padding: 40px 40px 0; }}
h1 {{ font-size: 32px; margin: 0; font-weight: 700; letter-spacing: -0.01em; }}
.sub {{ font-size: 18px; line-height: 1.4; color: {GREY}; margin: 10px 0 0; }}
.legend {{ display: flex; gap: 30px; margin-top: 18px; font-size: 18px; color: {NAVY}; }}
.legend span {{ display: inline-flex; align-items: center; gap: 10px; }}
.dot {{ width: 16px; height: 16px; border-radius: 50%; display: inline-block; }}
svg {{ position: absolute; left: 0; top: 0; }}
.tick {{ font-size: 16px; fill: {GREY}; font-variant-numeric: tabular-nums; }}
.group {{ font-size: 14px; font-weight: 600; letter-spacing: .08em; fill: {GREY}; }}
.num {{ font-size: 19px; font-weight: 700; fill: {NAVY}; }}
.name {{ font-size: 19px; fill: {NAVY}; }}
.val {{ font-size: 16px; fill: {NAVY}; font-variant-numeric: tabular-nums; }}
.note {{ font-size: 14px; fill: {MUTED}; font-style: italic; }}
.foot {{ position: absolute; left: 40px; right: 40px; bottom: 20px; display: flex; justify-content: space-between; align-items: flex-end; gap: 40px; font-size: 14px; line-height: 1.45; color: {GREY}; }}
</style></head><body>
<div class="wrap">
  <h1>Same report results, different execution times</h1>
  <p class="sub">Median report execution time of each method, logarithmic scale. PostgreSQL {pg_version}, default settings, 2 vCPUs, 8 GB RAM.</p>
  <div class="legend">
    <span><i class="dot" style="background:{BLUE}"></i>Key-account report (0.7% of shipments)</span>
    <span><i class="dot" style="background:{ORANGE}"></i>Full-history report (all 4 million shipments)</span>
  </div>
</div>
<svg width="{W}" height="{H}" viewBox="0 0 {W} {H}" role="img" aria-label="Median report execution times per method">
{chr(10).join(grid)}
{chr(10).join(svg)}
</svg>
<div class="foot"><span>Five interleaved runs per query after a warm-up. Report execution times only: method 6 excludes the initial pricing<br>of the history ({fmt(load_sec)} s) and any refresh or correction. Scripts and raw EXPLAIN output are in the benchmark package.</span><span>baremon.eu</span></div>
</body></html>
"""
open(out, "w", encoding="utf-8").write(html)
print("chart written:", out)
