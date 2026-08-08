`timescale 1ns / 1ps

`include "defines.vh"

module ALU (
    input  wire         rst,
    input  wire         clk,
    input  wire [ 4:0]  op,
    input  wire [31:0]  a,
    input  wire [31:0]  b,
    input  wire         valid,
    input  wire         enable,
    input  wire         is_mul_div,

    output reg  [31:0]  c,
    output reg          br,
    output wire         stall
);

    wire        mul_flag, mulu_flag;
    wire [63:0] mul_res;
    wire [65:0] mulu_res;
    wire        mul_busy, mulu_busy;
    wire        div_flag, divu_flag;
    wire [31:0] div_quo, div_rem;
    wire [32:0] divu_quo, divu_rem;
    wire        div_busy, divu_busy;
    reg  [ 4:0] op_r;
    reg         operation_started;  // 防止流水线暂停时重复启动乘除运算

    wire unit_busy = mul_busy | mulu_busy | div_busy | divu_busy;
    wire operation_start = valid && enable && is_mul_div &&
                           !operation_started;
    // 启动后暂时屏蔽乘除操作码，由内部运算单元继续执行。
    wire [ 4:0] active_op = operation_start ? op :
                            is_mul_div ? 5'h0 : op;

    always @(*) begin
        case (op_r != 0 ? op_r : active_op)
            `ALU_ADD  : c = a + b;
            `ALU_SUB  : c = a - b;
            `ALU_AND  : c = a & b;
            `ALU_OR   : c = a | b;
            `ALU_XOR  : c = a ^ b;
            `ALU_SLT  : c = $signed(a) < $signed(b);
            `ALU_SLTU : c = a < b;
            `ALU_NOR  : c = ~(a | b);
            `ALU_SLL  : c = a << b[4:0];
            `ALU_SRL  : c = a >> b[4:0];
            `ALU_SRA  : c = $signed(a) >>> b[4:0];
            `ALU_MUL  : c = mul_res[31:0];
            `ALU_MULH : c = mul_res[63:32];
            `ALU_MULHU: c = mulu_res[63:32];
            `ALU_DIV  : c = div_quo;
            `ALU_DIVU : c = divu_quo[31:0];
            `ALU_MOD  : c = div_rem;
            `ALU_MODU : c = divu_rem[31:0];
            default   : c = 32'h0;
        endcase
    end

    always @(*) begin
        case (active_op)
            `ALU_BEQ : br = a == b;
            `ALU_BNE : br = a != b;
            `ALU_BLT : br = $signed(a) <  $signed(b);
            `ALU_BGE : br = $signed(a) >= $signed(b);
            `ALU_BLTU: br = a <  b;
            `ALU_BGEU: br = a >= b;
            default  : br = 1'b0;
        endcase
    end

    assign mul_flag  = (active_op == `ALU_MUL) | (active_op == `ALU_MULH);
    assign mulu_flag = active_op == `ALU_MULHU;
    assign div_flag  = (active_op == `ALU_DIV) | (active_op == `ALU_MOD);
    assign divu_flag = (active_op == `ALU_DIVU) | (active_op == `ALU_MODU);
    assign stall = valid && is_mul_div &&
                   (!operation_started || unit_busy);

    always @(posedge clk or posedge rst) begin
        if (rst)
            op_r <= 5'h0;
        else if (mul_flag | mulu_flag | div_flag | divu_flag)
            op_r <= active_op;
        else if (!unit_busy)
            op_r <= 5'h0;
        else
            op_r <= op_r;
    end

    always @(posedge clk or posedge rst) begin
        if (rst)
            operation_started <= 1'b0;
        else if (!valid || !is_mul_div)
            operation_started <= 1'b0;
        else if (operation_start)
            operation_started <= 1'b1;
        else if (!stall)
            operation_started <= 1'b0;
        else
            operation_started <= operation_started;
    end

    multiplier #(32) U_mul (
        .clk    (clk),
        .rst    (rst),
        .x      (a),
        .y      (b),
        .start  (mul_flag),
        .z      (mul_res),
        .busy   (mul_busy)
    );

    multiplier #(33) U_mulu (
        .clk    (clk),
        .rst    (rst),
        .x      ({1'b0, a}),
        .y      ({1'b0, b}),
        .start  (mulu_flag),
        .z      (mulu_res),
        .busy   (mulu_busy)
    );

    divider #(32, 1'b1) U_div (
        .clk    (clk),
        .rst    (rst),
        .x      (a),
        .y      (b),
        .start  (div_flag),
        .z      (div_quo),
        .r      (div_rem),
        .busy   (div_busy)
    );

    divider #(33, 1'b0) U_divu (
        .clk    (clk),
        .rst    (rst),
        .x      ({1'b0, a}),
        .y      ({1'b0, b}),
        .start  (divu_flag),
        .z      (divu_quo),
        .r      (divu_rem),
        .busy   (divu_busy)
    );

endmodule
