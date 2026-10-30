#!/bin/bash
# Usage: ./run.sh <postgres-bin-dir> <port> <label>
#
# Builds a throwaway cluster with default settings, loads the data, creates the structures
# used by the alternative methods, runs the data checks and functional tests, and then times
# every query: one warm-up run each, followed by five rounds in which all timed entries
# (main queries and sensitivity checks) run once in a shuffled order. Raw output goes to
# results/<label>/. An existing results directory is never replaced unless FORCE=1 is set.
# Must not run as root (initdb refuses). psql must be on the path.
set -euo pipefail
B=$1; PORT=$2; L=$3
HERE=$(cd "$(dirname "$0")" && pwd)
D=$HERE/pgdata_$L; O=$HERE/results/$L
if [ -e "$O" ] && [ "${FORCE:-0}" != 1 ]; then
  echo "results/$L already exists; use another label, or set FORCE=1 to replace it" >&2
  exit 1
fi
rm -rf "$D" "$O"; mkdir -p "$O/sensitivity"
date -u "+started  %Y-%m-%d %H:%M:%S UTC" > "$O/run_times.txt"

"$B/initdb" -D "$D" -A trust >/dev/null
"$B/pg_ctl" -D "$D" -o "-p $PORT -k /tmp" -l "$O/server.log" -w start >/dev/null
TMPQ=$(mktemp)
cleanup() { "$B/pg_ctl" -D "$D" -m fast stop >/dev/null 2>&1 || true; rm -rf "$D" "$TMPQ" "$TMPQ.order"; }
trap cleanup EXIT

P="psql -X -q -v ON_ERROR_STOP=1 -h /tmp -p $PORT"
$P -d postgres -c "CREATE DATABASE ship"
P="$P -d ship"
$P -f "$HERE/setup.sql" >/dev/null
$P -f "$HERE/setup_methods.sql" > "$O/setup_methods.log" 2>&1

{
  echo "# server"; $P -Atc "SELECT version()"
  echo; echo "# settings"
  $P -Atc "SELECT name || ' = ' || current_setting(name) FROM pg_settings
           WHERE name IN ('shared_buffers','work_mem','maintenance_work_mem','effective_cache_size',
                          'max_parallel_workers_per_gather','max_parallel_workers','max_worker_processes',
                          'jit','jit_above_cost','jit_inline_above_cost','jit_optimize_above_cost',
                          'random_page_cost','seq_page_cost','from_collapse_limit','join_collapse_limit',
                          'geqo_threshold','default_statistics_target','TimeZone','enable_memoize')
           ORDER BY name"
  echo; echo "# tables (rows, size)"
  for t in customer dim_date zone rate_card rate_card_period shipment shipment_charge shipment_stored; do
    $P -Atc "SELECT '$t', count(*), pg_size_pretty(pg_table_size('$t')) FROM $t"
  done
  echo; echo "# indexes and constraints"
  $P -Atc "SELECT indexname || ' ON ' || tablename FROM pg_indexes WHERE schemaname = 'public' ORDER BY 1"
  $P -Atc "SELECT conrelid::regclass || ': ' || pg_get_constraintdef(oid) FROM pg_constraint WHERE contype = 'x'"
  echo; echo "# machine"; nproc; grep -m1 'model name' /proc/cpuinfo; grep MemTotal /proc/meminfo; uname -sr
} > "$O/environment.txt"

# Data checks quoted in the article, and functional tests (edge cases, per-shipment agreement)
$P -At -f "$HERE/checks.sql" > "$O/checks.txt"
$P -At -f "$HERE/tests.sql" > "$O/tests.txt"
if grep -q '|FAIL' "$O/tests.txt" || ! grep -q '|PASS' "$O/tests.txt"; then
  echo "functional tests failed, see $O/tests.txt" >&2; exit 1
fi

# Timed entries: name | query file | output directory | PGOPTIONS
ENTRIES=()
for f in "$HERE"/queries/*.sql; do
  q=$(basename "$f" .sql); ENTRIES+=("$q|$f|$O|")
done
S="$O/sensitivity"; QD="$HERE/queries"
ENTRIES+=("a1_window__work_mem_1GB|$QD/a1_window.sql|$S|-c work_mem=1GB")
for q in a3_window_joins_inside a5_lateral_top1 a6_cte_names_lateral_top1 a7_validity_period a8_precomputed a9_distinct_on_joins_inside; do
  ENTRIES+=("${q}__jit_off|$QD/$q.sql|$S|-c jit=off")
done
for q in b7_validity_period b9_validity_period_stored_columns; do
  ENTRIES+=("${q}__memoize_off|$QD/$q.sql|$S|-c enable_memoize=off")
  ENTRIES+=("${q}__memoize_off_jit_off|$QD/$q.sql|$S|-c enable_memoize=off -c jit=off")
  ENTRIES+=("${q}__memoize_off_jit_full|$QD/$q.sql|$S|-c enable_memoize=off -c jit_above_cost=0 -c jit_inline_above_cost=0 -c jit_optimize_above_cost=0")
done

EMPTY_MD5=$(printf '' | md5sum | cut -d' ' -f1)

# Warm-up: one run per entry; its output is hashed so that variants can be compared
for e in "${ENTRIES[@]}"; do
  IFS='|' read -r name f dir opts <<< "$e"
  out=$(PGOPTIONS="$opts" $P -At -f "$f" < /dev/null)
  [ -n "$out" ] || { echo "empty result: $name" >&2; exit 1; }
  printf '%s\n' "$out" | md5sum | cut -d' ' -f1 > "$dir/$name.result.md5"
  [ "$(cat "$dir/$name.result.md5")" != "$EMPTY_MD5" ] || { echo "empty hash: $name" >&2; exit 1; }
done

# Every key-account (a*), full-history (b*) and control (c*) variant must return the same result
for g in a b c; do
  n=$( { cat "$O"/$g*.result.md5 "$O"/sensitivity/$g*.result.md5 2>/dev/null || true; } | sort -u | wc -l)
  [ "$n" -eq 1 ] || { echo "result hashes differ within group $g" >&2; exit 1; }
done

# Five timed rounds, each in its own shuffled order (recorded in order.txt)
echo "query,run,execution_time_ms" > "$O/timings.csv"
echo "query,run,execution_time_ms" > "$S/timings.csv"
: > "$O/order.txt"
for i in 1 2 3 4 5; do
  printf '%s\n' "${ENTRIES[@]}" | awk -v seed="$i" 'BEGIN { srand(seed) } { print rand() "\t" $0 }' \
    | sort -k1,1g | cut -f2- > "$TMPQ.order"
  while IFS='|' read -r name f dir opts; do
    echo "$i,$name" >> "$O/order.txt"
    (echo "EXPLAIN (ANALYZE, BUFFERS, TIMING OFF)"; cat "$f") > "$TMPQ"
    PGOPTIONS="$opts" $P -At -f "$TMPQ" < /dev/null > "$dir/$name.run$i.txt"
    [ "$(grep -c 'Execution Time' "$dir/$name.run$i.txt")" -eq 1 ] \
      || { echo "unexpected EXPLAIN output: $name run $i" >&2; exit 1; }
    t=$(grep 'Execution Time' "$dir/$name.run$i.txt" | sed 's/[^0-9.]//g')
    echo "$name,$i,$t" >> "$dir/timings.csv"
  done < "$TMPQ.order"
done

date -u "+finished %Y-%m-%d %H:%M:%S UTC" >> "$O/run_times.txt"
"$HERE/summarise.sh" "$O" > "$O/summary.md"
echo done > "$O/DONE"
