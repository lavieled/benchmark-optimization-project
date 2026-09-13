"""
CPython-only n-body (no Numba / NumPy).

Same 5 bodies, dt, step count, and energy as run_benchmark.py.
Stays in the interpreter: unroll the 10 pairs and keep coordinates
in local variables. mag = dt / (r2 * sqrt(r2)) instead of r2 ** -1.5.
"""

from math import sqrt

import pyperf

__contact__ = "collinwinter@google.com (Collin Winter)"
DEFAULT_ITERATIONS = 20000
DEFAULT_REFERENCE = "sun"

PI = 3.14159265358979323
SOLAR_MASS = 4 * PI * PI
DAYS_PER_YEAR = 365.24

BODIES = {
    "sun": ([0.0, 0.0, 0.0], [0.0, 0.0, 0.0], SOLAR_MASS),

    "jupiter": ([4.84143144246472090e+00,
                 -1.16032004402742839e+00,
                 -1.03622044471123109e-01],
                [1.66007664274403694e-03 * DAYS_PER_YEAR,
                 7.69901118419740425e-03 * DAYS_PER_YEAR,
                 -6.90460016972063023e-05 * DAYS_PER_YEAR],
                9.54791938424326609e-04 * SOLAR_MASS),

    "saturn": ([8.34336671824457987e+00,
                4.12479856412430479e+00,
                -4.03523417114321381e-01],
               [-2.76742510726862411e-03 * DAYS_PER_YEAR,
                4.99852801234917238e-03 * DAYS_PER_YEAR,
                2.30417297573763929e-05 * DAYS_PER_YEAR],
               2.85885980666130812e-04 * SOLAR_MASS),

    "uranus": ([1.28943695621391310e+01,
                -1.51111514016986312e+01,
                -2.23307578892655734e-01],
               [2.96460137564761618e-03 * DAYS_PER_YEAR,
                2.37847173959480950e-03 * DAYS_PER_YEAR,
                -2.96589568540237556e-05 * DAYS_PER_YEAR],
               4.36624404335156298e-05 * SOLAR_MASS),

    "neptune": ([1.53796971148509165e+01,
                 -2.59193146099879641e+01,
                 1.79258772950371181e-01],
                [2.68067772490389322e-03 * DAYS_PER_YEAR,
                 1.62824170038242295e-03 * DAYS_PER_YEAR,
                 -9.51592254519715870e-05 * DAYS_PER_YEAR],
                5.15138902046611451e-05 * SOLAR_MASS),
}

NAMES = ("sun", "jupiter", "saturn", "uranus", "neptune")

# live state: [x, y, z, vx, vy, vz, mass] per body
_b = [[0.0] * 7 for _ in range(5)]


def load_initial():
    for i, name in enumerate(NAMES):
        (x, y, z), (vx, vy, vz), m = BODIES[name]
        _b[i][:] = [x, y, z, vx, vy, vz, m]


load_initial()


def advance(dt, n, bodies=None, pairs=None):
    (x0, y0, z0, vx0, vy0, vz0, m0) = _b[0]
    (x1, y1, z1, vx1, vy1, vz1, m1) = _b[1]
    (x2, y2, z2, vx2, vy2, vz2, m2) = _b[2]
    (x3, y3, z3, vx3, vy3, vz3, m3) = _b[3]
    (x4, y4, z4, vx4, vy4, vz4, m4) = _b[4]
    s = sqrt
    for _ in range(n):
        dx = x0 - x1
        dy = y0 - y1
        dz = z0 - z1
        dsq = dx * dx + dy * dy + dz * dz
        mag = dt / (dsq * s(dsq))
        vx0 -= dx * m1 * mag
        vy0 -= dy * m1 * mag
        vz0 -= dz * m1 * mag
        vx1 += dx * m0 * mag
        vy1 += dy * m0 * mag
        vz1 += dz * m0 * mag

        dx = x0 - x2
        dy = y0 - y2
        dz = z0 - z2
        dsq = dx * dx + dy * dy + dz * dz
        mag = dt / (dsq * s(dsq))
        vx0 -= dx * m2 * mag
        vy0 -= dy * m2 * mag
        vz0 -= dz * m2 * mag
        vx2 += dx * m0 * mag
        vy2 += dy * m0 * mag
        vz2 += dz * m0 * mag

        dx = x0 - x3
        dy = y0 - y3
        dz = z0 - z3
        dsq = dx * dx + dy * dy + dz * dz
        mag = dt / (dsq * s(dsq))
        vx0 -= dx * m3 * mag
        vy0 -= dy * m3 * mag
        vz0 -= dz * m3 * mag
        vx3 += dx * m0 * mag
        vy3 += dy * m0 * mag
        vz3 += dz * m0 * mag

        dx = x0 - x4
        dy = y0 - y4
        dz = z0 - z4
        dsq = dx * dx + dy * dy + dz * dz
        mag = dt / (dsq * s(dsq))
        vx0 -= dx * m4 * mag
        vy0 -= dy * m4 * mag
        vz0 -= dz * m4 * mag
        vx4 += dx * m0 * mag
        vy4 += dy * m0 * mag
        vz4 += dz * m0 * mag

        dx = x1 - x2
        dy = y1 - y2
        dz = z1 - z2
        dsq = dx * dx + dy * dy + dz * dz
        mag = dt / (dsq * s(dsq))
        vx1 -= dx * m2 * mag
        vy1 -= dy * m2 * mag
        vz1 -= dz * m2 * mag
        vx2 += dx * m1 * mag
        vy2 += dy * m1 * mag
        vz2 += dz * m1 * mag

        dx = x1 - x3
        dy = y1 - y3
        dz = z1 - z3
        dsq = dx * dx + dy * dy + dz * dz
        mag = dt / (dsq * s(dsq))
        vx1 -= dx * m3 * mag
        vy1 -= dy * m3 * mag
        vz1 -= dz * m3 * mag
        vx3 += dx * m1 * mag
        vy3 += dy * m1 * mag
        vz3 += dz * m1 * mag

        dx = x1 - x4
        dy = y1 - y4
        dz = z1 - z4
        dsq = dx * dx + dy * dy + dz * dz
        mag = dt / (dsq * s(dsq))
        vx1 -= dx * m4 * mag
        vy1 -= dy * m4 * mag
        vz1 -= dz * m4 * mag
        vx4 += dx * m1 * mag
        vy4 += dy * m1 * mag
        vz4 += dz * m1 * mag

        dx = x2 - x3
        dy = y2 - y3
        dz = z2 - z3
        dsq = dx * dx + dy * dy + dz * dz
        mag = dt / (dsq * s(dsq))
        vx2 -= dx * m3 * mag
        vy2 -= dy * m3 * mag
        vz2 -= dz * m3 * mag
        vx3 += dx * m2 * mag
        vy3 += dy * m2 * mag
        vz3 += dz * m2 * mag

        dx = x2 - x4
        dy = y2 - y4
        dz = z2 - z4
        dsq = dx * dx + dy * dy + dz * dz
        mag = dt / (dsq * s(dsq))
        vx2 -= dx * m4 * mag
        vy2 -= dy * m4 * mag
        vz2 -= dz * m4 * mag
        vx4 += dx * m2 * mag
        vy4 += dy * m2 * mag
        vz4 += dz * m2 * mag

        dx = x3 - x4
        dy = y3 - y4
        dz = z3 - z4
        dsq = dx * dx + dy * dy + dz * dz
        mag = dt / (dsq * s(dsq))
        vx3 -= dx * m4 * mag
        vy3 -= dy * m4 * mag
        vz3 -= dz * m4 * mag
        vx4 += dx * m3 * mag
        vy4 += dy * m3 * mag
        vz4 += dz * m3 * mag

        x0 += dt * vx0
        y0 += dt * vy0
        z0 += dt * vz0
        x1 += dt * vx1
        y1 += dt * vy1
        z1 += dt * vz1
        x2 += dt * vx2
        y2 += dt * vy2
        z2 += dt * vz2
        x3 += dt * vx3
        y3 += dt * vy3
        z3 += dt * vz3
        x4 += dt * vx4
        y4 += dt * vy4
        z4 += dt * vz4

    _b[0][:] = [x0, y0, z0, vx0, vy0, vz0, m0]
    _b[1][:] = [x1, y1, z1, vx1, vy1, vz1, m1]
    _b[2][:] = [x2, y2, z2, vx2, vy2, vz2, m2]
    _b[3][:] = [x3, y3, z3, vx3, vy3, vz3, m3]
    _b[4][:] = [x4, y4, z4, vx4, vy4, vz4, m4]


def report_energy(bodies=None, pairs=None, e=0.0):
    for i in range(5):
        xi, yi, zi, vxi, vyi, vzi, mi = _b[i]
        e += mi * (vxi * vxi + vyi * vyi + vzi * vzi) / 2.0
        for j in range(i + 1, 5):
            xj, yj, zj, _, _, _, mj = _b[j]
            dx = xi - xj
            dy = yi - yj
            dz = zi - zj
            e -= (mi * mj) / sqrt(dx * dx + dy * dy + dz * dz)
    return e


def offset_momentum(ref, bodies=None, px=0.0, py=0.0, pz=0.0):
    load_initial()
    for x, y, z, vx, vy, vz, m in _b:
        px -= vx * m
        py -= vy * m
        pz -= vz * m
    idx = 0
    if ref is not BODIES["sun"] and ref != "sun":
        for i, name in enumerate(NAMES):
            if ref is BODIES[name]:
                idx = i
                break
    m = _b[idx][6]
    _b[idx][3] = px / m
    _b[idx][4] = py / m
    _b[idx][5] = pz / m


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


if __name__ == "__main__":
    runner = pyperf.Runner(add_cmdline_args=add_cmdline_args)
    runner.metadata["description"] = "n-body benchmark (optimized, CPython)"
    runner.argparser.add_argument("--iterations",
                                  type=int, default=DEFAULT_ITERATIONS,
                                  help="Number of nbody advance() iterations "
                                       "(default: %s)" % DEFAULT_ITERATIONS)
    runner.argparser.add_argument("--reference",
                                  type=str, default=DEFAULT_REFERENCE,
                                  help="nbody reference (default: %s)"
                                       % DEFAULT_REFERENCE)

    args = runner.parse_args()
    runner.bench_time_func("nbody", bench_nbody,
                           args.reference, args.iterations)
