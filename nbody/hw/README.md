# nbody_force accelerator

Pairwise velocity-kick for the pyperformance nbody inner loop
(`mag = dt * r^{-3}` then update both bodies).

See `nbody_force.sv` and `report_nbody.txt` (Hardware Acceleration Proposal).

## Ports (IEEE-754 binary32)

| Dir | Name | Width | Meaning |
|-----|------|-------|---------|
| in  | clk, rst_n | 1 | 200 MHz class clock, active-low reset |
| in  | in_valid / in_ready | 1 | input handshake |
| in  | dx, dy, dz, m1, m2, dt | 32 | pair geometry, masses, timestep |
| out | out_valid / out_ready | 1 | output handshake |
| out | dv1{x,y,z}, dv2{x,y,z} | 32 | velocity increments |

Software: MMIO copy of one pair, or ISA ops FRSQRT + FMADD (not nbody-specific).
