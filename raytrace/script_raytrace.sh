#!/usr/bin/env bash
# Raytrace: venv setup, original vs refactored pyperf runs, perf stat comparison, optional perf/flamegraph, compare.
#
# Usage:
#   chmod +x script_raytrace.sh
#   ./script_raytrace.sh
#
# Optional environment variables:
#   RUN_STAT=1 ./script_raytrace.sh                  # Run pyperf + perf stat comparison table
#   RUN_PERF=1 ./script_raytrace.sh                  # Run pyperf + perf stat + flamegraphs
#   ITERS=10 WORKERS=1 RUN_STAT=1 ./script_raytrace.sh

set -euo pipefail

# Set RAYTRACE to the directory containing this script
RAYTRACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS="$RAYTRACE/results"
TOOLS="$RAYTRACE/tools"
FLAMEGRAPH_DIR="${FLAMEGRAPH_DIR:-$TOOLS/FlameGraph}"
cd "$RAYTRACE"

# Detect default Python binary
if command -v python3 >/dev/null 2>&1; then
  PY="${PYTHON:-python3}"
elif command -v python >/dev/null 2>&1; then
  PY="${PYTHON:-python}"
else
  echo "ERROR: python3 not found" >&2
  exit 1
fi

# Configuration parameters with sensible defaults
ITERS="${ITERS:-1}"
WORKERS="${WORKERS:-2}"
VALUES="${VALUES:-5}"
WARMUPS="${WARMUPS:-1}"
RUN_STAT="${RUN_STAT:-0}"
RUN_PERF="${RUN_PERF:-0}"
VENV="${VENV:-$RAYTRACE/.venv}"
VENV_DBG="${VENV_DBG:-$RAYTRACE/.venv-dbg}"

# Auto-enable RUN_STAT if RUN_PERF is set
if [[ "$RUN_PERF" == "1" ]]; then
  RUN_STAT=1
fi

mkdir -p "$RESULTS"

# ------------------------------------------------------------------------------
# 1. Virtual Environment & Dependencies Setup
# ------------------------------------------------------------------------------
if [[ ! -d "$VENV" ]]; then
  echo "=== Creating Python virtual environment ($VENV) ==="
  "$PY" -m venv "$VENV"
fi

# Activate virtual environment
# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -q --upgrade pip
pip install -q pyperf

PY_TIMING="$VENV/bin/python"

# ------------------------------------------------------------------------------
# 2. Pyperf Benchmark Execution
# ------------------------------------------------------------------------------
echo "=== Original raytrace benchmark (pyperf) ==="
"$PY_TIMING" -u "$RAYTRACE/run_benchmark_original.py" \
  --quiet \
  -o "$RESULTS/raytrace_original.json" \
  -w "$WARMUPS" -n "$VALUES" -p "$WORKERS" \
  --loops "$ITERS"

echo "=== Refactored/Optimized raytrace benchmark (pyperf) ==="
"$PY_TIMING" -u "$RAYTRACE/run_benchmark_optimized.py" \
  --quiet \
  -o "$RESULTS/raytrace_optimized.json" \
  -w "$WARMUPS" -n "$VALUES" -p "$WORKERS" \
  --loops "$ITERS"

if [[ ! -f "$RESULTS/raytrace_original.json" || ! -f "$RESULTS/raytrace_optimized.json" ]]; then
  echo "ERROR: Benchmark JSON outputs missing. Cannot proceed with comparison." >&2
  exit 1
fi

echo "=== Benchmark Comparison (Original vs Optimized) ==="
pyperf compare_to "$RESULTS/raytrace_original.json" "$RESULTS/raytrace_optimized.json" \
  | tee "$RESULTS/raytrace_compare.txt"

# ------------------------------------------------------------------------------
# 3. Hardware Metrics via perf stat (RUN_STAT=1)
# ------------------------------------------------------------------------------
if [[ "$RUN_STAT" == "1" ]]; then
  if ! command -v perf >/dev/null 2>&1; then
    echo "WARN: Linux perf tool not found; skipping perf stat stage" >&2
  else
    echo "=== Running perf stat profiling ==="
    
    STAT_RAW_ORIG="$RESULTS/.perf_stat_orig.tmp"
    STAT_RAW_OPT="$RESULTS/.perf_stat_opt.tmp"
    STAT_TABLE="$RESULTS/raytrace_perf_stat_comparison.txt"

    EVENTS="task-clock,context-switches,page-faults,cycles,instructions,branches,branch-misses"

    # Run perf stat on Original (--quiet added here)
    perf stat -x ';' -e "$EVENTS" -o "$STAT_RAW_ORIG" -- \
      "$PY_TIMING" -u "$RAYTRACE/run_benchmark_original.py" --quiet -w0 -n1 -p1 --loops "$ITERS" >/dev/null 2>&1 || true

    # Run perf stat on Optimized (--quiet added here)
    perf stat -x ';' -e "$EVENTS" -o "$STAT_RAW_OPT" -- \
      "$PY_TIMING" -u "$RAYTRACE/run_benchmark_optimized.py" --quiet -w0 -n1 -p1 --loops "$ITERS" >/dev/null 2>&1 || true

    # Generate Comparison Table via Python parser script
    "$PY_TIMING" - "$STAT_RAW_ORIG" "$STAT_RAW_OPT" "$STAT_TABLE" << 'EOF'
import sys, re

def parse_perf_csv(filepath):
    data = {}
    try:
        with open(filepath, 'r') as f:
            for line in f:
                parts = line.strip().split(';')
                if len(parts) >= 3:
                    val_str, unit, event = parts[0], parts[1], parts[2]
                    val_clean = re.sub(r'[^\d.]', '', val_str)
                    if val_clean:
                        data[event] = float(val_clean)
    except Exception as e:
        pass
    return data

orig_file, opt_file, out_file = sys.argv[1], sys.argv[2], sys.argv[3]
orig = parse_perf_csv(orig_file)
opt = parse_perf_csv(opt_file)

events_display = [
    ("task-clock", "Task Clock (msec)"),
    ("cycles", "CPU Cycles"),
    ("instructions", "Instructions executed"),
    ("branches", "Branch Instructions"),
    ("branch-misses", "Branch Misses"),
    ("page-faults", "Page Faults"),
    ("context-switches", "Context Switches")
]

table = []
table.append("=" * 80)
table.append(f"{'PERF STAT METRIC COMPARISON':^80}")
table.append("=" * 80)
table.append(f"{'Event / Metric':<28} | {'Original':<15} | {'Optimized':<15} | {'Diff (%)':<12}")
table.append("-" * 80)

for ev_key, ev_name in events_display:
    v_orig = orig.get(ev_key, 0.0)
    v_opt = opt.get(ev_key, 0.0)
    
    if v_orig > 0:
        pct_diff = ((v_opt - v_orig) / v_orig) * 100.0
        diff_str = f"{pct_diff:+.2f}%"
    else:
        diff_str = "N/A"

    if "clock" in ev_key:
        s_orig = f"{v_orig:,.2f}"
        s_opt = f"{v_opt:,.2f}"
    else:
        s_orig = f"{int(v_orig):,}"
        s_opt = f"{int(v_opt):,}"

    table.append(f"{ev_name:<28} | {s_orig:<15} | {s_opt:<15} | {diff_str:<12}")

# Add derived IPC (Instructions Per Cycle) metric if available
if orig.get("cycles", 0) > 0 and opt.get("cycles", 0) > 0:
    ipc_orig = orig.get("instructions", 0) / orig["cycles"]
    ipc_opt = opt.get("instructions", 0) / opt["cycles"]
    ipc_diff = ((ipc_opt - ipc_orig) / ipc_orig) * 100.0
    table.append("-" * 80)
    table.append(f"{'IPC (Inst per Cycle)':<28} | {ipc_orig:<15.3f} | {ipc_opt:<15.3f} | {ipc_diff:+.2f}%")

table.append("=" * 80)

output_content = "\n".join(table) + "\n"

with open(out_file, "w") as f:
    f.write(output_content)

EOF

    # Clean up raw temporary perf data
    rm -f "$STAT_RAW_ORIG" "$STAT_RAW_OPT"
  fi
fi

# ------------------------------------------------------------------------------
# 4. Helper Functions for Profiling & FlameGraph Generation
# ------------------------------------------------------------------------------
ensure_flamegraph() {
  if [[ -x "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" && -x "$FLAMEGRAPH_DIR/flamegraph.pl" ]]; then
    return 0
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "WARN: git not found; cannot clone FlameGraph toolkit" >&2
    return 1
  fi
  echo "=== Cloning FlameGraph toolkit ==="
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
  
  # Redirect perf stderr to /dev/null to hide kptr_restrict / bpf noise
  perf record -F 999 -g -e cpu-clock -o "$perf_data" -- \
    "$interpreter" -u "$bench" --quiet -w0 -n1 -p1 --loops "$ITERS" 2>/dev/null || true

  if [[ ! -s "$perf_data" ]]; then
    echo "ERROR: $perf_data was not created or is empty!" >&2
    return 1
  fi

  echo "=== Generating perf report ($label) ==="
  perf report -i "$perf_data" --stdio > "$report_txt" 2>/dev/null || true

  if [[ -x "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" && -x "$FLAMEGRAPH_DIR/flamegraph.pl" ]]; then
    echo "=== Generating FlameGraph SVG ($label) ==="
    
    if perf script -i "$perf_data" 2>/dev/null \
      | "$FLAMEGRAPH_DIR/stackcollapse-perf.pl" \
      | "$FLAMEGRAPH_DIR/flamegraph.pl" --title "raytrace $label" > "$svg_out"; then
      
      if [[ -s "$svg_out" ]]; then
        echo "SUCCESS: Saved FlameGraph to $svg_out"
      else
        echo "ERROR: SVG output $svg_out is empty." >&2
        rm -f "$svg_out"
      fi
    fi
  fi

  # Clean up perf data
  rm -f "$perf_data"
}

# ------------------------------------------------------------------------------
# 5. Optional Perf & Flamegraph Profiling (RUN_PERF=1)
# ------------------------------------------------------------------------------
if [[ "$RUN_PERF" == "1" ]]; then
  if ! command -v perf >/dev/null 2>&1; then
    echo "WARN: Linux perf tool not found; skipping profiling stage" >&2
  else
    ensure_flamegraph || true

    # Course requirements specify python3-dbg for symbol resolution
    if ! command -v python3-dbg >/dev/null 2>&1; then
      echo "ERROR: python3-dbg not found. Profiling requires python3-dbg for symbol resolution." >&2
      exit 1
    fi

    if [[ ! -d "$VENV_DBG" ]]; then
      echo "=== Creating python3-dbg virtual environment ($VENV_DBG) ==="
      python3-dbg -m venv "$VENV_DBG" || {
        echo "WARN: python3-dbg venv creation failed; falling back to python3-dbg binary directly" >&2
      }
    fi

    if [[ -x "$VENV_DBG/bin/pip" ]]; then
      PYTHONWARNINGS="ignore" "$VENV_DBG/bin/pip" install -q --upgrade pip
      PYTHONWARNINGS="ignore" "$VENV_DBG/bin/pip" install -q pyperf
      DBG_PY="$VENV_DBG/bin/python"
    else
      DBG_PY="python3-dbg"
    fi

    # Profile Original Baseline
    record_and_report "original baseline" "$DBG_PY" \
      "$RAYTRACE/run_benchmark_original.py" \
      "$RESULTS/raytrace_original.perf.data" \
      "$RESULTS/raytrace_original_perf_report.txt" \
      "$RESULTS/raytrace_baseline.svg"

    # Profile Refactored Code
    record_and_report "refactored optimized" "$DBG_PY" \
      "$RAYTRACE/run_benchmark_optimized.py" \
      "$RESULTS/raytrace_optimized.perf.data" \
      "$RESULTS/raytrace_optimized_perf_report.txt" \
      "$RESULTS/raytrace_optimized.svg"
  fi
fi

echo "Done. All benchmarks and profiles saved to $RESULTS"
