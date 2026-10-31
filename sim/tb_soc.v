// tb_soc.v - runs the firmware and prints what it writes to OUT_CHAR
`timescale 1ns/1ps
module tb_soc;
    reg clk = 0, resetn = 0;
    always #5 clk = ~clk;

    wire [7:0]  out_char;
    wire        out_char_valid, exit_valid;
    wire [31:0] exit_code;

    soc_top #(.FIRMWARE("build/firmware.hex")) dut (
        .clk(clk), .resetn(resetn),
        .out_char(out_char), .out_char_valid(out_char_valid),
        .exit_code(exit_code), .exit_valid(exit_valid)
    );

    initial begin
        repeat (10) @(posedge clk);
        resetn = 1;
    end

    always @(posedge clk) begin
        if (out_char_valid) $write("%c", out_char);
        if (exit_valid) begin
            if (exit_code == 0) $display("TEST PASSED");
            else                $display("TEST FAILED, exit code %0d", exit_code);
            $finish;
        end
    end

    initial begin
        #20_000_000;
        $display("TEST FAILED: timeout");
        $finish;
    end
endmodule
