"""Compare total energy of original vs optimized nbody after the same steps."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DT = 0.01
STEPS = 1000
TOL = 1e-9


def load_mod(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    orig = load_mod(ROOT / "run_benchmark.py", "nbody_original")
    opt = load_mod(ROOT / "optimized" / "run_benchmark.py", "nbody_optimized")

    orig.offset_momentum(orig.BODIES["sun"])
    opt.offset_momentum(opt.BODIES["sun"])

    e0_o = orig.report_energy()
    e0_n = opt.report_energy()
    orig.advance(DT, STEPS)
    opt.advance(DT, STEPS)
    e1_o = orig.report_energy()
    e1_n = opt.report_energy()

    d0 = abs(e0_o - e0_n)
    d1 = abs(e1_o - e1_n)
    print(f"energy after offset: original={e0_o:.12g}  optimized={e0_n:.12g}  |d|={d0:.3g}")
    print(f"energy after {STEPS} steps: original={e1_o:.12g}  optimized={e1_n:.12g}  |d|={d1:.3g}")
    if d0 > TOL or d1 > TOL:
        print("FAIL: energy mismatch")
        return 1
    print("OK: energies match within", TOL)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
