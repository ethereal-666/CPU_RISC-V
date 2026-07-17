`timescale 1ns / 1ps

`include "defines.vh"

module Controller (
    input  wire [31:15] inst_31_15,
    output wire [ 1: 0] npc_op,
    output wire [ 2: 0] ext_op,
    output wire         r2_sel,
    output wire         alua_sel,
    output wire         alub_sel,
    output wire [ 4: 0] alu_op,
    output wire         is_mul,
    output wire         is_div,
    output wire [ 2: 0] ram_r_op,
    output wire [ 3: 0] ram_w_op,
    output wire         rf_we,
    output wire         wr_sel,
    output wire [ 1: 0] rf_wsel
);

    wire LU12I_W   = (inst_31_15[31:25] == 7'h0A    );
    wire PCADDU12I = (inst_31_15[31:25] == 7'h0E    );
    wire ADDI_W    = (inst_31_15[31:22] == 10'h00A  );
    wire SLTI      = (inst_31_15[31:22] == 10'h008  );
    wire SLTUI     = (inst_31_15[31:22] == 10'h009  );
    wire ANDI      = (inst_31_15[31:22] == 10'h00D  );
    wire ORI       = (inst_31_15[31:22] == 10'h00E  );
    wire XORI      = (inst_31_15[31:22] == 10'h00F  );
    wire SLLI_W    = (inst_31_15[31:15] == 17'h00081);
    wire SRLI_W    = (inst_31_15[31:15] == 17'h00089);
    wire SRAI_W    = (inst_31_15[31:15] == 17'h00091);

    wire ADD_W     = (inst_31_15[31:15] == 17'h00020);
    wire SUB_W     = (inst_31_15[31:15] == 17'h00022);
    wire SLT       = (inst_31_15[31:15] == 17'h00024);
    wire SLTU      = (inst_31_15[31:15] == 17'h00025);
    wire AND       = (inst_31_15[31:15] == 17'h00029);
    wire OR        = (inst_31_15[31:15] == 17'h0002A);
    wire XOR       = (inst_31_15[31:15] == 17'h0002B);
    wire SLL_W     = (inst_31_15[31:15] == 17'h0002E);
    wire SRL_W     = (inst_31_15[31:15] == 17'h0002F);
    wire SRA_W     = (inst_31_15[31:15] == 17'h00030);
    wire MUL_W     = (inst_31_15[31:15] == 17'h00038);
    wire MULH_W    = (inst_31_15[31:15] == 17'h00039);
    wire MULH_WU   = (inst_31_15[31:15] == 17'h0003A);
    wire DIV_W     = (inst_31_15[31:15] == 17'h00040);
    wire MOD_W     = (inst_31_15[31:15] == 17'h00041);
    wire DIV_WU    = (inst_31_15[31:15] == 17'h00042);
    wire MOD_WU    = (inst_31_15[31:15] == 17'h00043);

    wire LD_B      = (inst_31_15[31:22] == 10'h0A0  );
    wire LD_H      = (inst_31_15[31:22] == 10'h0A1  );
    wire LD_W      = (inst_31_15[31:22] == 10'h0A2  );
    wire ST_B      = (inst_31_15[31:22] == 10'h0A4  );
    wire ST_H      = (inst_31_15[31:22] == 10'h0A5  );
    wire ST_W      = (inst_31_15[31:22] == 10'h0A6  );
    wire LD_BU     = (inst_31_15[31:22] == 10'h0A8  );
    wire LD_HU     = (inst_31_15[31:22] == 10'h0A9  );

    wire JIRL      = (inst_31_15[31:26] == 6'h13    );
    wire B         = (inst_31_15[31:26] == 6'h14    );
    wire BL        = (inst_31_15[31:26] == 6'h15    );
    wire BEQ       = (inst_31_15[31:26] == 6'h16    );
    wire BNE       = (inst_31_15[31:26] == 6'h17    );
    wire BLT       = (inst_31_15[31:26] == 6'h18    );
    wire BGE       = (inst_31_15[31:26] == 6'h19    );
    wire BLTU      = (inst_31_15[31:26] == 6'h1A    );
    wire BGEU      = (inst_31_15[31:26] == 6'h1B    );

    // npc_op
    wire NPC_OP_BRCH = BEQ | BNE | BLT | BGE | BLTU | BGEU;
    wire NPC_OP_JIRL = JIRL;
    wire NPC_OP_JMP  = B | BL;
    wire NPC_OP_PC4  = !NPC_OP_BRCH & !NPC_OP_JIRL & !NPC_OP_JMP;

    // ext_op
    wire EXT_OP_5   = SLLI_W | SRLI_W | SRAI_W;
    wire EXT_OP_12U = ANDI | ORI | XORI;
    wire EXT_OP_12  = ADDI_W | SLTI | SLTUI |
                      LD_B | LD_H | LD_W | LD_BU | LD_HU |
                      ST_B | ST_H | ST_W;
    wire EXT_OP_16  = JIRL | BEQ | BNE | BLT | BGE | BLTU | BGEU;
    wire EXT_OP_20  = LU12I_W | PCADDU12I;
    wire EXT_OP_26  = B | BL;

    // alu_op
    wire ALU_OP_ADD   = ADD_W | ADDI_W | PCADDU12I |
                        LD_B | LD_H | LD_W | LD_BU | LD_HU |
                        ST_B | ST_H | ST_W;
    wire ALU_OP_SUB   = SUB_W;
    wire ALU_OP_AND   = AND | ANDI;
    wire ALU_OP_OR    = OR | ORI;
    wire ALU_OP_XOR   = XOR | XORI;
    wire ALU_OP_SLT   = SLT | SLTI;
    wire ALU_OP_SLTU  = SLTU | SLTUI;
    wire ALU_OP_SLL   = SLL_W | SLLI_W;
    wire ALU_OP_SRL   = SRL_W | SRLI_W;
    wire ALU_OP_SRA   = SRA_W | SRAI_W;
    wire ALU_OP_EQ    = BEQ;
    wire ALU_OP_NE    = BNE;
    wire ALU_OP_LT    = BLT;
    wire ALU_OP_GE    = BGE;
    wire ALU_OP_LTU   = BLTU;
    wire ALU_OP_GEU   = BGEU;
    wire ALU_OP_MUL   = MUL_W;
    wire ALU_OP_MULH  = MULH_W;
    wire ALU_OP_MULHU = MULH_WU;
    wire ALU_OP_DIV   = DIV_W;
    wire ALU_OP_DIVU  = DIV_WU;
    wire ALU_OP_MOD   = MOD_W;
    wire ALU_OP_MODU  = MOD_WU;

    // r2_sel
    wire R2_SEL_RD = ST_B | ST_H | ST_W |
                     BEQ | BNE | BLT | BGE | BLTU | BGEU;

    // alua_sel
    wire ALU_A_SEL_PC = PCADDU12I;

    // alub_sel
    wire ALU_B_SEL_EXT = SLLI_W | SRLI_W | SRAI_W |
                         ADDI_W | SLTI | SLTUI | ANDI | ORI | XORI |
                         PCADDU12I |
                         LD_B | LD_H | LD_W | LD_BU | LD_HU |
                         ST_B | ST_H | ST_W;

    // ram_r_op
    wire RAM_EXT_B  = LD_B;
    wire RAM_EXT_BU = LD_BU;
    wire RAM_EXT_H  = LD_H;
    wire RAM_EXT_HU = LD_HU;
    wire RAM_EXT_W  = LD_W;

    // ram_w_op
    wire RAM_W_B  = ST_B;
    wire RAM_W_H  = ST_H;
    wire RAM_W_W  = ST_W;

    // rf_we
    wire RF_OP_WE = LU12I_W | PCADDU12I |
                    ADDI_W | SLTI | SLTUI | ANDI | ORI | XORI |
                    ADD_W | SUB_W | SLT | SLTU | AND | OR | XOR |
                    SLL_W | SRL_W | SRA_W | SLLI_W | SRLI_W | SRAI_W |
                    MUL_W | MULH_W | MULH_WU |
                    DIV_W | DIV_WU | MOD_W | MOD_WU |
                    LD_B | LD_H | LD_W | LD_BU | LD_HU |
                    JIRL | BL;

    // wr_sel
    wire WR_SEL_R1 = BL;

    // rf_wsel
    wire WB_OP_ALU = PCADDU12I |
                     ADDI_W | SLTI | SLTUI | ANDI | ORI | XORI |
                     ADD_W | SUB_W | SLT | SLTU | AND | OR | XOR |
                     SLL_W | SRL_W | SRA_W | SLLI_W | SRLI_W | SRAI_W |
                     MUL_W | MULH_W | MULH_WU |
                     DIV_W | DIV_WU | MOD_W | MOD_WU;
    wire WB_OP_RAM = LD_B | LD_H | LD_W | LD_BU | LD_HU;
    wire WB_OP_EXT = LU12I_W;
    wire WB_OP_PC4 = JIRL | BL;

    assign npc_op = {2{NPC_OP_PC4 }} & `NPC_PC4  |
                    {2{NPC_OP_JIRL}} & `NPC_JIRL |
                    {2{NPC_OP_BRCH}} & `NPC_BRCH |
                    {2{NPC_OP_JMP }} & `NPC_JMP;

    assign ext_op = {3{EXT_OP_5  }} & `EXT_5   |
                    {3{EXT_OP_12U}} & `EXT_12U |
                    {3{EXT_OP_12 }} & `EXT_12  |
                    {3{EXT_OP_16 }} & `EXT_16  |
                    {3{EXT_OP_20 }} & `EXT_20  |
                    {3{EXT_OP_26 }} & `EXT_26;

    assign r2_sel = R2_SEL_RD ? `R2_RD : `R2_RK;

    assign alua_sel = ALU_A_SEL_PC ? `ALUA_PC : `ALUA_R1;

    assign alub_sel = ALU_B_SEL_EXT ? `ALUB_EXT : `ALUB_R2;

    assign alu_op = {5{ALU_OP_ADD  }} & `ALU_ADD   |
                    {5{ALU_OP_SUB  }} & `ALU_SUB   |
                    {5{ALU_OP_AND  }} & `ALU_AND   |
                    {5{ALU_OP_OR   }} & `ALU_OR    |
                    {5{ALU_OP_XOR  }} & `ALU_XOR   |
                    {5{ALU_OP_SLT  }} & `ALU_SLT   |
                    {5{ALU_OP_SLTU }} & `ALU_SLTU  |
                    {5{ALU_OP_SLL  }} & `ALU_SLL   |
                    {5{ALU_OP_SRL  }} & `ALU_SRL   |
                    {5{ALU_OP_SRA  }} & `ALU_SRA   |
                    {5{ALU_OP_EQ   }} & `ALU_BEQ   |
                    {5{ALU_OP_NE   }} & `ALU_BNE   |
                    {5{ALU_OP_LT   }} & `ALU_BLT   |
                    {5{ALU_OP_GE   }} & `ALU_BGE   |
                    {5{ALU_OP_LTU  }} & `ALU_BLTU  |
                    {5{ALU_OP_GEU  }} & `ALU_BGEU  |
                    {5{ALU_OP_MUL  }} & `ALU_MUL   |
                    {5{ALU_OP_MULH }} & `ALU_MULH  |
                    {5{ALU_OP_MULHU}} & `ALU_MULHU |
                    {5{ALU_OP_DIV  }} & `ALU_DIV   |
                    {5{ALU_OP_DIVU }} & `ALU_DIVU  |
                    {5{ALU_OP_MOD  }} & `ALU_MOD   |
                    {5{ALU_OP_MODU }} & `ALU_MODU;

    assign is_mul = MUL_W | MULH_W | MULH_WU;
    assign is_div = DIV_W | DIV_WU | MOD_W | MOD_WU;

    assign ram_r_op = {3{RAM_EXT_B }} & `RAM_EXT_B  |
                      {3{RAM_EXT_BU}} & `RAM_EXT_BU |
                      {3{RAM_EXT_H }} & `RAM_EXT_H  |
                      {3{RAM_EXT_HU}} & `RAM_EXT_HU |
                      {3{RAM_EXT_W }} & `RAM_EXT_W;

    assign ram_w_op = {4{RAM_W_B}} & `RAM_WE_B |
                      {4{RAM_W_H}} & `RAM_WE_H |
                      {4{RAM_W_W}} & `RAM_WE_W;

    assign rf_we = RF_OP_WE;

    assign wr_sel = WR_SEL_R1 ? `WR_Rr1 : `WR_RD;

    assign rf_wsel = {2{WB_OP_ALU}} & `WB_ALU |
                     {2{WB_OP_RAM}} & `WB_RAM |
                     {2{WB_OP_EXT}} & `WB_EXT |
                     {2{WB_OP_PC4}} & `WB_PC4;

endmodule
