#!/usr/bin/env bash
# Nbody: venv, original vs optimized pyperf runs, optional perf/flamegraph, compare.
#
#   chmod +x nbody/script_nbody.sh
#   ./nbody/script_nbody.sh
#
# Inside the QEMU Ubuntu guest (python3-dbg + perf for RUN_PERF=1).
#
# Optional env:
#   ITERS=20000 RUN_PERF=1 ./nbody/script_nbody.sh
#   ONLY_CPYTHON=1   # new CPython-only results only; do not overwrite Numba/original
# Defaults match the official QEMU table: pyperf -w1 -n3 -p1.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NBODY="$ROOT/nbody"
RESULTS="$NBODY/results"
TOOLS="$NBODY/tools"
FLAMEGRAPH_DIR="${FLAMEGRAPH_DIR:-$TOOLS/FlameGraph}"
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
WORKERS="${WORKERS:-1}"
VALUES="${VALUES:-3}"
WARMUPS="${WARMUPS:-1}"
RUN_PERF="${RUN_PERF:-0}"
ONLY_CPYTHON="${ONLY_CPYTHON:-0}"
VENV="${VENV:-$ROOT/.venv}"
VENV_DBG="${VENV_DBG:-$ROOT/.venv-dbg}"

mkdir -p "$RESULTS"

if [[ ! -d "$VENV" ]]; then
  "$PY" -m venv "$VENV"
fi
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -q --upgrade pip
pip install -q pyperf numpy numba

PY_TIMING="$VENV/bin/python"

echo "=== energy check (original vs Numba vs CPython-only) ==="
"$PY_TIMING" "$NBODY/verify_energy.py"

if [[ "$ONLY_CPYTHON" != "1" ]]; then
  echo "=== original nbody (pyperf) ==="
  "$PY_TIMING" -u "$NBODY/run_benchmark.py" \
    -o "$RESULTS/nbody_original.json" \
    -w "$WARMUPS" -n "$VALUES" -p "$WORKERS" \
    --iterations "$ITERS"

  echo "=== Numba optimized nbody (pyperf) ==="
  "$PY_TIMING" -u "$NBODY/optimized/run_benchmark.py" \
    -o "$RESULTS/nbody_optimized.json" \
    -w "$WARMUPS" -n "$VALUES" -p "$WORKERS" \
    --iterations "$ITERS"
fi

if [[ ! -f "$RESULTS/nbody_original.json" ]]; then
  echo "ERROR: nbody/results/nbody_original.json missing (needed to compare)." >&2
  exit 1
fi

echo "=== CPython-only optimized nbody (pyperf, no Numba) ==="
"$PY_TIMING" -u "$NBODY/optimized_cpython.py" \
  -o "$RESULTS/nbody_cpython.json" \
  -w "$WARMUPS" -n "$VALUES" -p "$WORKERS" \
  --iterations "$ITERS"

if [[ "$ONLY_CPYTHON" != "1" ]]; then
  echo "=== compare (original vs Numba) ==="
  pyperf compare_to "$RESULTS/nbody_original.json" "$RESULTS/nbody_optimized.json" \
    | tee "$RESULTS/nbody_compare.txt"
fi

echo "=== compare (original vs CPython-only) ==="
pyperf compare_to "$RESULTS/nbody_original.json" "$RESULTS/nbody_cpython.json" \
  | tee "$RESULTS/nbody_cpython_compare.txt"

ensure_flamegraph() {
  if [[ -x "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" && -x "$FLAMEGRAPH_DIR/flamegraph.pl" ]]; then
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "WARN: git not found; cannot clone FlameGraph" >&2
    return 1
  fi
  echo "=== clone FlameGraph ==="
  mkdir -p "$TOOLS"
  rm -rf "$FLAMEGRAPH_DIR"
  git clone --depth 1 https://github.com/brendangregg/FlameGraph "$FLAMEGRAPH_DIR"
}

record_and_report() {
  local label="$1"
  local interpreter="$2"
  local bench="$3"
  local perf_data="$4"
  local report_txt="$5"
  local svg_out="$6"

  echo "=== perf record ($label) ==="
  rm -f "$perf_data"
  perf record -F 999 -g -o "$perf_data" -- \
    "$interpreter" -u "$bench" -w0 -n1 -p1 --iterations "$ITERS" || true

  if [[ ! -f "$perf_data" ]]; then
    echo "WARN: no perf data for $label" >&2
    return 0
  fi

  perf report -i "$perf_data" --stdio > "$report_txt" || true

  if [[ -x "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" && -x "$FLAMEGRAPH_DIR/flamegraph.pl" ]]; then
    perf script -i "$perf_data" \
      | "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" \
      | "$FLAMEGRAPH_DIR/flamegraph.pl" --title "nbody $label" \
      > "$svg_out" || true
  else
    echo "WARN: FlameGraph scripts missing; kept $report_txt only" >&2
  fi
  rm -f "$perf_data"
}

if [[ "$RUN_PERF" == "1" ]]; then
  if ! command -v perf >/dev/null 2>&1; then
    echo "WARN: perf not found; skip profiling" >&2
  else
    ensure_flamegraph || true

    # Course requires python3-dbg so perf can resolve CPython internals.
    if ! command -v python3-dbg >/dev/null 2>&1; then
      echo "ERROR: python3-dbg not found. Course profiles must use the debug build." >&2
      echo "Install python3-dbg (or dpkg the jammy *-dbg debs) and re-run RUN_PERF=1." >&2
      exit 1
    fi
    if [[ ! -d "$VENV_DBG" ]]; then
      echo "=== python3-dbg venv ($VENV_DBG) ==="
      python3-dbg -m venv "$VENV_DBG" || {
        echo "WARN: python3-dbg -m venv failed; using python3-dbg + PYTHONPATH" >&2
      }
    fi
    if [[ -x "$VENV_DBG/bin/pip" ]]; then
      "$VENV_DBG/bin/pip" install -q --upgrade pip
      "$VENV_DBG/bin/pip" install -q pyperf
      DBG_PY="$VENV_DBG/bin/python"
    else
      DBG_PY=python3-dbg
    fi

    if [[ "$ONLY_CPYTHON" != "1" ]]; then
      record_and_report "original python3-dbg" "$DBG_PY" \
        "$NBODY/run_benchmark.py" \
        "$RESULTS/nbody_original.perf.data" \
        "$RESULTS/nbody_perf_report.txt" \
        "$RESULTS/nbody_baseline.svg"

      # Numba often fails on debug Python; profile with regular python3.
      record_and_report "optimized numba python3" "$PY_TIMING" \
        "$NBODY/optimized/run_benchmark.py" \
        "$RESULTS/nbody_optimized.perf.data" \
        "$RESULTS/nbody_optimized_perf_report.txt" \
        "$RESULTS/nbody_optimized.svg"
    fi

    # Pure CPython: python3-dbg is valid and matches the course profile method.
    record_and_report "optimized cpython python3-dbg" "$DBG_PY" \
      "$NBODY/optimized_cpython.py" \
      "$RESULTS/nbody_cpython.perf.data" \
      "$RESULTS/nbody_cpython_perf_report.txt" \
      "$RESULTS/nbody_cpython.svg"
  fi
fi

echo "Done. Results in $RESULTS"
