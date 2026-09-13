// Pairwise n-body force / velocity-kick accelerator
// Implements mag = dt / r^3 and the two-body velocity updates:
//   v1 -= (dx,dy,dz) * m2 * mag
//   v2 += (dx,dy,dz) * m1 * mag
//
// IEEE-754 binary32 ports. Datapath uses SystemVerilog shortreal so the
// control/FSM and Newton rsqrt schedule are explicit; a tape-out would
// replace each FADD/FMUL with a hard FP unit of similar latency.
//
// Handshake: valid/ready (in and out). One pair per transaction.
// Target clock (FPGA-class): 200 MHz assumed for the report.

`timescale 1ns / 1ps

module fmul32 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        out_valid,
    output logic [31:0] y
);
    shortreal sa, sb, sy;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            y <= 32'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                sa = $bitstoshortreal(a);
                sb = $bitstoshortreal(b);
                sy = sa * sb;
                y <= $shortrealtobits(sy);
            end
        end
    end
endmodule

module fadd32 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        out_valid,
    output logic [31:0] y
);
    shortreal sa, sb, sy;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            y <= 32'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                sa = $bitstoshortreal(a);
                sb = $bitstoshortreal(b);
                sy = sa + sb;
                y <= $shortrealtobits(sy);
            end
        end
    end
endmodule

// One Newton-Raphson step for reciprocal square root:
//   y1 = y0 * (1.5 - 0.5 * r2 * y0 * y0)
module frsqrt_newton32 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [31:0] r2,
    input  logic [31:0] y0,
    output logic        out_valid,
    output logic [31:0] y1
);
    shortreal sr2, sy0, half, one_pt_five, y1s;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            y1 <= 32'b0;
        end else begin
            out_valid <= in_valid;
            if (in_valid) begin
                sr2 = $bitstoshortreal(r2);
                sy0 = $bitstoshortreal(y0);
                half = 0.5;
                one_pt_five = 1.5;
                y1s = sy0 * (one_pt_five - half * sr2 * sy0 * sy0);
                y1 <= $shortrealtobits(y1s);
            end
        end
    end
endmodule

module nbody_force (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        in_valid,
    output logic        in_ready,
    input  logic [31:0] dx,
    input  logic [31:0] dy,
    input  logic [31:0] dz,
    input  logic [31:0] m1,
    input  logic [31:0] m2,
    input  logic [31:0] dt,

    output logic        out_valid,
    input  logic        out_ready,
    output logic [31:0] dv1x,
    output logic [31:0] dv1y,
    output logic [31:0] dv1z,
    output logic [31:0] dv2x,
    output logic [31:0] dv2y,
    output logic [31:0] dv2z
);

    typedef enum logic [3:0] {
        S_IDLE,
        S_R2,
        S_RSQRT0,
        S_NEWTON1,
        S_NEWTON2,
        S_INV3,
        S_MAG,
        S_SCALE,
        S_OUT
    } state_t;

    state_t state, state_n;

    logic [31:0] dx_r, dy_r, dz_r, m1_r, m2_r, dt_r;
    logic [31:0] r2, inv, inv2, inv3, mag, b1m, b2m;
    logic [31:0] y_rsqrt;
    logic        step_valid;

    shortreal sdx, sdy, sdz, sm1, sm2, sdt;
    shortreal sr2, sinv, smag, sb1m, sb2m, sy;

    assign in_ready  = (state == S_IDLE);
    assign out_valid = (state == S_OUT);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            dx_r <= 32'b0;
            dy_r <= 32'b0;
            dz_r <= 32'b0;
            m1_r <= 32'b0;
            m2_r <= 32'b0;
            dt_r <= 32'b0;
            dv1x <= 32'b0;
            dv1y <= 32'b0;
            dv1z <= 32'b0;
            dv2x <= 32'b0;
            dv2y <= 32'b0;
            dv2z <= 32'b0;
            r2 <= 32'b0;
            inv <= 32'b0;
            mag <= 32'b0;
            y_rsqrt <= 32'b0;
        end else begin
            state <= state_n;
            if (state == S_IDLE && in_valid) begin
                dx_r <= dx;
                dy_r <= dy;
                dz_r <= dz;
                m1_r <= m1;
                m2_r <= m2;
                dt_r <= dt;
            end
            if (state == S_R2) begin
                sdx = $bitstoshortreal(dx_r);
                sdy = $bitstoshortreal(dy_r);
                sdz = $bitstoshortreal(dz_r);
                sr2 = sdx * sdx + sdy * sdy + sdz * sdz;
                r2 <= $shortrealtobits(sr2);
            end
            // Magic-constant rsqrt seed (Quake-style), then two Newton steps.
            if (state == S_RSQRT0) begin
                y_rsqrt <= (32'h5F3759DF - (r2 >> 1));
            end
            if (state == S_NEWTON1 || state == S_NEWTON2) begin
                sr2 = $bitstoshortreal(r2);
                sy  = $bitstoshortreal(y_rsqrt);
                sy  = sy * (1.5 - 0.5 * sr2 * sy * sy);
                y_rsqrt <= $shortrealtobits(sy);
                if (state == S_NEWTON2)
                    inv <= $shortrealtobits(sy);
            end
            if (state == S_INV3) begin
                sinv = $bitstoshortreal(inv);
                inv3 <= $shortrealtobits(sinv * sinv * sinv);
            end
            if (state == S_MAG) begin
                sdt  = $bitstoshortreal(dt_r);
                sinv = $bitstoshortreal(inv3);
                mag  <= $shortrealtobits(sdt * sinv);
            end
            if (state == S_SCALE) begin
                sdx = $bitstoshortreal(dx_r);
                sdy = $bitstoshortreal(dy_r);
                sdz = $bitstoshortreal(dz_r);
                sm1 = $bitstoshortreal(m1_r);
                sm2 = $bitstoshortreal(m2_r);
                smag = $bitstoshortreal(mag);
                sb1m = sm1 * smag;
                sb2m = sm2 * smag;
                dv1x <= $shortrealtobits(-(sdx * sb2m));
                dv1y <= $shortrealtobits(-(sdy * sb2m));
                dv1z <= $shortrealtobits(-(sdz * sb2m));
                dv2x <= $shortrealtobits(sdx * sb1m);
                dv2y <= $shortrealtobits(sdy * sb1m);
                dv2z <= $shortrealtobits(sdz * sb1m);
            end
        end
    end

    always_comb begin
        state_n = state;
        unique case (state)
            S_IDLE:    if (in_valid) state_n = S_R2;
            S_R2:      state_n = S_RSQRT0;
            S_RSQRT0:  state_n = S_NEWTON1;
            S_NEWTON1: state_n = S_NEWTON2;
            S_NEWTON2: state_n = S_INV3;
            S_INV3:    state_n = S_MAG;
            S_MAG:     state_n = S_SCALE;
            S_SCALE:   state_n = S_OUT;
            S_OUT:     if (out_ready) state_n = S_IDLE;
            default:   state_n = S_IDLE;
        endcase
    end

endmodule
