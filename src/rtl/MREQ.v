`timescale 1ns / 1ps

`include "defines.vh"

module MREQ (
    input  wire         clk,
    input  wire         rst,
    input  wire         valid,

    input  wire [31:0]  ram_addr,

    input  wire [ 2:0]  ram_rop,
    output reg  [ 3:0]  da_ren,
    output wire [31:0]  da_addr,

    input  wire [ 3:0]  ram_wop,
    input  wire [31:0]  ram_wdata,
    output reg  [ 3:0]  da_wen,
    output reg  [31:0]  da_wdata,

    input  wire         da_rvalid,
    input  wire         da_wresp,
    output wire         stall
);

    wire [1:0] offset = ram_addr[1:0];
    wire is_load = ram_rop != `RAM_EXT_N;
    wire is_store = ram_wop != `RAM_WE_N;
    wire is_memory = is_load || is_store;
    wire response = is_load ? da_rvalid :
                    is_store ? da_wresp : 1'b1;
    reg request_sent;  // 确保每条访存指令只发出一次请求

    wire [2:0] active_ram_rop = (valid && !request_sent) ?
                                 ram_rop : `RAM_EXT_N;
    wire [3:0] active_ram_wop = (valid && !request_sent) ?
                                 ram_wop : `RAM_WE_N;

    assign da_addr = ram_addr;
    // 请求发出后保持流水线，直到RAM返回响应。
    assign stall = valid && is_memory && !response;

    // 产生写访存请求（da_wen、da_wdata）
    always @(*) begin
        da_wen = 4'h0;

        case (active_ram_wop)
            `RAM_WE_B: begin                            // st.b
                da_wen = active_ram_wop << offset;
            end
            `RAM_WE_H: begin                            // st.h
                if (offset[0] == 1'b0) begin
                    da_wen = active_ram_wop << offset;
                end else
                    da_wen = 4'h0;
            end
            `RAM_WE_W:                                  // st.w
                if (offset == 2'h0) begin
                    da_wen = active_ram_wop;
                end else
                    da_wen = 4'h0;
            default: da_wen = 4'h0;
        endcase
    end

    // 产生读访存请求（da_ren）
    always @(*) begin
        da_wdata = ram_wdata;

        case (active_ram_wop)
            `RAM_WE_B: begin                            // st.b
                da_wdata = ram_wdata << {offset, 3'b000};
            end
            `RAM_WE_H: begin                            // st.h
                if (offset[0] == 1'b0) begin
                    da_wdata = ram_wdata << {offset, 3'b000};
                end else
                    da_wdata = ram_wdata;
            end
            default: da_wdata = ram_wdata;
        endcase
    end

    always @(*) begin
        if (active_ram_rop != `RAM_EXT_N) begin
            case (active_ram_rop)
                `RAM_EXT_B,
                `RAM_EXT_BU: da_ren = 4'b0001 << offset;
                `RAM_EXT_H,
                `RAM_EXT_HU: da_ren = (offset[0] == 1'b0) ?
                                           (4'b0011 << offset) : 4'h0;
                default    : da_ren = (offset == 2'h0) ? 4'hF : 4'h0; // ld.w
            endcase
        end else
            da_ren = 4'h0;
    end

    always @(posedge clk or posedge rst) begin
        if (rst)
            request_sent <= 1'b0;
        else if (!valid || !is_memory || response)
            request_sent <= 1'b0;
        else if (!request_sent)
            request_sent <= 1'b1;
        else
            request_sent <= request_sent;
    end

endmodule
