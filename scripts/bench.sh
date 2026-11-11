#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
BEFORE=${1:?FAIL setup: baseline binary required}
AFTER=${2:-.work/bench-after}
CORE=${BENCH_CPU:-15}
for round in 1 2 3; do
  order=(before after)
  if [ "$round" -eq 2 ]; then order=(after before); fi
  for side in "${order[@]}"; do
    binary=$BEFORE
    if [ "$side" = after ]; then binary=$AFTER; fi
    echo "BEGIN $side round $round cpu $CORE"
    scripts/capped.sh /usr/bin/time -f 'wall_s %e peak_kb %M' taskset -c "$CORE" "$binary"
  done
  echo "BEGIN reference round $round cpu $CORE"
  scripts/capped.sh /usr/bin/time -f 'wall_s %e peak_kb %M' taskset -c "$CORE" python3 -I tools/bench_ref.py
done
