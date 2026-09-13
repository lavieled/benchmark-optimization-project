"""In-process timing (no pyperf worker). For a local preview; QEMU uses script_nbody.sh."""
from __future__ import annotations

import importlib.util
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ITERS = 20000
LOOPS = 3


def load_mod(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def time_run(mod) -> float:
    mod.offset_momentum(mod.BODIES["sun"])
    t0 = time.perf_counter()
    for _ in range(LOOPS):
        mod.report_energy()
        mod.advance(0.01, ITERS)
        mod.report_energy()
    return time.perf_counter() - t0


def main() -> None:
    orig = load_mod(ROOT / "run_benchmark.py", "nbody_original_t")
    opt = load_mod(ROOT / "optimized" / "run_benchmark.py", "nbody_optimized_t")
    time_run(orig)
    time_run(opt)
    to = time_run(orig)
    tn = time_run(opt)
    pct = (to - tn) / to * 100.0
    print(f"loops={LOOPS} iterations={ITERS}")
    print(f"original:  {to:.4f} s")
    print(f"optimized: {tn:.4f} s")
    print(f"improvement: {pct:.1f}%")
    out = ROOT / "results" / "nbody_compare.txt"
    out.parent.mkdir(exist_ok=True)
    out.write_text(
        f"LOCAL_PREVIEW (in-process, not QEMU pyperf)\n"
        f"loops={LOOPS} iterations={ITERS}\n"
        f"original:  {to:.6f} s\n"
        f"optimized: {tn:.6f} s\n"
        f"improvement: {pct:.1f}%\n",
        encoding="utf-8",
    )
    print("wrote", out)


if __name__ == "__main__":
    main()
