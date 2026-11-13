#!/usr/bin/env bash
# CI entry point (GitHub runner or local): install, build, then every gate. MOJO=path overrides the toolchain.
# Ends with "PASS n/m" (or "FAIL k/m"): the README checks badge parses that line.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v uv >/dev/null || { echo "FAIL setup: uv not installed"; exit 1; }
uv python install 3.14 || { echo "FAIL setup: python 3.14"; exit 1; }
if [ -z "${MOJO:-}" ]; then
  uv sync -q --python 3.14 || { echo "FAIL setup: uv sync"; exit 1; }
  MOJO=.venv/bin/mojo
fi
"$MOJO" --version
# the oracle is Python 3.14 on every channel: 3.12 words errors differently (MOJO= used to skip this and fall back)
ORACLE_PY=$(uv python find 3.14) || { echo "FAIL setup: python 3.14 not found"; exit 1; }; export ORACLE_PY
mkdir -p .work/t
for t in tests/cases:.work/cases tests/api:.work/t/api tests/test_golden:.work/t/golden tests/test_roundtrip:.work/t/roundtrip examples/quickstart:.work/t/quickstart; do
  scripts/capped.sh "$MOJO" build -O3 -I src -I tests ${MOJO_FLAGS:-} "${t%%:*}.mojo" -o "${t##*:}" 2>.work/build.err || { echo "FAIL build: ${t%%:*}.mojo"; cat .work/build.err; echo "FAIL 6/6"; exit 1; }
done
m=7; ok=0
gate() { local name=$1; shift; if "$@"; then ok=$((ok+1)); echo "ok $name"; else echo "FAIL $name"; echo "FAIL $((m-ok))/$m"; exit 1; fi; }
gate oracle env CASES=.work/cases scripts/check.sh
gate golden scripts/capped.sh .work/t/golden
gate roundtrip scripts/capped.sh .work/t/roundtrip
gate mutants env MOJO="$MOJO" scripts/mutants.sh
gate api scripts/capped.sh .work/t/api
gate quickstart scripts/capped.sh sh -c '.work/t/quickstart > /dev/null'
gate docs env MOJO="$MOJO" scripts/docs.sh
echo "PASS $ok/$m"
echo "PASS ci"
