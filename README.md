# Benchmark optimization project

Course work: analyze, profile, and optimize two [pyperformance](https://pyperformance.readthedocs.io/benchmarks.html) benchmarks, then propose hardware acceleration.

| Benchmark | Owner | Status |
|-----------|--------|--------|
| [nbody](nbody/) | Lavie | this branch (`lavie_nbody`) |
| [raytrace](raytrace/) | partner | original sources only |

Private repo: https://github.com/lavieled/benchmark-optimization-project

## Layout

```
nbody/                 original + optimized Python nbody, script, report, HW
  run_benchmark.py     unmodified pyperformance nbody
  optimized/           same 5-body physics, faster Python
  script_nbody.sh      venv, run, perf, flamegraph, compare
  report_nbody.txt
  hw/nbody_force.sv
  verify_energy.py     original vs optimized energy check
  results/             JSON / SVG / perf text (not raw *.perf.data)
raytrace/              partner (do not overwrite)
prompt.txt             AI prompts used on this project
.gitignore
```

Ignored: `__pycache__/`, `.venv/`, `*.pdf`, `*.zip`, `*.perf.data`, QEMU `*.img`. See `.gitignore`.

## Nbody: how to run

Inside the **QEMU Ubuntu guest** (not the SSH host), from the repo root:

```bash
chmod +x nbody/script_nbody.sh
./nbody/script_nbody.sh
```

Optional:

```bash
ITERS=20000 WORKERS=2 RUN_PERF=1 ./nbody/script_nbody.sh
```

`RUN_PERF=1` records `perf` with `python3-dbg` and writes `nbody/results/nbody_perf_report.txt` (and a flame graph if `stackcollapse-perf.pl` / `flamegraph.pl` are on `PATH`).

Energy sanity check (needs pyperf, numpy, numba):

```bash
python3 nbody/verify_energy.py
```

## Raytrace

Partner fills `script_raytrace.sh` and `report_raytrace.txt`. Original files are `raytrace/run_benchmark.py` and `raytrace/pyproject.toml`.
