#!/bin/bash
# Usage: ./summarise.sh <results-dir>
# Prints median, minimum and maximum execution time per query, and the result hashes.
O=$1
table() {
  echo "| Query | Median (s) | Min (s) | Max (s) | Result hash |"
  echo "|---|---:|---:|---:|---|"
  tail -n +2 "$1/timings.csv" | cut -d, -f1 | sort -u | while read -r q; do
    grep "^$q," "$1/timings.csv" | cut -d, -f3 | sort -g |
      awk -v q="$q" -v h="$(cut -c1-8 "$1/$q.result.md5")" \
        '{v[NR]=$1} END {printf "| %s | %.2f | %.2f | %.2f | %s |\n", q, v[int((NR+1)/2)]/1000, v[1]/1000, v[NR]/1000, h}'
  done
}
echo "# Results: $(basename "$O")"; echo
head -1 "$O/environment.txt" >/dev/null; sed -n '2p' "$O/environment.txt"; echo
echo "Execution Time from EXPLAIN (ANALYZE, BUFFERS, TIMING OFF): one warm-up run, then five timed runs in interleaved, shuffled rounds (order.txt)."; echo
sed "s/^/- Run /" "$O/run_times.txt"; echo
table "$O"; echo
echo "## Sensitivity checks"; echo
table "$O/sensitivity"; echo
echo "## Initial population of shipment_charge (setup_methods.sql)"; echo
echo "CREATE TABLE ... AS: $(grep -E '^Time:' "$O/setup_methods.log" | sed -n 1p)"
echo
echo "Primary key: $(grep -E '^Time:' "$O/setup_methods.log" | sed -n 2p)"
echo; echo "## Functional tests (tests.txt)"; echo
sed 's/^/- /' "$O/tests.txt"
