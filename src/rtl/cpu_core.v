`timescale 1ns / 1ps

`include "defines.vh"

module cpu_core(
    input  wire         cpu_rst,
    input  wire         cpu_clk,

    // Instruction Fetch Interface
    output wire         ifetch_req   /* verilator public */ ,
    output wire [31:0]  ifetch_addr  /* verilator public */ ,
    input  wire         ifetch_valid /* verilator public */ ,
    input  wire [31:0]  ifetch_inst,

    // Data Access Interface
    output wire [ 3:0]  daccess_ren,
    output wire [31:0]  daccess_addr,
    input  wire         daccess_rvalid,
    input  wire [31:0]  daccess_rdata,
    output wire [ 3:0]  daccess_wen,
    output wire [31:0]  daccess_wdata,
    input  wire         daccess_wresp
);

    localparam [31:0] NOP = 32'h0340_0000;

    /************************ Pipeline registers ************************/
    // IF/ID
    reg         if_id_valid;
    reg  [31:0] if_id_inst;
    reg  [31:0] if_id_pc;
    reg         if_id_pred_taken;

    // ID/EX
    reg         id_ex_valid;
    reg  [31:0] id_ex_pc;
    reg  [31:0] id_ex_pc4;
    reg         id_ex_pred_taken;
    reg  [31:0] id_ex_sext;
    reg  [31:0] id_ex_rd1;
    reg  [31:0] id_ex_rd2;
    reg  [ 4:0] id_ex_rR1;
    reg  [ 4:0] id_ex_rR2;
    reg  [ 4:0] id_ex_wR;
    reg  [ 4:0] id_ex_alu_op;
    reg         id_ex_alua_sel;
    reg         id_ex_alub_sel;
    reg  [ 2:0] id_ex_ram_r_op;
    reg  [ 3:0] id_ex_ram_w_op;
    reg         id_ex_rf_we;
    reg  [ 1:0] id_ex_rf_wsel;
    reg  [ 1:0] id_ex_npc_op;
    reg         id_ex_is_mul_div;

    // EX/MEM
    reg         ex_mem_valid;
    reg  [31:0] ex_mem_pc;
    reg  [31:0] ex_mem_pc4;
    reg  [31:0] ex_mem_alu_c;
    reg  [31:0] ex_mem_rd2;
    reg  [31:0] ex_mem_sext;
    reg  [ 4:0] ex_mem_wR;
    reg  [ 2:0] ex_mem_ram_r_op;
    reg  [ 3:0] ex_mem_ram_w_op;
    reg         ex_mem_rf_we;
    reg  [ 1:0] ex_mem_rf_wsel;

    // MEM/WB
    reg         mem_wb_valid;
    reg  [31:0] mem_wb_pc;
    reg  [31:0] mem_wb_pc4;
    reg  [31:0] mem_wb_alu_c;
    reg  [31:0] mem_wb_mext;
    reg  [31:0] mem_wb_sext;
    reg  [ 4:0] mem_wb_wR;
    reg         mem_wb_rf_we;
    reg  [ 1:0] mem_wb_rf_wsel;

    /************************ Datapath signals ************************/
    // IF
    wire [31:0] pc;
    wire        predicted_taken;
    wire [31:0] predicted_target;
    wire        if_req_valid;
    wire [31:0] if_req_pc;
    wire        if_req_pred_taken;

    // ID
    wire [ 1:0] npc_op;
    wire [ 2:0] ext_op;
    wire        r2_sel;
    wire        alua_sel;
    wire        alub_sel;
    wire [ 4:0] alu_op;
    wire        is_mul_div;
    wire [ 2:0] ram_r_op;
    wire [ 3:0] ram_w_op;
    wire        rf_we;
    wire        wr_sel;
    wire [ 1:0] rf_wsel;
    wire [31:0] ext;
    wire [ 4:0] rR1_id;
    wire [ 4:0] rR2_id;
    wire [ 4:0] wR_id;
    wire [31:0] rf_rd1;
    wire [31:0] rf_rd2;
    wire [31:0] id_rd1;
    wire [31:0] id_rd2;

    // Pipeline control
    wire front_stall;
    wire if_id_flush;
    wire if_id_hold;
    wire id_ex_flush;
    wire id_ex_hold;
    wire ex_mem_hold;
    wire ex_mem_bubble;

    // EX
    wire [ 1:0] forward1;
    wire [ 1:0] forward2;
    wire [31:0] ex_src1;
    wire [31:0] ex_src2;
    wire [31:0] ex_mem_forward_data;
    wire [31:0] alu_a;
    wire [31:0] alu_b;
    wire [31:0] alu_c;
    wire        alu_br;
    wire        mul_div_stall;
    wire        ex_resolve;
    wire        actual_taken;
    wire [31:0] actual_next_pc;
    wire [31:0] control_target;
    wire        ex_is_branch;
    wire        ex_is_jump;
    wire        ex_redirect;
    wire [31:0] redirect_pc;

    // MEM
    wire        mem_stall;
    wire [31:0] load_ext;

    // WB
    reg  [31:0] mem_wb_wdata;
    wire        mem_wb_write_enable;

    /***************************** IF *****************************/
    IF_Control U_if_control (
        .clk_i            (cpu_clk),
        .rst_i            (cpu_rst),
        .front_stall_i    (front_stall),
        .redirect_i       (ex_redirect),
        .redirect_pc_i    (redirect_pc),
        .pred_taken_i     (predicted_taken),
        .pred_target_i    (predicted_target),
        .ifetch_valid_i   (ifetch_valid),
        .ifetch_req_o     (ifetch_req),
        .ifetch_addr_o    (ifetch_addr),
        .pc_o             (pc),
        .req_valid_o      (if_req_valid),
        .req_pc_o         (if_req_pc),
        .req_pred_taken_o (if_req_pred_taken)
    );

    Branch_Predictor U_branch_predictor (
        .clk_i           (cpu_clk),
        .rst_i           (cpu_rst),
        .fetch_pc_i      (pc),
        .pred_taken_o    (predicted_taken),
        .pred_target_o   (predicted_target),
        .resolve_en_i          (ex_resolve),
        .is_branch_i           (ex_is_branch),
        .is_jump_i             (ex_is_jump),
        .resolve_pc_i          (id_ex_pc),
        .resolved_pred_taken_i (id_ex_pred_taken),
        .actual_taken_i        (actual_taken),
        .actual_target_i       (control_target),
        .actual_next_pc_i      (actual_next_pc),
        .redirect_o            (ex_redirect),
        .redirect_pc_o         (redirect_pc)
    );

    /***************************** IF/ID *****************************/
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst || if_id_flush) begin
            if_id_valid      <= 1'b0;
            if_id_inst       <= NOP;
            if_id_pc         <= 32'h0;
            if_id_pred_taken <= 1'b0;
        end else if (!if_id_hold) begin
            if_id_valid      <= ifetch_valid && if_req_valid;
            if_id_inst       <= (ifetch_valid && if_req_valid) ? ifetch_inst : NOP;
            if_id_pc         <= if_req_pc;
            if_id_pred_taken <= if_req_pred_taken;
        end else begin
            if_id_valid      <= if_id_valid;
            if_id_inst       <= if_id_inst;
            if_id_pc         <= if_id_pc;
            if_id_pred_taken <= if_id_pred_taken;
        end
    end

    /***************************** ID *****************************/
    Controller U_CU (
        .inst_31_15 (if_id_inst[31:15]),
        .npc_op     (npc_op),
        .ext_op     (ext_op),
        .r2_sel     (r2_sel),
        .alua_sel   (alua_sel),
        .alub_sel   (alub_sel),
        .alu_op     (alu_op),
        .is_mul_div (is_mul_div),
        .ram_r_op   (ram_r_op),
        .ram_w_op   (ram_w_op),
        .rf_we      (rf_we),
        .wr_sel     (wr_sel),
        .rf_wsel    (rf_wsel)
    );

    EXT U_EXT (
        .op  (ext_op),
        .imm (if_id_inst[25:0]),
        .ext (ext)
    );

    assign rR1_id = if_id_inst[9:5];
    assign rR2_id = r2_sel ? if_id_inst[14:10] : if_id_inst[4:0];
    assign wR_id  = wr_sel ? if_id_inst[4:0] : 5'h1;

    RF U_RF (
        .clk (cpu_clk),
        .rR1 (rR1_id),
        .rR2 (rR2_id),
        .rD1 (rf_rd1),
        .rD2 (rf_rd2),
        .we  (mem_wb_write_enable),
        .wR  (mem_wb_wR),
        .wD  (mem_wb_wdata)
    );

    // WB写入与ID读取同沿发生，直接旁路最新数据。
    assign id_rd1 = (mem_wb_write_enable && (mem_wb_wR != 5'h0) &&
                     (mem_wb_wR == rR1_id)) ? mem_wb_wdata : rf_rd1;
    assign id_rd2 = (mem_wb_write_enable && (mem_wb_wR != 5'h0) &&
                     (mem_wb_wR == rR2_id)) ? mem_wb_wdata : rf_rd2;

    /************************ Hazard control ************************/
    Hazard_Control U_hazard_control (
        .if_id_valid_i    (if_id_valid),
        .id_rR1_i         (rR1_id),
        .id_rR2_i         (rR2_id),
        .id_ex_valid_i    (id_ex_valid),
        .id_ex_wR_i       (id_ex_wR),
        .id_ex_is_load_i  (id_ex_ram_r_op != `RAM_EXT_N),
        .ex_rR1_i         (id_ex_rR1),
        .ex_rR2_i         (id_ex_rR2),
        .ex_mem_valid_i   (ex_mem_valid),
        .ex_mem_rf_we_i   (ex_mem_rf_we),
        .ex_mem_rf_wsel_i (ex_mem_rf_wsel),
        .ex_mem_wR_i      (ex_mem_wR),
        .mem_wb_we_i      (mem_wb_write_enable),
        .mem_wb_wR_i      (mem_wb_wR),
        .mem_stall_i      (mem_stall),
        .mul_div_stall_i  (mul_div_stall),
        .redirect_i       (ex_redirect),
        .front_stall_o    (front_stall),
        .if_id_flush_o    (if_id_flush),
        .if_id_hold_o     (if_id_hold),
        .id_ex_flush_o    (id_ex_flush),
        .id_ex_hold_o     (id_ex_hold),
        .ex_mem_hold_o    (ex_mem_hold),
        .ex_mem_bubble_o  (ex_mem_bubble),
        .forward1_o       (forward1),
        .forward2_o       (forward2)
    );

    /***************************** ID/EX *****************************/
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst || id_ex_flush) begin
            id_ex_valid      <= 1'b0;
            id_ex_pc         <= 32'h0;
            id_ex_pc4        <= 32'h0;
            id_ex_pred_taken <= 1'b0;
            id_ex_sext       <= 32'h0;
            id_ex_rd1        <= 32'h0;
            id_ex_rd2        <= 32'h0;
            id_ex_rR1        <= 5'h0;
            id_ex_rR2        <= 5'h0;
            id_ex_wR         <= 5'h0;
            id_ex_alu_op     <= 5'h0;
            id_ex_alua_sel   <= 1'b0;
            id_ex_alub_sel   <= 1'b0;
            id_ex_ram_r_op   <= `RAM_EXT_N;
            id_ex_ram_w_op   <= `RAM_WE_N;
            id_ex_rf_we      <= 1'b0;
            id_ex_rf_wsel    <= 2'h0;
            id_ex_npc_op     <= `NPC_PC4;
            id_ex_is_mul_div <= 1'b0;
        end else if (id_ex_hold) begin
            id_ex_valid      <= id_ex_valid;
            id_ex_pc         <= id_ex_pc;
            id_ex_pc4        <= id_ex_pc4;
            id_ex_pred_taken <= id_ex_pred_taken;
            id_ex_sext       <= id_ex_sext;
            id_ex_rd1        <= id_ex_rd1;
            id_ex_rd2        <= id_ex_rd2;
            id_ex_rR1        <= id_ex_rR1;
            id_ex_rR2        <= id_ex_rR2;
            id_ex_wR         <= id_ex_wR;
            id_ex_alu_op     <= id_ex_alu_op;
            id_ex_alua_sel   <= id_ex_alua_sel;
            id_ex_alub_sel   <= id_ex_alub_sel;
            id_ex_ram_r_op   <= id_ex_ram_r_op;
            id_ex_ram_w_op   <= id_ex_ram_w_op;
            id_ex_rf_we      <= id_ex_rf_we;
            id_ex_rf_wsel    <= id_ex_rf_wsel;
            id_ex_npc_op     <= id_ex_npc_op;
            id_ex_is_mul_div <= id_ex_is_mul_div;
        end else begin
            id_ex_valid      <= if_id_valid;
            id_ex_pc         <= if_id_pc;
            id_ex_pc4        <= if_id_pc + 32'h4;
            id_ex_pred_taken <= if_id_pred_taken;
            id_ex_sext       <= ext;
            id_ex_rd1        <= id_rd1;
            id_ex_rd2        <= id_rd2;
            id_ex_rR1        <= rR1_id;
            id_ex_rR2        <= rR2_id;
            id_ex_wR         <= wR_id;
            id_ex_alu_op     <= alu_op;
            id_ex_alua_sel   <= alua_sel;
            id_ex_alub_sel   <= alub_sel;
            id_ex_ram_r_op   <= ram_r_op;
            id_ex_ram_w_op   <= ram_w_op;
            id_ex_rf_we      <= rf_we;
            id_ex_rf_wsel    <= rf_wsel;
            id_ex_npc_op     <= npc_op;
            id_ex_is_mul_div <= is_mul_div;
        end
    end

    /***************************** EX *****************************/
    // load不能从EX/MEM级前递，其余写回来源在此完成选择。
    assign ex_mem_forward_data = (ex_mem_rf_wsel == `WB_EXT) ?
                                 ex_mem_sext :
                                 (ex_mem_rf_wsel == `WB_PC4) ?
                                 ex_mem_pc4 : ex_mem_alu_c;

    // 前递优先级由冒险控制器统一判断。
    assign ex_src1 = (forward1 == `FWD_MEM) ? ex_mem_forward_data :
                     (forward1 == `FWD_WB)  ? mem_wb_wdata : id_ex_rd1;
    assign ex_src2 = (forward2 == `FWD_MEM) ? ex_mem_forward_data :
                     (forward2 == `FWD_WB)  ? mem_wb_wdata : id_ex_rd2;

    assign alu_a = id_ex_alua_sel ? ex_src1 : id_ex_pc;
    assign alu_b = id_ex_alub_sel ? ex_src2 : id_ex_sext;

    // 后级停顿解除后，当前控制转移指令才允许提交解析结果。
    assign ex_resolve = id_ex_valid && !mem_stall && !mul_div_stall;

    ALU U_ALU (
        .rst        (cpu_rst),
        .clk        (cpu_clk),
        .op         (id_ex_alu_op),
        .a          (alu_a),
        .b          (alu_b),
        .valid      (id_ex_valid),
        .enable     (!mem_stall),
        .is_mul_div (id_ex_is_mul_div),
        .c          (alu_c),
        .br         (alu_br),
        .stall      (mul_div_stall)
    );

    assign actual_taken = (id_ex_npc_op == `NPC_BRCH) ? alu_br :
                          (id_ex_npc_op != `NPC_PC4);
    assign ex_is_branch = id_ex_npc_op == `NPC_BRCH;
    assign ex_is_jump = (id_ex_npc_op == `NPC_JMP) ||
                        (id_ex_npc_op == `NPC_JIRL);
    NPC U_NPC_EX (
        .op     (id_ex_npc_op),
        .pc     (id_ex_pc),
        .base   (ex_src1),
        .offset (id_ex_sext),
        .br     (actual_taken),
        .npc    (actual_next_pc),
        .target (control_target)
    );

    /***************************** EX/MEM *****************************/
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            ex_mem_valid    <= 1'b0;
            ex_mem_pc       <= 32'h0;
            ex_mem_pc4      <= 32'h0;
            ex_mem_alu_c    <= 32'h0;
            ex_mem_rd2      <= 32'h0;
            ex_mem_sext     <= 32'h0;
            ex_mem_wR       <= 5'h0;
            ex_mem_ram_r_op <= `RAM_EXT_N;
            ex_mem_ram_w_op <= `RAM_WE_N;
            ex_mem_rf_we    <= 1'b0;
            ex_mem_rf_wsel  <= 2'h0;
        end else if (ex_mem_hold) begin
            ex_mem_valid    <= ex_mem_valid;
            ex_mem_pc       <= ex_mem_pc;
            ex_mem_pc4      <= ex_mem_pc4;
            ex_mem_alu_c    <= ex_mem_alu_c;
            ex_mem_rd2      <= ex_mem_rd2;
            ex_mem_sext     <= ex_mem_sext;
            ex_mem_wR       <= ex_mem_wR;
            ex_mem_ram_r_op <= ex_mem_ram_r_op;
            ex_mem_ram_w_op <= ex_mem_ram_w_op;
            ex_mem_rf_we    <= ex_mem_rf_we;
            ex_mem_rf_wsel  <= ex_mem_rf_wsel;
        end else if (ex_mem_bubble) begin
            ex_mem_valid    <= 1'b0;
            ex_mem_pc       <= 32'h0;
            ex_mem_pc4      <= 32'h0;
            ex_mem_alu_c    <= 32'h0;
            ex_mem_rd2      <= 32'h0;
            ex_mem_sext     <= 32'h0;
            ex_mem_wR       <= 5'h0;
            ex_mem_ram_r_op <= `RAM_EXT_N;
            ex_mem_ram_w_op <= `RAM_WE_N;
            ex_mem_rf_we    <= 1'b0;
            ex_mem_rf_wsel  <= 2'h0;
        end else begin
            ex_mem_valid    <= id_ex_valid;
            ex_mem_pc       <= id_ex_pc;
            ex_mem_pc4      <= id_ex_pc4;
            ex_mem_alu_c    <= alu_c;
            ex_mem_rd2      <= ex_src2;
            ex_mem_sext     <= id_ex_sext;
            ex_mem_wR       <= id_ex_wR;
            ex_mem_ram_r_op <= id_ex_ram_r_op;
            ex_mem_ram_w_op <= id_ex_ram_w_op;
            ex_mem_rf_we    <= id_ex_rf_we;
            ex_mem_rf_wsel  <= id_ex_rf_wsel;
        end
    end

    /***************************** MEM *****************************/
    MREQ U_MEM_REQ (
        .clk        (cpu_clk),
        .rst        (cpu_rst),
        .valid      (ex_mem_valid),
        .ram_addr  (ex_mem_alu_c),
        .ram_rop   (ex_mem_ram_r_op),
        .da_ren    (daccess_ren),
        .da_addr   (daccess_addr),
        .ram_wop   (ex_mem_ram_w_op),
        .ram_wdata (ex_mem_rd2),
        .da_wen    (daccess_wen),
        .da_wdata  (daccess_wdata),
        .da_rvalid (daccess_rvalid),
        .da_wresp  (daccess_wresp),
        .stall     (mem_stall)
    );

    MEXT U_MEM_EXT (
        .op        (ex_mem_ram_r_op),
        .din       (daccess_rdata),
        .byte_offs (ex_mem_alu_c[1:0]),
        .ext       (load_ext)
    );

    /***************************** MEM/WB *****************************/
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            mem_wb_valid    <= 1'b0;
            mem_wb_pc       <= 32'h0;
            mem_wb_pc4      <= 32'h0;
            mem_wb_alu_c    <= 32'h0;
            mem_wb_mext     <= 32'h0;
            mem_wb_sext     <= 32'h0;
            mem_wb_wR       <= 5'h0;
            mem_wb_rf_we    <= 1'b0;
            mem_wb_rf_wsel  <= 2'h0;
        // 普通指令可直接进入WB，访存指令需等待响应完成。
        end else if (ex_mem_valid && !mem_stall) begin
            mem_wb_valid    <= 1'b1;
            mem_wb_pc       <= ex_mem_pc;
            mem_wb_pc4      <= ex_mem_pc4;
            mem_wb_alu_c    <= ex_mem_alu_c;
            mem_wb_mext     <= load_ext;
            mem_wb_sext     <= ex_mem_sext;
            mem_wb_wR       <= ex_mem_wR;
            mem_wb_rf_we    <= ex_mem_rf_we;
            mem_wb_rf_wsel  <= ex_mem_rf_wsel;
        end else begin
            mem_wb_valid    <= 1'b0;
            mem_wb_pc       <= 32'h0;
            mem_wb_pc4      <= 32'h0;
            mem_wb_alu_c    <= 32'h0;
            mem_wb_mext     <= 32'h0;
            mem_wb_sext     <= 32'h0;
            mem_wb_wR       <= 5'h0;
            mem_wb_rf_we    <= 1'b0;
            mem_wb_rf_wsel  <= 2'h0;
        end
    end

    /***************************** WB *****************************/
    assign mem_wb_write_enable = mem_wb_valid && mem_wb_rf_we;

    always @(*) begin
        case (mem_wb_rf_wsel)
            `WB_ALU : mem_wb_wdata = mem_wb_alu_c;
            `WB_RAM : mem_wb_wdata = mem_wb_mext;
            `WB_EXT : mem_wb_wdata = mem_wb_sext;
            `WB_PC4 : mem_wb_wdata = mem_wb_pc4;
            default : mem_wb_wdata = 32'h0;
        endcase
    end

    /***************************** Debug *****************************/
`ifdef RUN_TRACE
    wire [31:0] debug_wb_pc    /* verilator public */ ;
    wire        debug_wb_rf_we /* verilator public */ ;
    wire [ 4:0] debug_wb_rf_wR /* verilator public */ ;
    wire [31:0] debug_wb_rf_wD /* verilator public */ ;

    wire [31:0] debug_mem_pc    /* verilator public */ ;
    wire [ 3:0] debug_mem_we    /* verilator public */ ;
    wire [31:0] debug_mem_waddr /* verilator public */ ;
    wire [31:0] debug_mem_wdata /* verilator public */ ;

    assign debug_wb_pc    = mem_wb_pc;
    assign debug_wb_rf_we = mem_wb_write_enable;
    assign debug_wb_rf_wR = mem_wb_wR;
    assign debug_wb_rf_wD = mem_wb_wdata;

    assign debug_mem_pc    = ex_mem_pc;
    assign debug_mem_we    = daccess_wen;
    assign debug_mem_waddr = daccess_addr;
    assign debug_mem_wdata = daccess_wdata;
`endif

endmodule
