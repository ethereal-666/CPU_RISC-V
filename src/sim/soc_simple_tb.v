`timescale 1ns / 1ps

`include "defines.vh"

module soc_simple_tb();

    reg         clk  = 1;
    reg         rst  = 1;
    reg  [23:0] switch = 24'h123456;
    wire [23:0] led;
    wire [ 7:0] dig_en;
    wire [ 7:0] dig_seg;
    wire        tx;
    wire        rx = 1;

    integer if_req_count  = 0;
    integer if_rsp_count  = 0;
    integer data_rd_count = 0;
    integer data_wr_count = 0;
    integer axi_ar_count  = 0;
    integer axi_r_count   = 0;
    integer axi_aw_count  = 0;
    integer axi_w_count   = 0;
    integer axi_b_count   = 0;
    integer wb_count      = 0;

    // Release reset between rising clock edges to avoid a race with the
    // CPU's reset-edge detector when RUN_TRACE bypasses the clock wizard.
    initial #595 rst = 0;
    always #5 clk = !clk;

    always @(posedge DUT.sys_clk) begin
        if (!DUT.sys_rst) begin
            if (DUT.U_cpu.U_core.ifetch_req)
                if_req_count <= if_req_count + 1;
            if (DUT.U_cpu.U_core.ifetch_valid)
                if_rsp_count <= if_rsp_count + 1;
            if (|DUT.U_cpu.U_core.daccess_ren)
                data_rd_count <= data_rd_count + 1;
            if (|DUT.U_cpu.U_core.daccess_wen)
                data_wr_count <= data_wr_count + 1;
            if (DUT.cpu_arvalid && DUT.cpu_arready)
                axi_ar_count <= axi_ar_count + 1;
            if (DUT.cpu_rvalid && DUT.cpu_rready)
                axi_r_count <= axi_r_count + 1;
            if (DUT.cpu_awvalid && DUT.cpu_awready)
                axi_aw_count <= axi_aw_count + 1;
            if (DUT.cpu_wvalid && DUT.cpu_wready)
                axi_w_count <= axi_w_count + 1;
            if (DUT.cpu_bvalid && DUT.cpu_bready)
                axi_b_count <= axi_b_count + 1;
            if (DUT.U_cpu.U_core.mem_wb_write_enable)
                wb_count <= wb_count + 1;
        end
    end

    initial begin
        #200000;
        $display(
            "AB_SMOKE if_req=%0d if_rsp=%0d data_rd=%0d data_wr=%0d axi_ar=%0d axi_r=%0d axi_aw=%0d axi_w=%0d axi_b=%0d wb=%0d pc=%08x",
            if_req_count, if_rsp_count, data_rd_count, data_wr_count,
            axi_ar_count, axi_r_count, axi_aw_count, axi_w_count,
            axi_b_count, wb_count, DUT.U_cpu.U_core.pc
        );
        if (if_req_count == 0 || if_rsp_count == 0 || axi_ar_count == 0 || axi_r_count == 0)
            $error("AB_SMOKE_FAIL: instruction AXI read path made no progress");
    end

    always @(*) begin
        if (DUT.U_cpu.U_core.ifetch_valid && DUT.U_cpu.U_core.ifetch_inst == 32'h2b0000) begin
            #20 $display("Test Passed!");
            $finish;
        end
    end

    miniLA_SoC DUT (
        .fpga_clk   (clk),
        .fpga_rst   (rst),
        .sw         (switch),
        .led        (led),
        .dig_en     (dig_en),
        .dig_seg    (dig_seg),
        .rx         (rx),
        .tx         (tx)

`ifdef USE_DDR
        ,// DDR Interface
        .ddr3_addr      (ddr3_addr),
        .ddr3_ba        (ddr3_ba),
        .ddr3_cas_n     (ddr3_cas_n),
        .ddr3_ck_n      (ddr3_ck_n),
        .ddr3_ck_p      (ddr3_ck_p),
        .ddr3_cke       (ddr3_cke),
        .ddr3_ras_n     (ddr3_ras_n),
        .ddr3_we_n      (ddr3_we_n),
        .ddr3_dq        (ddr3_dq),
        .ddr3_dqs_n     (ddr3_dqs_n),
        .ddr3_dqs_p     (ddr3_dqs_p),
        .ddr3_reset_n   (ddr3_reset_n),
        .ddr3_cs_n      (ddr3_cs_n),
        .ddr3_dm        (ddr3_dm),
        .ddr3_odt       (ddr3_odt)
`endif
    );

`ifdef USE_DDR
    wire [14:0] ddr3_addr;
    wire [ 2:0] ddr3_ba;
    wire        ddr3_cas_n;
    wire [ 0:0] ddr3_ck_p;
    wire [ 0:0] ddr3_ck_n;
    wire [ 0:0] ddr3_cke;
    wire        ddr3_ras_n;
    wire        ddr3_we_n;
    wire [15:0] ddr3_dq;
    wire [ 1:0] ddr3_dqs_n;
    wire [ 1:0] ddr3_dqs_p;
    wire        ddr3_reset_n;
    wire [ 0:0] ddr3_cs_n;
    wire [ 1:0] ddr3_dm;
    wire [ 0:0] ddr3_odt;

    ddr3_model u_ddr3 (
        .rst_n          (ddr3_reset_n),
        .ck             (ddr3_ck_p),
        .ck_n           (ddr3_ck_n),
        .cke            (ddr3_cke),
        .cs_n           (ddr3_cs_n),
        .ras_n          (ddr3_ras_n),
        .cas_n          (ddr3_cas_n),
        .we_n           (ddr3_we_n),
        .dm_tdqs        (ddr3_dm),
        .ba             (ddr3_ba),
        .addr           (ddr3_addr),
        .dq             (ddr3_dq),
        .dqs            (ddr3_dqs_p),
        .dqs_n          (ddr3_dqs_n),
        .tdqs_n         (),
        .odt            (ddr3_odt)
    );
`endif

endmodule
