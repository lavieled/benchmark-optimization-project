#!/usr/bin/env bash
# Nbody: venv, original vs optimized pyperf runs, optional perf/flamegraph, compare.
#
#   chmod +x nbody/script_nbody.sh
#   ./nbody/script_nbody.sh
#
# Inside the QEMU Ubuntu guest (python3-dbg + perf for RUN_PERF=1).
#
# Optional env:
#   ITERS=20000 WORKERS=2 RUN_PERF=1 ./nbody/script_nbody.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NBODY="$ROOT/nbody"
RESULTS="$NBODY/results"
cd "$ROOT"

if command -v python3 >/dev/null 2>&1; then
  PY="${PYTHON:-python3}"
elif command -v python >/dev/null 2>&1; then
  PY="${PYTHON:-python}"
else
  echo "ERROR: python3 not found" >&2
  exit 1
fi

ITERS="${ITERS:-20000}"
WORKERS="${WORKERS:-2}"
VALUES="${VALUES:-5}"
WARMUPS="${WARMUPS:-1}"
RUN_PERF="${RUN_PERF:-0}"
VENV="${VENV:-$ROOT/.venv}"

mkdir -p "$RESULTS"

if [[ ! -d "$VENV" ]]; then
  "$PY" -m venv "$VENV"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -q --upgrade pip
pip install -q pyperf numpy numba

echo "=== energy check (original vs optimized) ==="
"$PY" "$NBODY/verify_energy.py"

echo "=== original nbody (pyperf) ==="
"$PY" -u "$NBODY/run_benchmark.py" \
  -o "$RESULTS/nbody_original.json" \
  -w "$WARMUPS" -n "$VALUES" \
  --iterations "$ITERS"

echo "=== optimized nbody (pyperf) ==="
"$PY" -u "$NBODY/optimized/run_benchmark.py" \
  -o "$RESULTS/nbody_optimized.json" \
  -w "$WARMUPS" -n "$VALUES" \
  --iterations "$ITERS"

echo "=== compare ==="
pyperf compare_to "$RESULTS/nbody_original.json" "$RESULTS/nbody_optimized.json" \
  | tee "$RESULTS/nbody_compare.txt"

if [[ "$RUN_PERF" == "1" ]]; then
  if ! command -v perf >/dev/null 2>&1; then
    echo "WARN: perf not found; skip profiling" >&2
  else
    DBG="${PYTHON_DBG:-}"
    if [[ -z "$DBG" ]]; then
      if command -v python3-dbg >/dev/null 2>&1; then
        DBG=python3-dbg
      else
        DBG="$PY"
        echo "WARN: python3-dbg not found; using $DBG" >&2
      fi
    fi
    echo "=== perf record (original) ==="
    perf record -F 999 -g -o "$RESULTS/nbody_original.perf.data" -- \
      "$DBG" -u "$NBODY/run_benchmark.py" -w0 -n1 --iterations "$ITERS" || true
    if [[ -f "$RESULTS/nbody_original.perf.data" ]]; then
      perf report -i "$RESULTS/nbody_original.perf.data" --stdio \
        > "$RESULTS/nbody_perf_report.txt" || true
      if command -v stackcollapse-perf.pl >/dev/null 2>&1 && command -v flamegraph.pl >/dev/null 2>&1; then
        perf script -i "$RESULTS/nbody_original.perf.data" \
          | stackcollapse-perf.pl \
          | flamegraph.pl > "$RESULTS/nbody_baseline.svg" || true
      else
        echo "WARN: FlameGraph scripts not on PATH; kept perf report only" >&2
      fi
      rm -f "$RESULTS/nbody_original.perf.data"
    fi
  fi
fi

echo "Done. Results in $RESULTS"
