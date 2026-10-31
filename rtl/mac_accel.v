// mac_accel.v
// int8 dot product (MAC) accelerator with its own scratchpad memory.
// CPU copies vectors A and B into the scratchpad, sets LEN/A_OFF/B_OFF and
// starts it. The engine reads A and B from the scratchpad, not over the bus.
//
// Registers (offset from base):
//   0x00 CTRL    W   bit0 start
//   0x04 STATUS  R   bit0 busy, bit1 done, bit2 error
//   0x08 LEN     RW  number of int8 elements
//   0x0C A_OFF   RW  byte offset of A in scratchpad (multiple of 4)
//   0x10 B_OFF   RW  byte offset of B in scratchpad (multiple of 4)
//   0x14 RESULT  R   dot product (signed 32 bit)
//   0x18 CYCLES  R   engine cycles of last run
//   0x1_0000     scratchpad, 4 int8 per word, little endian
//
// 4 elements per clock, so LEN elements take about LEN/4 + 2 cycles.

`default_nettype none

module mac_accel #(
    parameter integer SPAD_WORDS = 1024
) (
    input  wire        clk,
    input  wire        resetn,
    input  wire        bus_valid,
    output reg         bus_ready,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire [31:0] bus_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  wire [31:0] bus_wdata,
    input  wire [ 3:0] bus_wstrb,
    output reg  [31:0] bus_rdata
);
    localparam integer AW = $clog2(SPAD_WORDS);

    reg [31:0] len, a_off, b_off, result, cycles;
    reg        busy, done, error;

    wire       sel_spad = bus_addr[16];
    wire [4:0] reg_idx  = bus_addr[6:2];
    wire [AW-1:0] cpu_addr = bus_addr[AW+1:2];

    wire wr = bus_valid && !bus_ready && (bus_wstrb != 0);
    wire rd = bus_valid && !bus_ready && (bus_wstrb == 0);

    wire start = wr && !sel_spad && reg_idx == 0 && bus_wdata[0] && !busy;

    // scratchpad: CPU port + 2 read ports for the engine
    reg [31:0] spad [0:SPAD_WORDS-1];
    reg [31:0] cpu_q, a_q, b_q;
    reg [AW-1:0] a_addr, b_addr;

    integer i;
    always @(posedge clk) begin
        if (wr && sel_spad && !busy)
            for (i = 0; i < 4; i = i + 1)
                if (bus_wstrb[i]) spad[cpu_addr][8*i +: 8] <= bus_wdata[8*i +: 8];
        cpu_q <= spad[cpu_addr];
        a_q   <= spad[a_addr];
        b_q   <= spad[b_addr];
    end

    // engine
    // cycle n:   a_addr/b_addr go to the scratchpad
    // cycle n+1: a_q/b_q are valid (q_valid), multiply and add to acc
    reg [31:0] words, elems;
    reg        q_valid;
    reg [31:0] acc;

    // products are 16 bit, kept at 18 bit so the sum below does not overflow
    wire signed [17:0] m0 = $signed(a_q[7:0])   * $signed(b_q[7:0]);
    wire signed [17:0] m1 = $signed(a_q[15:8])  * $signed(b_q[15:8]);
    wire signed [17:0] m2 = $signed(a_q[23:16]) * $signed(b_q[23:16]);
    wire signed [17:0] m3 = $signed(a_q[31:24]) * $signed(b_q[31:24]);

    // last word can be partly filled, drop the extra lanes
    wire [2:0] nlanes = (elems >= 4) ? 3'd4 : elems[2:0];

    wire signed [17:0] sum = (nlanes > 0 ? m0 : 18'sd0)
                           + (nlanes > 1 ? m1 : 18'sd0)
                           + (nlanes > 2 ? m2 : 18'sd0)
                           + (nlanes > 3 ? m3 : 18'sd0);

    wire bad_args = (a_off[1:0] != 0) || (b_off[1:0] != 0) || (len > 4*SPAD_WORDS);

    always @(posedge clk) begin
        if (!resetn) begin
            busy    <= 0;
            done    <= 0;
            error   <= 0;
            q_valid <= 0;
            acc     <= 0;
            result  <= 0;
            cycles  <= 0;
            words   <= 0;
            elems   <= 0;
            a_addr  <= 0;
            b_addr  <= 0;
        end else if (start) begin
            done <= 0;
            if (bad_args) begin
                error <= 1;
                done  <= 1;
            end else begin
                error   <= 0;
                busy    <= 1;
                acc     <= 0;
                cycles  <= 0;
                words   <= (len + 3) >> 2;
                elems   <= len;
                a_addr  <= a_off[AW+1:2];
                b_addr  <= b_off[AW+1:2];
                q_valid <= 0;
            end
        end else if (busy) begin
            cycles  <= cycles + 1;
            q_valid <= (words != 0);
            if (words != 0) begin
                words  <= words - 1;
                a_addr <= a_addr + 1;
                b_addr <= b_addr + 1;
            end
            if (q_valid) begin
                acc   <= acc + {{14{sum[17]}}, sum};
                elems <= (elems >= 4) ? elems - 4 : 0;
            end
            if (words == 0 && !q_valid) begin
                busy   <= 0;
                done   <= 1;
                result <= acc;
            end
        end
    end

    // bus side, every access takes one wait state
    reg       rd_wait, rd_spad;
    reg [4:0] rd_idx;

    always @(posedge clk) begin
        if (!resetn) begin
            bus_ready <= 0;
            len       <= 0;
            a_off     <= 0;
            b_off     <= 0;
            rd_wait   <= 0;
        end else begin
            bus_ready <= 0;
            if (wr) begin
                bus_ready <= 1;
                if (!sel_spad && !busy) begin
                    if (reg_idx == 2) len   <= bus_wdata;
                    if (reg_idx == 3) a_off <= bus_wdata;
                    if (reg_idx == 4) b_off <= bus_wdata;
                end
            end else if (rd && !rd_wait) begin
                rd_wait <= 1;
                rd_spad <= sel_spad;
                rd_idx  <= reg_idx;
            end else if (rd_wait) begin
                rd_wait   <= 0;
                bus_ready <= 1;
            end
        end
    end

    always @(*) begin
        if (rd_spad)
            bus_rdata = cpu_q;
        else case (rd_idx)
            1: bus_rdata = {29'd0, error, done, busy};
            2: bus_rdata = len;
            3: bus_rdata = a_off;
            4: bus_rdata = b_off;
            5: bus_rdata = result;
            6: bus_rdata = cycles;
            default: bus_rdata = 0;
        endcase
    end

endmodule

`default_nettype wire
