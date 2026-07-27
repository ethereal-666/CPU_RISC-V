`timescale 1ns / 1ps

`include "defines.vh"

module NPC (
    input  wire [ 1:0]  op,
    input  wire [31:0]  pc,
    input  wire [31:0]  base,
    input  wire [31:0]  offset,
    input  wire         br,
    
    output reg  [31:0]  npc,
    output reg  [31:0]  target
);

    wire [31:0] pc4;

    assign pc4 = pc + 32'h4;

    always @(*) begin
        case (op)
            `NPC_PC4 : npc = pc4;
            `NPC_JIRL: npc = target;
            `NPC_BRCH: npc = br ? target : pc4;
            `NPC_JMP : npc = target;
            default  : npc = pc4;
        endcase
    end

    // target始终给出跳转方向的目标，供分支预测器更新BTB。
    always @(*) begin
        case (op)
            `NPC_JIRL: target = base + offset;
            `NPC_BRCH,
            `NPC_JMP : target = pc + offset;
            default  : target = pc4;
        endcase
    end
    
endmodule
