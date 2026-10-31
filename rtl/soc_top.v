// soc_top.v - PicoRV32 + 64 KiB RAM + mac_accel + output port
//
// 0x0000_0000  RAM
// 0x1000_0000  OUT_CHAR (write a character)
// 0x1000_0004  OUT_EXIT (write exit code, ends simulation)
// 0x2000_0000  mac_accel (regs at +0, scratchpad at +0x1_0000)

`default_nettype none

module soc_top #(
    parameter integer RAM_WORDS = 16384,
    parameter         FIRMWARE  = "firmware.hex"
) (
    input  wire       clk,
    input  wire       resetn,
    output reg  [7:0] out_char,
    output reg        out_char_valid,
    output reg [31:0] exit_code,
    output reg        exit_valid
);
    wire        mem_valid, mem_instr;
    reg         mem_ready;
    wire [31:0] mem_addr, mem_wdata;
    wire [ 3:0] mem_wstrb;
    reg  [31:0] mem_rdata;

    picorv32 #(
        .ENABLE_COUNTERS (1),
        .ENABLE_MUL      (1),   // so software uses mul too
        .ENABLE_DIV      (1),   // putd() needs div
        .PROGADDR_RESET  (32'h0000_0000),
        .STACKADDR       (4 * RAM_WORDS)
    ) cpu (
        .clk       (clk),
        .resetn    (resetn),
        .mem_valid (mem_valid),
        .mem_instr (mem_instr),
        .mem_ready (mem_ready),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_wstrb (mem_wstrb),
        .mem_rdata (mem_rdata),
        .mem_la_read (), .mem_la_write (), .mem_la_addr (),
        .mem_la_wdata (), .mem_la_wstrb (),
        .pcpi_valid (), .pcpi_insn (), .pcpi_rs1 (), .pcpi_rs2 (),
        .pcpi_wr (1'b0), .pcpi_rd (32'd0), .pcpi_wait (1'b0), .pcpi_ready (1'b0),
        .irq (32'd0), .eoi (),
        .trace_valid (), .trace_data ()
    );

    wire sel_ram   = mem_addr[31:28] == 4'h0;
    wire sel_io    = mem_addr[31:28] == 4'h1;
    wire sel_accel = mem_addr[31:28] == 4'h2;

    // RAM
    reg [31:0] ram [0:RAM_WORDS-1];
    initial $readmemh(FIRMWARE, ram);

    reg        ram_ready;
    reg [31:0] ram_rdata;
    wire [$clog2(RAM_WORDS)-1:0] ram_word = mem_addr[$clog2(RAM_WORDS)+1:2];

    always @(posedge clk) begin
        ram_ready <= 1'b0;
        if (mem_valid && sel_ram && !ram_ready) begin
            if (mem_wstrb[0]) ram[ram_word][ 7: 0] <= mem_wdata[ 7: 0];
            if (mem_wstrb[1]) ram[ram_word][15: 8] <= mem_wdata[15: 8];
            if (mem_wstrb[2]) ram[ram_word][23:16] <= mem_wdata[23:16];
            if (mem_wstrb[3]) ram[ram_word][31:24] <= mem_wdata[31:24];
            ram_rdata <= ram[ram_word];
            ram_ready <= 1'b1;
        end
    end

    // output port
    reg io_ready;
    always @(posedge clk) begin
        io_ready       <= 1'b0;
        out_char_valid <= 1'b0;
        if (!resetn) begin
            exit_valid <= 1'b0;
            exit_code  <= 32'd0;
        end else if (mem_valid && sel_io && !io_ready) begin
            io_ready <= 1'b1;
            if (|mem_wstrb) begin
                if (mem_addr[2] == 1'b0) begin
                    out_char       <= mem_wdata[7:0];
                    out_char_valid <= 1'b1;
                end else begin
                    exit_code  <= mem_wdata;
                    exit_valid <= 1'b1;
                end
            end
        end
    end

    wire        acc_ready;
    wire [31:0] acc_rdata;

    mac_accel #(.SPAD_WORDS(1024)) accel (
        .clk       (clk),
        .resetn    (resetn),
        .bus_valid (mem_valid && sel_accel),
        .bus_ready (acc_ready),
        .bus_addr  (mem_addr),
        .bus_wdata (mem_wdata),
        .bus_wstrb (mem_wstrb),
        .bus_rdata (acc_rdata)
    );

    // ready/rdata back to CPU
    always @(*) begin
        mem_ready = 1'b0;
        mem_rdata = 32'd0;
        if (sel_ram)   begin mem_ready = ram_ready; mem_rdata = ram_rdata; end
        if (sel_io)    begin mem_ready = io_ready;  mem_rdata = 32'd0;     end
        if (sel_accel) begin mem_ready = acc_ready; mem_rdata = acc_rdata; end
    end

endmodule

`default_nettype wire
