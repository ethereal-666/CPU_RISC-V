`timescale 1ns / 1ps

`include "defines.vh"

module Hazard_Control (
    input  wire         if_id_valid_i,
    input  wire [ 4:0]  id_rR1_i,
    input  wire [ 4:0]  id_rR2_i,

    input  wire         id_ex_valid_i,
    input  wire [ 4:0]  id_ex_wR_i,
    input  wire         id_ex_is_load_i,

    input  wire [ 4:0]  ex_rR1_i,
    input  wire [ 4:0]  ex_rR2_i,
    input  wire         ex_mem_valid_i,
    input  wire         ex_mem_rf_we_i,
    input  wire [ 1:0]  ex_mem_rf_wsel_i,
    input  wire [ 4:0]  ex_mem_wR_i,
    input  wire         mem_wb_we_i,
    input  wire [ 4:0]  mem_wb_wR_i,

    input  wire         mem_stall_i,
    input  wire         mul_div_stall_i,
    input  wire         redirect_i,

    output wire         front_stall_o,
    output wire         if_id_flush_o,
    output wire         if_id_hold_o,
    output wire         id_ex_flush_o,
    output wire         id_ex_hold_o,
    output wire         ex_mem_hold_o,
    output wire         ex_mem_bubble_o,
    output reg  [ 1:0]  forward1_o,
    output reg  [ 1:0]  forward2_o
);

    // load数据在MEM阶段返回，紧随其后的相关指令需要暂停一拍。
    wire load_use_stall = if_id_valid_i && id_ex_valid_i &&
                          id_ex_is_load_i && (id_ex_wR_i != 5'h0) &&
                          ((id_ex_wR_i == id_rR1_i) ||
                           (id_ex_wR_i == id_rR2_i));
    wire pipeline_hold = mem_stall_i || mul_div_stall_i;
    // load结果此时尚不可用，不能从EX/MEM级前递。
    wire ex_mem_can_forward = ex_mem_valid_i && ex_mem_rf_we_i &&
                              (ex_mem_rf_wsel_i != `WB_RAM) &&
                              (ex_mem_wR_i != 5'h0);

    assign front_stall_o  = pipeline_hold || load_use_stall;
    assign if_id_flush_o  = redirect_i;
    assign if_id_hold_o   = front_stall_o && !redirect_i;
    assign id_ex_flush_o  = redirect_i || (!pipeline_hold && load_use_stall);
    assign id_ex_hold_o   = pipeline_hold && !redirect_i;
    assign ex_mem_hold_o  = mem_stall_i;
    assign ex_mem_bubble_o = !mem_stall_i && mul_div_stall_i;

    // 数据较新时优先选择EX/MEM级，其次选择MEM/WB级。
    always @(*) begin
        if (ex_mem_can_forward && (ex_mem_wR_i == ex_rR1_i))
            forward1_o = `FWD_MEM;
        else if (mem_wb_we_i && (mem_wb_wR_i != 5'h0) &&
                 (mem_wb_wR_i == ex_rR1_i))
            forward1_o = `FWD_WB;
        else
            forward1_o = `FWD_REG;
    end

    always @(*) begin
        if (ex_mem_can_forward && (ex_mem_wR_i == ex_rR2_i))
            forward2_o = `FWD_MEM;
        else if (mem_wb_we_i && (mem_wb_wR_i != 5'h0) &&
                 (mem_wb_wR_i == ex_rR2_i))
            forward2_o = `FWD_WB;
        else
            forward2_o = `FWD_REG;
    end

endmodule
