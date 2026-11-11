#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .work/docs
awk '/^```mojo$/{active=1; next} /^```$/{active=0} active' README.md > .work/docs/readme.mojo
[ -s .work/docs/readme.mojo ] || { echo 'FAIL docs: no README Mojo example'; exit 1; }
scripts/capped.sh "${MOJO:-.venv/bin/mojo}" run -I src .work/docs/readme.mojo
printf 'PASS docs\n'
