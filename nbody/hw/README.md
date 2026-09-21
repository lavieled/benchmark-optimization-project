# nbody_force accelerator

## Purpose

Computes the pairwise gravity kick from the nbody inner loop in hardware, one
body pair per transaction:

```
mag = dt / r^3
v1 -= dr * m2 * mag
v2 += dr * m1 * mag
```

Source: [nbody_force.sv](nbody_force.sv). More detail in the hardware section of
[report_nbody.txt](../report_nbody.txt).

## Inputs / outputs (IEEE-754 binary32)

| Dir | Name | Width | Meaning |
|-----|------|-------|---------|
| in  | clk, rst_n | 1 | clock, active-low reset |
| in  | in_valid | 1 | input pair is valid |
| out | in_ready | 1 | unit is idle, can accept a pair |
| in  | dx, dy, dz | 32 each | position difference between the two bodies |
| in  | m1, m2 | 32 each | masses |
| in  | dt | 32 | timestep |
| out | out_valid | 1 | results are valid |
| in  | out_ready | 1 | consumer took the results |
| out | dv1x, dv1y, dv1z | 32 each | velocity change of body 1 |
| out | dv2x, dv2y, dv2z | 32 each | velocity change of body 2 |

## How it works

```
                 +---------------------------------------------+
                 |                nbody_force                  |
                 |                                             |
  dx dy dz ----->|  +-------+    +----------+    +---------+   |
  m1 m2 dt       |  | input |    |  r2 =    |    |  rsqrt  |   |
  in_valid ----->|  | regs  |--->| dx²+dy²  |--->|  seed   |   |
  in_ready <-----|  +-------+    |   +dz²    |    +----+----+   |
                 |               +----------+         |        |
                 |                                    v        |
                 |                              +-----------+  |
                 |                              | Newton x2 |  |
                 |                              | refine 1/r|  |
                 |                              +-----+-----+  |
                 |                                    |        |
                 |                                    v        |
                 |  +----------+    +--------+   +---------+   |
  dv1 xyz <------|  | scale by |    | mag =  |   | inv^3 = |   |
  dv2 xyz <------|  | dr, m1,  |<---| dt *   |<--| (1/r)^3 |   |
  out_valid <----|  | m2       |    | inv^3  |   +---------+   |
  out_ready ---->|  +----------+    +--------+                 |
                 |                                             |
                 |   [ FSM: IDLE > R2 > RSQRT > NEWTON x2 >    |
                 |     INV3 > MAG > SCALE > OUT ]              |
                 +---------------------------------------------+
```

```
   CPU (advance loop)                    nbody_force
  +------------------+   dx dy dz     +-----------------+
  |  for each pair:  |   m1 m2 dt     |                 |
  |   send pair  ----+--------------->|  compute kick   |
  |   wait valid     |                |                 |
  |   read dv1, dv2 <+----------------+  8 cycles/pair  |
  +------------------+   dv1  dv2     +-----------------+
     via MMIO registers, or FRSQRT + FMADD custom instructions
```
