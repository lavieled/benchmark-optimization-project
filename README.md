# Benchmark optimization project

Analyze, profile, and optimize two [pyperformance](https://pyperformance.readthedocs.io/benchmarks.html) benchmarks, then propose hardware acceleration.

| Benchmark | Main speedup | Report | Evidence | Hardware |
|-----------|--------------|--------|----------|----------|
| [nbody](nbody/) | **1.49×** (CPython) | [report_nbody.txt](nbody/report_nbody.txt) | [results/](nbody/results/) | [nbody_force.sv](nbody/hw/nbody_force.sv) |
| [raytrace](raytrace/) | 1.50× | [report_raytrace.txt](raytrace/report_raytrace.txt) | [perf/](raytrace/perf/) | — |

Nbody bonus (optional JIT): Numba **57.82×**.

Repo: https://github.com/lavieled/benchmark-optimization-project

## Layout

```
nbody/
  run_benchmark.py              original pyperformance nbody
  optimized_cpython.py          MAIN opt: unrolled locals + sqrt, no JIT
  optimized/run_benchmark.py    BONUS: SoA + Numba
  script_nbody.sh               venv, pyperf, optional perf/flamegraph
  verify_energy.py              same-physics check
  report_nbody.txt
  hw/nbody_force.sv             pairwise 1/r^3 kick
  results/                      pyperf JSON, compare, perf report, SVG

raytrace/
  run_benchmark.py              original pyperformance raytrace
  run_benchmark_optimized_refactor.py
  report_raytrace.txt
  perf/                         pyperf JSON, flame graphs, perf report, perf stat

prompt.txt                      AI prompts used on this project
.gitignore
```

Ignored: `__pycache__/`, `.venv/`, `.venv-dbg/`, `nbody/tools/`, `*.pdf`, `*.zip`, `*.perf.data`, QEMU `*.img`. See `.gitignore`.

## Nbody

Five-body solar system (sun + Jupiter, Saturn, Uranus, Neptune), 20,000 Euler steps.

**Main (CPython only, QEMU 3.10.12):** 3.71 s → **2.49 s (1.49×)**.  
`optimized_cpython.py` — 10 pairs unrolled, coordinates in locals, `mag = dt / (r2 * sqrt(r2))`.  
Files: `nbody_cpython_compare.txt`, `nbody_cpython.json`, `nbody_cpython.svg`, `nbody_cpython_perf_report.txt`.

**Bonus (Numba):** 3.71 s → 64.1 ms (57.82×).  
`optimized/run_benchmark.py` — `nbody_compare.txt`, `nbody_optimized.json`, `nbody_optimized.svg`.

From the repo root, inside the QEMU Ubuntu guest:

```bash
chmod +x nbody/script_nbody.sh
ONLY_CPYTHON=1 RUN_PERF=1 ./nbody/script_nbody.sh
```

That refreshes only the CPython result set and does not overwrite the Numba files.

Full original + Numba + CPython timing (overwrites Numba JSON if you let it):

```bash
ITERS=20000 RUN_PERF=1 ./nbody/script_nbody.sh
```

Time with regular `python3`, not `python3-dbg`. Profiles for original and CPython opt use `python3-dbg`.

```bash
python3 nbody/verify_energy.py
```

## Raytrace

Pure-Python ray tracer (stdlib `math` only). The optimized program inlines vector math, drops defensive type checks, and allocates fewer temporary `Vector`/`Point` objects. Official figures in [report_raytrace.txt](raytrace/report_raytrace.txt): **1.50×** (~33% less time; `perf stat` wall clock 189.83 s → 128.59 s).

Sources, report, and profiles are under `raytrace/` as committed on `main`.
