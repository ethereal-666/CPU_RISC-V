`timescale 1ns / 1ps

module Branch_Predictor (
    input  wire         clk_i,
    input  wire         rst_i,

    input  wire [31:0]  fetch_pc_i,
    output wire         pred_taken_o,
    output wire [31:0]  pred_target_o,

    input  wire         resolve_en_i,
    input  wire         is_branch_i,
    input  wire         is_jump_i,
    input  wire [31:0]  resolve_pc_i,
    input  wire         resolved_pred_taken_i,
    input  wire         actual_taken_i,
    input  wire [31:0]  actual_target_i,
    input  wire [31:0]  actual_next_pc_i,

    output wire         redirect_o,
    output wire [31:0]  redirect_pc_o
);

    reg  [15:0] bht_valid;
    reg  [25:0] bht_tag     [0:15];
    reg  [31:0] bht_target  [0:15];
    reg  [ 1:0] bht_counter [0:15];

    wire [3:0] read_index  = fetch_pc_i[5:2];
    wire [3:0] write_index = resolve_pc_i[5:2];
    wire       read_hit    = bht_valid[read_index] &&
                             (bht_tag[read_index] == fetch_pc_i[31:6]);
    wire       write_hit   = bht_valid[write_index] &&
                             (bht_tag[write_index] == resolve_pc_i[31:6]);
    wire       update_en   = resolve_en_i && is_branch_i;

    assign pred_taken_o  = read_hit && bht_counter[read_index][1];
    assign pred_target_o = bht_target[read_index];
    assign redirect_o = resolve_en_i &&
                        ((is_branch_i &&
                          (actual_taken_i != resolved_pred_taken_i)) ||
                         is_jump_i);
    assign redirect_pc_o = actual_next_pc_i;

    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i)
            bht_valid <= 16'h0;
        else if (update_en)
            bht_valid[write_index] <= 1'b1;
    end

    always @(posedge clk_i) begin
        if (update_en) begin
            bht_tag[write_index]    <= resolve_pc_i[31:6];
            bht_target[write_index] <= actual_target_i;
        end
    end

    // 新分支从强不跳转开始，连续两次跳转后改变预测。
    always @(posedge clk_i) begin
        if (update_en) begin
            if (!write_hit)
                bht_counter[write_index] <= actual_taken_i ? 2'b01 : 2'b00;
            else if (actual_taken_i)
                bht_counter[write_index] <=
                    (bht_counter[write_index] == 2'b11) ?
                     2'b11 : bht_counter[write_index] + 2'b01;
            else
                bht_counter[write_index] <=
                    (bht_counter[write_index] == 2'b00) ?
                     2'b00 : bht_counter[write_index] - 2'b01;
        end
    end

endmodule
