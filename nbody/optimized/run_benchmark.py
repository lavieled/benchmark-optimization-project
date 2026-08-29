"""
Optimized n-body

Numba JIT + SoA float64 arrays. Inner mag is dt / r^3 via 1/sqrt.
Same BODIES constants, dt, default iterations, and energy.
"""

import math

import numpy as np
import pyperf
from numba import njit

__contact__ = "collinwinter@google.com (Collin Winter)"
DEFAULT_ITERATIONS = 20000
DEFAULT_REFERENCE = 'sun'

PI = 3.14159265358979323
SOLAR_MASS = 4 * PI * PI
DAYS_PER_YEAR = 365.24

BODIES = {
    'sun': ([0.0, 0.0, 0.0], [0.0, 0.0, 0.0], SOLAR_MASS),

    'jupiter': ([4.84143144246472090e+00,
                 -1.16032004402742839e+00,
                 -1.03622044471123109e-01],
                [1.66007664274403694e-03 * DAYS_PER_YEAR,
                 7.69901118419740425e-03 * DAYS_PER_YEAR,
                 -6.90460016972063023e-05 * DAYS_PER_YEAR],
                9.54791938424326609e-04 * SOLAR_MASS),

    'saturn': ([8.34336671824457987e+00,
                4.12479856412430479e+00,
                -4.03523417114321381e-01],
               [-2.76742510726862411e-03 * DAYS_PER_YEAR,
                4.99852801234917238e-03 * DAYS_PER_YEAR,
                2.30417297573763929e-05 * DAYS_PER_YEAR],
               2.85885980666130812e-04 * SOLAR_MASS),

    'uranus': ([1.28943695621391310e+01,
                -1.51111514016986312e+01,
                -2.23307578892655734e-01],
               [2.96460137564761618e-03 * DAYS_PER_YEAR,
                2.37847173959480950e-03 * DAYS_PER_YEAR,
                -2.96589568540237556e-05 * DAYS_PER_YEAR],
               4.36624404335156298e-05 * SOLAR_MASS),

    'neptune': ([1.53796971148509165e+01,
                 -2.59193146099879641e+01,
                 1.79258772950371181e-01],
                [2.68067772490389322e-03 * DAYS_PER_YEAR,
                 1.62824170038242295e-03 * DAYS_PER_YEAR,
                 -9.51592254519715870e-05 * DAYS_PER_YEAR],
                5.15138902046611451e-05 * SOLAR_MASS)}

NAMES = ('sun', 'jupiter', 'saturn', 'uranus', 'neptune')
SYSTEM = list(BODIES.values())
N = len(NAMES)
# integer pair list; no nested Python tuples in the hot loop
PAIRS_NP = np.array(
    [(i, j) for i in range(N) for j in range(i + 1, N)],
    dtype=np.int32,
)

# SoA: one array per field, better for Numba than [pos, vel, mass] lists
px = np.zeros(N, dtype=np.float64)
py = np.zeros(N, dtype=np.float64)
pz = np.zeros(N, dtype=np.float64)
vx = np.zeros(N, dtype=np.float64)
vy = np.zeros(N, dtype=np.float64)
vz = np.zeros(N, dtype=np.float64)
mass = np.zeros(N, dtype=np.float64)


def load_initial():
    for i, name in enumerate(NAMES):
        (x, y, z), (vvx, vvy, vvz), m = BODIES[name]
        px[i] = x
        py[i] = y
        pz[i] = z
        vx[i] = vvx
        vy[i] = vvy
        vz[i] = vvz
        mass[i] = m


load_initial()


@njit  # compile to machine code; skip CPython pair-loop overhead
def _advance(dt, n, px, py, pz, vx, vy, vz, mass, pairs):
    n_pairs = pairs.shape[0]
    nbody = px.shape[0]
    for _ in range(n):
        for p in range(n_pairs):
            i = pairs[p, 0]
            j = pairs[p, 1]
            dx = px[i] - px[j]
            dy = py[i] - py[j]
            dz = pz[i] - pz[j]
            inv = 1.0 / math.sqrt(dx * dx + dy * dy + dz * dz)  # 1/r
            mag = dt * inv * inv * inv  # dt/r^3 instead of r2 ** -1.5
            b1m = mass[i] * mag
            b2m = mass[j] * mag
            vx[i] -= dx * b2m
            vy[i] -= dy * b2m
            vz[i] -= dz * b2m
            vx[j] += dx * b1m
            vy[j] += dy * b1m
            vz[j] += dz * b1m
        for k in range(nbody):
            px[k] += dt * vx[k]
            py[k] += dt * vy[k]
            pz[k] += dt * vz[k]


@njit  # same kernel as original report_energy, compiled
def _energy(px, py, pz, vx, vy, vz, mass, pairs):
    e = 0.0
    n_pairs = pairs.shape[0]
    nbody = px.shape[0]
    for p in range(n_pairs):
        i = pairs[p, 0]
        j = pairs[p, 1]
        dx = px[i] - px[j]
        dy = py[i] - py[j]
        dz = pz[i] - pz[j]
        e -= (mass[i] * mass[j]) / math.sqrt(dx * dx + dy * dy + dz * dz)
    for k in range(nbody):
        e += mass[k] * (vx[k] * vx[k] + vy[k] * vy[k] + vz[k] * vz[k]) / 2.0
    return e


def advance(dt, n, bodies=None, pairs=None):
    _advance(dt, n, px, py, pz, vx, vy, vz, mass, PAIRS_NP)


def report_energy(bodies=None, pairs=None, e=0.0):
    return _energy(px, py, pz, vx, vy, vz, mass, PAIRS_NP)


def offset_momentum(ref, bodies=None, px_acc=0.0, py_acc=0.0, pz_acc=0.0):
    load_initial()
    for k in range(N):
        px_acc -= vx[k] * mass[k]
        py_acc -= vy[k] * mass[k]
        pz_acc -= vz[k] * mass[k]
    if ref is BODIES['sun'] or ref == 'sun':
        idx = 0
    else:
        idx = NAMES.index(DEFAULT_REFERENCE)
        for i, name in enumerate(NAMES):
            if ref is BODIES[name]:
                idx = i
                break
    m = mass[idx]
    vx[idx] = px_acc / m
    vy[idx] = py_acc / m
    vz[idx] = pz_acc / m


# compile once here so pyperf does not pay JIT time
def _warmup():
    pxw = np.arange(N, dtype=np.float64)
    pyw = np.arange(N, dtype=np.float64) * 0.5
    pzw = np.arange(N, dtype=np.float64) * 0.25
    vw = np.zeros(N, dtype=np.float64)
    mw = np.ones(N, dtype=np.float64)
    _advance(0.01, 1, pxw, pyw, pzw, vw.copy(), vw.copy(), vw.copy(), mw, PAIRS_NP)
    _energy(pxw, pyw, pzw, vw, vw, vw, mw, PAIRS_NP)


_warmup()


def bench_nbody(loops, reference, iterations):
    offset_momentum(BODIES[reference])

    range_it = range(loops)
    t0 = pyperf.perf_counter()

    for _ in range_it:
        report_energy()
        advance(0.01, iterations)
        report_energy()

    return pyperf.perf_counter() - t0


def add_cmdline_args(cmd, args):
    cmd.extend(("--iterations", str(args.iterations)))


if __name__ == '__main__':
    runner = pyperf.Runner(add_cmdline_args=add_cmdline_args)
    runner.metadata['description'] = "n-body benchmark (optimized, numba)"
    runner.argparser.add_argument("--iterations",
                                  type=int, default=DEFAULT_ITERATIONS,
                                  help="Number of nbody advance() iterations "
                                       "(default: %s)" % DEFAULT_ITERATIONS)
    runner.argparser.add_argument("--reference",
                                  type=str, default=DEFAULT_REFERENCE,
                                  help="nbody reference (default: %s)"
                                       % DEFAULT_REFERENCE)

    args = runner.parse_args()
    runner.bench_time_func('nbody', bench_nbody,
                           args.reference, args.iterations)
