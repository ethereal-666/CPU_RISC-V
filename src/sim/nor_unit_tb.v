`timescale 1ns / 1ps

`include "defines.vh"

module nor_unit_tb;
    reg         clk = 1'b0;
    reg         rst = 1'b1;
    reg  [31:15] inst_31_15;
    reg  [31:0] a;
    reg  [31:0] b;

    wire [1:0] npc_op;
    wire [2:0] ext_op;
    wire       r2_sel;
    wire       alua_sel;
    wire       alub_sel;
    wire [4:0] alu_op;
    wire       is_mul_div;
    wire [2:0] ram_r_op;
    wire [3:0] ram_w_op;
    wire       rf_we;
    wire       wr_sel;
    wire [1:0] rf_wsel;
    wire [31:0] result;
    wire       branch_result;
    wire       stall;

    always #5 clk = ~clk;

    Controller controller (
        .inst_31_15(inst_31_15),
        .npc_op(npc_op),
        .ext_op(ext_op),
        .r2_sel(r2_sel),
        .alua_sel(alua_sel),
        .alub_sel(alub_sel),
        .alu_op(alu_op),
        .is_mul_div(is_mul_div),
        .ram_r_op(ram_r_op),
        .ram_w_op(ram_w_op),
        .rf_we(rf_we),
        .wr_sel(wr_sel),
        .rf_wsel(rf_wsel)
    );

    ALU alu (
        .rst(rst),
        .clk(clk),
        .op(alu_op),
        .a(a),
        .b(b),
        .valid(1'b1),
        .enable(1'b1),
        .is_mul_div(is_mul_div),
        .c(result),
        .br(branch_result),
        .stall(stall)
    );

    initial begin
        inst_31_15 = 17'h00028;
        a = 32'h0f0f_00ff;
        b = 32'h3333_5500;
        #10;
        rst = 1'b0;
        #1;

        if (alu_op !== `ALU_NOR) $fatal(1, "NOR decode failed");
        if (rf_we !== 1'b1) $fatal(1, "NOR register write enable failed");
        if (is_mul_div !== 1'b0) $fatal(1, "NOR was classified as mul/div");
        if (result !== ~(a | b)) $fatal(1, "NOR ALU result failed");

        $display("NOR unit test passed: result=%08x", result);
        $finish;
    end
endmodule
