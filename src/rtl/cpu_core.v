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

    wire [31:0] pc;

    /************************ Pipeline registers ************************/
    reg         if_req_valid;
    reg  [31:0] if_req_pc;
    reg  [31:0] if_req_pred_pc;

    reg         if_id_valid;
    reg  [31:0] if_id_inst;
    reg  [31:0] if_id_pc;
    reg  [31:0] if_id_pred_pc;

    reg         id_ex_valid;
    reg  [31:0] id_ex_pc;
    reg  [31:0] id_ex_pc4;
    reg  [31:0] id_ex_pred_pc;
    reg  [31:0] id_ex_ext;
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
    reg         id_ex_is_mul;
    reg         id_ex_is_div;

    reg         ex_mem_valid;
    reg  [31:0] ex_mem_pc;
    reg  [31:0] ex_mem_pc4;
    reg  [31:0] ex_mem_alu_c;
    reg  [31:0] ex_mem_rd2;
    reg  [31:0] ex_mem_ext;
    reg  [ 4:0] ex_mem_wR;
    reg  [ 2:0] ex_mem_ram_r_op;
    reg  [ 3:0] ex_mem_ram_w_op;
    reg         ex_mem_rf_we;
    reg  [ 1:0] ex_mem_rf_wsel;

    reg         mem_wb_valid;
    reg  [31:0] mem_wb_pc;
    reg  [31:0] mem_wb_pc4;
    reg  [31:0] mem_wb_alu_c;
    reg  [31:0] mem_wb_load_data;
    reg  [31:0] mem_wb_ext;
    reg  [ 4:0] mem_wb_wR;
    reg         mem_wb_rf_we;
    reg  [ 1:0] mem_wb_rf_wsel;

    /***************************** WB *****************************/
    reg [31:0] mem_wb_wdata;

    always @(*) begin
        case (mem_wb_rf_wsel)
            `WB_ALU : mem_wb_wdata = mem_wb_alu_c;
            `WB_RAM : mem_wb_wdata = mem_wb_load_data;
            `WB_EXT : mem_wb_wdata = mem_wb_ext;
            `WB_PC4 : mem_wb_wdata = mem_wb_pc4;
            default : mem_wb_wdata = 32'h0;
        endcase
    end

    wire mem_wb_write_enable = mem_wb_valid && mem_wb_rf_we;

    /***************************** ID *****************************/
    wire [ 1:0] npc_op;
    wire [ 2:0] ext_op;
    wire        r2_sel;
    wire        alua_sel;
    wire        alub_sel;
    wire [ 4:0] alu_op;
    wire        is_mul;
    wire        is_div;
    wire [ 2:0] ram_r_op;
    wire [ 3:0] ram_w_op;
    wire        rf_we;
    wire        wr_sel;
    wire [ 1:0] rf_wsel;

    Controller U_CU (
        .inst_31_15 (if_id_inst[31:15]),
        .npc_op     (npc_op),
        .ext_op     (ext_op),
        .r2_sel     (r2_sel),
        .alua_sel   (alua_sel),
        .alub_sel   (alub_sel),
        .alu_op     (alu_op),
        .is_mul     (is_mul),
        .is_div     (is_div),
        .ram_r_op   (ram_r_op),
        .ram_w_op   (ram_w_op),
        .rf_we      (rf_we),
        .wr_sel     (wr_sel),
        .rf_wsel    (rf_wsel)
    );

    wire [31:0] ext;

    EXT U_EXT (
        .op  (ext_op),
        .imm (if_id_inst[25:0]),
        .ext (ext)
    );

    wire [ 4:0] rR1_id = if_id_inst[9:5];
    wire [ 4:0] rR2_id = r2_sel ? if_id_inst[14:10] : if_id_inst[4:0];
    wire [ 4:0] wR_id  = wr_sel ? if_id_inst[4:0] : 5'h1;
    wire [31:0] rf_rd1;
    wire [31:0] rf_rd2;

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

    // The RF write and ID read happen on the same edge, so bypass WB here.
    wire [31:0] id_rd1 = (mem_wb_write_enable && (mem_wb_wR != 5'h0) &&
                          (mem_wb_wR == rR1_id)) ? mem_wb_wdata : rf_rd1;
    wire [31:0] id_rd2 = (mem_wb_write_enable && (mem_wb_wR != 5'h0) &&
                          (mem_wb_wR == rR2_id)) ? mem_wb_wdata : rf_rd2;

    /***************************** MEM *****************************/
    wire ex_mem_is_load  = ex_mem_ram_r_op != `RAM_EXT_N;
    wire ex_mem_is_store = ex_mem_ram_w_op != `RAM_WE_N;
    wire ex_mem_is_mem   = ex_mem_is_load || ex_mem_is_store;
    reg  mem_req_sent;

    wire mem_response = ex_mem_is_load  ? daccess_rvalid :
                        ex_mem_is_store ? daccess_wresp  : 1'b1;
    wire mem_stall = ex_mem_valid && ex_mem_is_mem && !mem_response;

    wire [ 2:0] active_ram_r_op = (ex_mem_valid && !mem_req_sent) ?
                                   ex_mem_ram_r_op : `RAM_EXT_N;
    wire [ 3:0] active_ram_w_op = (ex_mem_valid && !mem_req_sent) ?
                                   ex_mem_ram_w_op : `RAM_WE_N;
    wire [ 3:0] da_ren;
    wire [31:0] da_addr;
    wire [ 3:0] da_wen;
    wire [31:0] da_wdata;

    MREQ U_MEM_REQ (
        .ram_addr  (ex_mem_alu_c),
        .ram_rop   (active_ram_r_op),
        .da_ren    (da_ren),
        .da_addr   (da_addr),
        .ram_wop   (active_ram_w_op),
        .ram_wdata (ex_mem_rd2),
        .da_wen    (da_wen),
        .da_wdata  (da_wdata)
    );

    assign daccess_ren   = da_ren;
    assign daccess_addr  = da_addr;
    assign daccess_wen   = da_wen;
    assign daccess_wdata = da_wdata;

    wire [31:0] load_ext;

    MEXT U_MEM_EXT (
        .op        (ex_mem_ram_r_op),
        .din       (daccess_rdata),
        .byte_offs (ex_mem_alu_c[1:0]),
        .ext       (load_ext)
    );

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst)
            mem_req_sent <= 1'b0;
        else if (!ex_mem_valid || !ex_mem_is_mem || mem_response)
            mem_req_sent <= 1'b0;
        else if (!mem_req_sent)
            mem_req_sent <= 1'b1;
        else
            mem_req_sent <= mem_req_sent;
    end

    /***************************** EX *****************************/
    reg [31:0] ex_src1;
    reg [31:0] ex_src2;

    wire ex_mem_can_forward = ex_mem_valid && ex_mem_rf_we &&
                              (ex_mem_rf_wsel != `WB_RAM);
    reg [31:0] ex_mem_forward_data;

    always @(*) begin
        case (ex_mem_rf_wsel)
            `WB_EXT : ex_mem_forward_data = ex_mem_ext;
            `WB_PC4 : ex_mem_forward_data = ex_mem_pc4;
            default : ex_mem_forward_data = ex_mem_alu_c;
        endcase
    end

    always @(*) begin
        if (ex_mem_can_forward && (ex_mem_wR != 5'h0) &&
            (ex_mem_wR == id_ex_rR1))
            ex_src1 = ex_mem_forward_data;
        else if (mem_wb_write_enable && (mem_wb_wR != 5'h0) &&
                 (mem_wb_wR == id_ex_rR1))
            ex_src1 = mem_wb_wdata;
        else
            ex_src1 = id_ex_rd1;
    end

    always @(*) begin
        if (ex_mem_can_forward && (ex_mem_wR != 5'h0) &&
            (ex_mem_wR == id_ex_rR2))
            ex_src2 = ex_mem_forward_data;
        else if (mem_wb_write_enable && (mem_wb_wR != 5'h0) &&
                 (mem_wb_wR == id_ex_rR2))
            ex_src2 = mem_wb_wdata;
        else
            ex_src2 = id_ex_rd2;
    end

    wire [31:0] alu_a = id_ex_alua_sel ? ex_src1 : id_ex_pc;
    wire [31:0] alu_b = id_ex_alub_sel ? ex_src2 : id_ex_ext;
    wire        id_ex_is_mul_div = id_ex_is_mul || id_ex_is_div;
    reg         mul_div_started;
    wire        mul_div_start = id_ex_valid && id_ex_is_mul_div &&
                                !mul_div_started && !mem_stall;
    wire [ 4:0] alu_op_active = mul_div_start ? id_ex_alu_op :
                                  id_ex_is_mul_div ? 5'h0 : id_ex_alu_op;
    wire [31:0] alu_c;
    wire        alu_br;
    wire        mul_div_busy;

    ALU U_ALU (
        .rst  (cpu_rst),
        .clk  (cpu_clk),
        .op   (alu_op_active),
        .a    (alu_a),
        .b    (alu_b),
        .c    (alu_c),
        .br   (alu_br),
        .busy (mul_div_busy)
    );

    wire mul_div_stall = id_ex_valid && id_ex_is_mul_div &&
                         (!mul_div_started || mul_div_busy);
    wire ex_resolve = id_ex_valid && !mem_stall && !mul_div_stall;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst)
            mul_div_started <= 1'b0;
        else if (!id_ex_valid || !id_ex_is_mul_div)
            mul_div_started <= 1'b0;
        else if (mul_div_start)
            mul_div_started <= 1'b1;
        else if (!mul_div_stall)
            mul_div_started <= 1'b0;
        else
            mul_div_started <= mul_div_started;
    end

    wire actual_taken = (id_ex_npc_op == `NPC_BRCH) ? alu_br :
                        (id_ex_npc_op != `NPC_PC4);
    wire [31:0] actual_next_pc;
    wire [31:0] control_target;

    NPC U_NPC_EX (
        .op     (id_ex_npc_op),
        .pc     (id_ex_pc),
        .base   (ex_src1),
        .offset (id_ex_ext),
        .br     (actual_taken),
        .npc    (actual_next_pc),
        .pc4    ()
    );

    NPC U_NPC_TARGET (
        .op     (id_ex_npc_op),
        .pc     (id_ex_pc),
        .base   (ex_src1),
        .offset (id_ex_ext),
        .br     (1'b1),
        .npc    (control_target),
        .pc4    ()
    );

    wire ex_is_control = id_ex_npc_op != `NPC_PC4;
    wire ex_redirect = ex_resolve && ex_is_control &&
                       (actual_next_pc != id_ex_pred_pc);

    /************************ Branch predictor ************************/
    // 16-entry BTB/BHT. A new conditional branch starts at strongly not-taken.
    reg  [15:0] bht_valid;
    reg  [15:0] bht_unconditional;
    reg  [25:0] bht_tag     [0:15];
    reg  [31:0] bht_target  [0:15];
    reg  [ 1:0] bht_counter [0:15];

    wire [ 3:0] bht_read_index = pc[5:2];
    wire [ 3:0] bht_write_index = id_ex_pc[5:2];
    wire bht_hit = bht_valid[bht_read_index] &&
                   (bht_tag[bht_read_index] == pc[31:6]);
    wire bht_predict_taken = bht_hit &&
                             (bht_unconditional[bht_read_index] ||
                              bht_counter[bht_read_index][1]);
    wire [31:0] predicted_fetch_pc = bht_predict_taken ?
                                     bht_target[bht_read_index] : pc + 32'h4;
    wire bht_update_hit = bht_valid[bht_write_index] &&
                          (bht_tag[bht_write_index] == id_ex_pc[31:6]);
    wire predictor_update = ex_resolve && ex_is_control;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            bht_valid         <= 16'h0;
            bht_unconditional <= 16'h0;
        end else if (predictor_update) begin
            bht_valid[bht_write_index]         <= 1'b1;
            bht_unconditional[bht_write_index] <=
                (id_ex_npc_op == `NPC_JMP) || (id_ex_npc_op == `NPC_JIRL);
        end
    end

    always @(posedge cpu_clk) begin
        if (predictor_update) begin
            bht_tag[bht_write_index]    <= id_ex_pc[31:6];
            bht_target[bht_write_index] <= control_target;
        end
    end

    always @(posedge cpu_clk) begin
        if (predictor_update) begin
            if (id_ex_npc_op != `NPC_BRCH)
                bht_counter[bht_write_index] <= 2'b11;
            else if (!bht_update_hit)
                bht_counter[bht_write_index] <= actual_taken ? 2'b01 : 2'b00;
            else if (actual_taken)
                bht_counter[bht_write_index] <=
                    (bht_counter[bht_write_index] == 2'b11) ?
                     2'b11 : bht_counter[bht_write_index] + 2'b01;
            else
                bht_counter[bht_write_index] <=
                    (bht_counter[bht_write_index] == 2'b00) ?
                     2'b00 : bht_counter[bht_write_index] - 2'b01;
        end
    end

    /************************ Hazard control ************************/
    // A load result cannot be forwarded until its memory response arrives.
    wire load_use_stall = if_id_valid && id_ex_valid &&
                          (id_ex_ram_r_op != `RAM_EXT_N) &&
                          (id_ex_wR != 5'h0) &&
                          ((id_ex_wR == rR1_id) || (id_ex_wR == rR2_id));
    wire pipeline_hold = mem_stall || mul_div_stall;
    wire front_stall = pipeline_hold || load_use_stall;

    /***************************** IF *****************************/
    wire replay_fetch = front_stall && ifetch_valid && if_req_valid &&
                        !ex_redirect;
    wire pc_fetch = ex_redirect || ifetch_req || replay_fetch;
    wire [31:0] pc_next = ex_redirect ? actual_next_pc :
                          replay_fetch ? if_req_pc : predicted_fetch_pc;

    PC U_PC (
        .clk   (cpu_clk),
        .rst   (cpu_rst),
        .npc   (pc_next),
        .fetch (pc_fetch),
        .pc    (pc)
    );

    assign ifetch_req  = !cpu_rst && !front_stall && !ex_redirect;
    assign ifetch_addr = pc;

    // Keep request metadata aligned with the one-cycle synchronous ROM response.
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            if_req_valid   <= 1'b0;
            if_req_pc      <= 32'h0;
            if_req_pred_pc <= 32'h0;
        end else if (ifetch_req) begin
            if_req_valid   <= 1'b1;
            if_req_pc      <= pc;
            if_req_pred_pc <= predicted_fetch_pc;
        end else begin
            if_req_valid   <= 1'b0;
            if_req_pc      <= if_req_pc;
            if_req_pred_pc <= if_req_pred_pc;
        end
    end

    /***************************** IF/ID *****************************/
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst || ex_redirect) begin
            if_id_valid   <= 1'b0;
            if_id_inst    <= NOP;
            if_id_pc      <= 32'h0;
            if_id_pred_pc <= 32'h0;
        end else if (!front_stall) begin
            if_id_valid   <= ifetch_valid && if_req_valid;
            if_id_inst    <= (ifetch_valid && if_req_valid) ? ifetch_inst : NOP;
            if_id_pc      <= if_req_pc;
            if_id_pred_pc <= if_req_pred_pc;
        end else begin
            if_id_valid   <= if_id_valid;
            if_id_inst    <= if_id_inst;
            if_id_pc      <= if_id_pc;
            if_id_pred_pc <= if_id_pred_pc;
        end
    end

    /***************************** ID/EX *****************************/
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst || ex_redirect) begin
            id_ex_valid      <= 1'b0;
            id_ex_pc         <= 32'h0;
            id_ex_pc4        <= 32'h0;
            id_ex_pred_pc    <= 32'h0;
            id_ex_ext        <= 32'h0;
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
            id_ex_is_mul     <= 1'b0;
            id_ex_is_div     <= 1'b0;
        end else if (pipeline_hold) begin
            id_ex_valid      <= id_ex_valid;
            id_ex_pc         <= id_ex_pc;
            id_ex_pc4        <= id_ex_pc4;
            id_ex_pred_pc    <= id_ex_pred_pc;
            id_ex_ext        <= id_ex_ext;
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
            id_ex_is_mul     <= id_ex_is_mul;
            id_ex_is_div     <= id_ex_is_div;
        end else if (load_use_stall) begin
            id_ex_valid      <= 1'b0;
            id_ex_pc         <= 32'h0;
            id_ex_pc4        <= 32'h0;
            id_ex_pred_pc    <= 32'h0;
            id_ex_ext        <= 32'h0;
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
            id_ex_is_mul     <= 1'b0;
            id_ex_is_div     <= 1'b0;
        end else begin
            id_ex_valid      <= if_id_valid;
            id_ex_pc         <= if_id_pc;
            id_ex_pc4        <= if_id_pc + 32'h4;
            id_ex_pred_pc    <= if_id_pred_pc;
            id_ex_ext        <= ext;
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
            id_ex_is_mul     <= is_mul;
            id_ex_is_div     <= is_div;
        end
    end

    /***************************** EX/MEM *****************************/
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            ex_mem_valid    <= 1'b0;
            ex_mem_pc       <= 32'h0;
            ex_mem_pc4      <= 32'h0;
            ex_mem_alu_c    <= 32'h0;
            ex_mem_rd2      <= 32'h0;
            ex_mem_ext      <= 32'h0;
            ex_mem_wR       <= 5'h0;
            ex_mem_ram_r_op <= `RAM_EXT_N;
            ex_mem_ram_w_op <= `RAM_WE_N;
            ex_mem_rf_we    <= 1'b0;
            ex_mem_rf_wsel  <= 2'h0;
        end else if (mem_stall) begin
            ex_mem_valid    <= ex_mem_valid;
            ex_mem_pc       <= ex_mem_pc;
            ex_mem_pc4      <= ex_mem_pc4;
            ex_mem_alu_c    <= ex_mem_alu_c;
            ex_mem_rd2      <= ex_mem_rd2;
            ex_mem_ext      <= ex_mem_ext;
            ex_mem_wR       <= ex_mem_wR;
            ex_mem_ram_r_op <= ex_mem_ram_r_op;
            ex_mem_ram_w_op <= ex_mem_ram_w_op;
            ex_mem_rf_we    <= ex_mem_rf_we;
            ex_mem_rf_wsel  <= ex_mem_rf_wsel;
        end else if (mul_div_stall) begin
            ex_mem_valid    <= 1'b0;
            ex_mem_pc       <= 32'h0;
            ex_mem_pc4      <= 32'h0;
            ex_mem_alu_c    <= 32'h0;
            ex_mem_rd2      <= 32'h0;
            ex_mem_ext      <= 32'h0;
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
            ex_mem_ext      <= id_ex_ext;
            ex_mem_wR       <= id_ex_wR;
            ex_mem_ram_r_op <= id_ex_ram_r_op;
            ex_mem_ram_w_op <= id_ex_ram_w_op;
            ex_mem_rf_we    <= id_ex_rf_we;
            ex_mem_rf_wsel  <= id_ex_rf_wsel;
        end
    end

    /***************************** MEM/WB *****************************/
    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            mem_wb_valid     <= 1'b0;
            mem_wb_pc        <= 32'h0;
            mem_wb_pc4       <= 32'h0;
            mem_wb_alu_c     <= 32'h0;
            mem_wb_load_data <= 32'h0;
            mem_wb_ext       <= 32'h0;
            mem_wb_wR        <= 5'h0;
            mem_wb_rf_we     <= 1'b0;
            mem_wb_rf_wsel   <= 2'h0;
        end else if (ex_mem_valid && (!ex_mem_is_mem || mem_response)) begin
            mem_wb_valid     <= 1'b1;
            mem_wb_pc        <= ex_mem_pc;
            mem_wb_pc4       <= ex_mem_pc4;
            mem_wb_alu_c     <= ex_mem_alu_c;
            mem_wb_load_data <= load_ext;
            mem_wb_ext       <= ex_mem_ext;
            mem_wb_wR        <= ex_mem_wR;
            mem_wb_rf_we     <= ex_mem_rf_we;
            mem_wb_rf_wsel   <= ex_mem_rf_wsel;
        end else begin
            mem_wb_valid     <= 1'b0;
            mem_wb_pc        <= 32'h0;
            mem_wb_pc4       <= 32'h0;
            mem_wb_alu_c     <= 32'h0;
            mem_wb_load_data <= 32'h0;
            mem_wb_ext       <= 32'h0;
            mem_wb_wR        <= 5'h0;
            mem_wb_rf_we     <= 1'b0;
            mem_wb_rf_wsel   <= 2'h0;
        end
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
