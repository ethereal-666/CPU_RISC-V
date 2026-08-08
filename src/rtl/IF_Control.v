`timescale 1ns / 1ps

module IF_Control (
    input  wire         clk_i,
    input  wire         rst_i,

    input  wire         front_stall_i,
    input  wire         redirect_i,
    input  wire [31:0]  redirect_pc_i,

    input  wire         pred_taken_i,
    input  wire [31:0]  pred_target_i,

    input  wire         ifetch_valid_i,

    output wire         ifetch_req_o,
    output wire [31:0]  ifetch_addr_o,

    output wire [31:0]  pc_o,
    output reg          req_valid_o,
    output reg  [31:0]  req_pc_o,
    output reg          req_pred_taken_o
);

    reg outstanding_r;
    reg cancelled_r;

    wire response = outstanding_r && ifetch_valid_i;
    wire [31:0] predicted_pc = pred_taken_i ? pred_target_i : pc_o + 32'h4;
    wire replay_fetch = response && front_stall_i && !cancelled_r &&
                        !redirect_i;
    wire pc_write = redirect_i || ifetch_req_o || replay_fetch;
    wire [31:0] next_pc = redirect_i ? redirect_pc_i :
                          replay_fetch ? req_pc_o : predicted_pc;

    // The SoC-side ICache/AXI path has no request-ready signal.  Therefore
    // only one fetch may be outstanding; a request is a one-cycle pulse and
    // its metadata must be retained until ifetch_valid_i returns.
    assign ifetch_req_o  = !rst_i && !front_stall_i && !redirect_i &&
                           !outstanding_r;
    assign ifetch_addr_o = pc_o;

    PC U_PC (
        .clk   (clk_i),
        .rst   (rst_i),
        .npc   (next_pc),
        .fetch (pc_write),
        .pc    (pc_o)
    );

    // 保存请求信息，使其与可变延迟的 Cache/AXI 响应对齐。
    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            outstanding_r        <= 1'b0;
            cancelled_r          <= 1'b0;
            req_valid_o      <= 1'b0;
            req_pc_o         <= 32'h0;
            req_pred_taken_o <= 1'b0;
        end else begin
            if (response) begin
                outstanding_r <= 1'b0;
                cancelled_r   <= 1'b0;
                req_valid_o   <= 1'b0;
            end

            if (redirect_i && outstanding_r && !response) begin
                cancelled_r <= 1'b1;
                req_valid_o <= 1'b0;
            end

            if (ifetch_req_o) begin
                outstanding_r        <= 1'b1;
                cancelled_r          <= 1'b0;
                req_valid_o          <= 1'b1;
                req_pc_o             <= pc_o;
                req_pred_taken_o     <= pred_taken_i;
            end
        end
    end

endmodule
