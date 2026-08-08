`timescale 1ns / 1ps

`include "defines.vh"

module miniLA_SoC(
    input  wire         fpga_clk,
    input  wire         fpga_rst,   // High Active
    input  wire [23:0]  sw,
    output wire [23:0]  led,
    output wire [ 7:0]  dig_en,
    output wire [ 7:0]  dig_seg,    // {CA, CB, ..., CG, DP}
    input  wire         rx,
    output wire         tx
`ifdef USE_DDR
    ,
    output wire [14:0]  ddr3_addr,
    output wire [ 2:0]  ddr3_ba,
    output wire         ddr3_cas_n,
    output wire [ 0:0]  ddr3_ck_n,
    output wire [ 0:0]  ddr3_ck_p,
    output wire [ 0:0]  ddr3_cke,
    output wire         ddr3_ras_n,
    output wire         ddr3_we_n,
    inout  wire [15:0]  ddr3_dq,
    inout  wire [ 1:0]  ddr3_dqs_n,
    inout  wire [ 1:0]  ddr3_dqs_p,
    output wire         ddr3_reset_n,
    output wire [ 0:0]  ddr3_cs_n,
    output wire [ 1:0]  ddr3_dm,
    output wire [ 0:0]  ddr3_odt
`endif
);

`ifdef RUN_TRACE
    wire sys_clk = fpga_clk;
    wire sys_rst = fpga_rst;
`else
    wire pll_clk1;
    wire pll_clk2;
    wire pll_lock;
    wire sys_clk;
    wire reset_async;
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync;
    wire sys_rst;

    // Keep the generated clock ungated.  Assert reset asynchronously when the
    // button is pressed or the PLL is unlocked, then release it synchronously
    // in the clock domain used by the CPU, AXI fabric and peripherals.
    assign sys_clk     = pll_clk1;
    assign reset_async = fpga_rst | !pll_lock;
    assign sys_rst     = reset_sync[1];

    always @(posedge sys_clk or posedge reset_async) begin
        if (reset_async)
            reset_sync <= 2'b11;
        else
            reset_sync <= {reset_sync[0], 1'b0};
    end

    clk_wiz_0 U_clkgen (
        .clk_in1    (fpga_clk),
        .locked     (pll_lock),
        .clk_out1   (pll_clk1),
        .clk_out2   (pll_clk2)
    );
`endif

`ifdef USE_DDR
    wire ddr_init_done;
`endif

    wire cpu_rst;
`ifdef RUN_TRACE
    assign cpu_rst = sys_rst;
`elsif USE_DDR
    // The MIG and AXI fabric must leave reset so DDR calibration can run.
    // Hold only the CPU until the synchronized calibration-done indication.
    assign cpu_rst = sys_rst | !ddr_init_done;
`else
    assign cpu_rst = sys_rst;
`endif

    wire [31:0] cpu_awaddr ;
    wire [ 7:0] cpu_awlen  ;
    wire [ 2:0] cpu_awsize ;
    wire [ 1:0] cpu_awburst;
    wire        cpu_awvalid;
    wire        cpu_awready;
    wire [31:0] cpu_wdata  ;
    wire [ 3:0] cpu_wstrb  ;
    wire        cpu_wlast  ;
    wire        cpu_wvalid ;
    wire        cpu_wready ;
    wire        cpu_bready ;
    wire [ 1:0] cpu_bresp  ;
    wire        cpu_bvalid ;
    wire [31:0] cpu_araddr ;
    wire [ 7:0] cpu_arlen  ;
    wire [ 2:0] cpu_arsize ;
    wire [ 1:0] cpu_arburst;
    wire        cpu_arvalid;
    wire        cpu_arready;
    wire        cpu_rready ;
    wire [31:0] cpu_rdata  ;
    wire [ 1:0] cpu_rresp  ;
    wire        cpu_rlast  ;
    wire        cpu_rvalid ;

    wire [31:0] bram_awaddr ;
    wire [ 7:0] bram_awlen  ;
    wire [ 2:0] bram_awsize ;
    wire [ 1:0] bram_awburst;
    wire        bram_awvalid;
    wire        bram_awready;
    wire [31:0] bram_wdata  ;
    wire [ 3:0] bram_wstrb  ;
    wire        bram_wlast  ;
    wire        bram_wvalid ;
    wire        bram_wready ;
    wire        bram_bready ;
    wire [ 1:0] bram_bresp  ;
    wire        bram_bvalid ;
    wire [31:0] bram_araddr ;
    wire [ 7:0] bram_arlen  ;
    wire [ 2:0] bram_arsize ;
    wire [ 1:0] bram_arburst;
    wire        bram_arvalid;
    wire        bram_arready;
    wire        bram_rready ;
    wire [31:0] bram_rdata  ;
    wire [ 1:0] bram_rresp  ;
    wire        bram_rlast  ;
    wire        bram_rvalid ;

`ifdef RUN_TRACE
    assign bram_awaddr  = cpu_awaddr ;
    assign bram_awlen   = cpu_awlen  ;
    assign bram_awsize  = cpu_awsize ;
    assign bram_awburst = cpu_awburst;
    assign cpu_awready  = bram_awready;
    assign bram_awvalid = cpu_awvalid;
    assign bram_wdata   = cpu_wdata  ;
    assign bram_wstrb   = cpu_wstrb  ;
    assign bram_wlast   = cpu_wlast  ;
    assign bram_wvalid  = cpu_wvalid ;
    assign cpu_wready   = bram_wready;
    assign cpu_bresp    = bram_bresp ;
    assign cpu_bvalid   = bram_bvalid;
    assign bram_bready  = cpu_bready ;
    assign bram_araddr  = cpu_araddr ;
    assign bram_arlen   = cpu_arlen  ;
    assign bram_arsize  = cpu_arsize ;
    assign bram_arburst = cpu_arburst;
    assign bram_arvalid = cpu_arvalid;
    assign cpu_arready  = bram_arready;
    assign bram_rready  = cpu_rready ;
    assign cpu_rdata    = bram_rdata ;
    assign cpu_rresp    = bram_rresp ;
    assign cpu_rlast    = bram_rlast ;
    assign cpu_rvalid   = bram_rvalid;

    assign led     = 24'h0;
    assign dig_en  = 8'hFF;
    assign dig_seg = 8'hFF;
    assign tx      = 1'b1;
`else
    wire [223:0] soc_awaddr;
    wire [ 55:0] soc_awlen;
    wire [ 20:0] soc_awsize;
    wire [ 13:0] soc_awburst;
    wire [  6:0] soc_awlock;
    wire [ 27:0] soc_awcache;
    wire [ 20:0] soc_awprot;
    wire [ 27:0] soc_awregion;
    wire [ 27:0] soc_awqos;
    wire [  6:0] soc_awvalid;
    wire [  6:0] soc_awready;
    wire [223:0] soc_wdata;
    wire [ 27:0] soc_wstrb;
    wire [  6:0] soc_wlast;
    wire [  6:0] soc_wvalid;
    wire [  6:0] soc_wready;
    wire [ 13:0] soc_bresp;
    wire [  6:0] soc_bvalid;
    wire [  6:0] soc_bready;
    wire [223:0] soc_araddr;
    wire [ 55:0] soc_arlen;
    wire [ 20:0] soc_arsize;
    wire [ 13:0] soc_arburst;
    wire [  6:0] soc_arlock;
    wire [ 27:0] soc_arcache;
    wire [ 20:0] soc_arprot;
    wire [ 27:0] soc_arregion;
    wire [ 27:0] soc_arqos;
    wire [  6:0] soc_arvalid;
    wire [  6:0] soc_arready;
    wire [223:0] soc_rdata;
    wire [ 13:0] soc_rresp;
    wire [  6:0] soc_rlast;
    wire [  6:0] soc_rvalid;
    wire [  6:0] soc_rready;
    wire [ 31:0] dig_value;
    assign bram_awaddr   = soc_awaddr[31:0];
    assign bram_awlen    = soc_awlen[7:0];
    assign bram_awsize   = soc_awsize[2:0];
    assign bram_awburst  = soc_awburst[1:0];
    assign bram_awvalid  = soc_awvalid[0];
    assign soc_awready[0]= bram_awready;
    assign bram_wdata    = soc_wdata[31:0];
    assign bram_wstrb    = soc_wstrb[3:0];
    assign bram_wlast    = soc_wlast[0];
    assign bram_wvalid   = soc_wvalid[0];
    assign soc_wready[0] = bram_wready;
    assign soc_bresp[1:0]= bram_bresp;
    assign soc_bvalid[0] = bram_bvalid;
    assign bram_bready   = soc_bready[0];
    assign bram_araddr   = soc_araddr[31:0];
    assign bram_arlen    = soc_arlen[7:0];
    assign bram_arsize   = soc_arsize[2:0];
    assign bram_arburst  = soc_arburst[1:0];
    assign bram_arvalid  = soc_arvalid[0];
    assign soc_arready[0]= bram_arready;
    assign soc_rdata[31:0]= bram_rdata;
    assign soc_rresp[1:0]= bram_rresp;
    assign soc_rlast[0]  = bram_rlast;
    assign soc_rvalid[0] = bram_rvalid;
    assign bram_rready   = soc_rready[0];

    axi_crossbar_0 U_crossbar (
        .aclk           (sys_clk),
        .aresetn        (!sys_rst),
        .s_axi_awaddr   (cpu_awaddr),
        .s_axi_awlen    (cpu_awlen),
        .s_axi_awsize   (cpu_awsize),
        .s_axi_awburst  (cpu_awburst),
        .s_axi_awlock   (1'b0),
        .s_axi_awcache  (4'b0),
        .s_axi_awprot   (3'b0),
        .s_axi_awqos    (4'b0),
        .s_axi_awvalid  (cpu_awvalid),
        .s_axi_awready  (cpu_awready),
        .s_axi_wdata    (cpu_wdata),
        .s_axi_wstrb    (cpu_wstrb),
        .s_axi_wlast    (cpu_wlast),
        .s_axi_wvalid   (cpu_wvalid),
        .s_axi_wready   (cpu_wready),
        .s_axi_bresp    (cpu_bresp),
        .s_axi_bvalid   (cpu_bvalid),
        .s_axi_bready   (cpu_bready),
        .s_axi_araddr   (cpu_araddr),
        .s_axi_arlen    (cpu_arlen),
        .s_axi_arsize   (cpu_arsize),
        .s_axi_arburst  (cpu_arburst),
        .s_axi_arlock   (1'b0),
        .s_axi_arcache  (4'b0),
        .s_axi_arprot   (3'b0),
        .s_axi_arqos    (4'b0),
        .s_axi_arvalid  (cpu_arvalid),
        .s_axi_arready  (cpu_arready),
        .s_axi_rdata    (cpu_rdata),
        .s_axi_rresp    (cpu_rresp),
        .s_axi_rlast    (cpu_rlast),
        .s_axi_rvalid   (cpu_rvalid),
        .s_axi_rready   (cpu_rready),
        .m_axi_awaddr   (soc_awaddr),
        .m_axi_awlen    (soc_awlen),
        .m_axi_awsize   (soc_awsize),
        .m_axi_awburst  (soc_awburst),
        .m_axi_awlock   (soc_awlock),
        .m_axi_awcache  (soc_awcache),
        .m_axi_awprot   (soc_awprot),
        .m_axi_awregion (soc_awregion),
        .m_axi_awqos    (soc_awqos),
        .m_axi_awvalid  (soc_awvalid),
        .m_axi_awready  (soc_awready),
        .m_axi_wdata    (soc_wdata),
        .m_axi_wstrb    (soc_wstrb),
        .m_axi_wlast    (soc_wlast),
        .m_axi_wvalid   (soc_wvalid),
        .m_axi_wready   (soc_wready),
        .m_axi_bresp    (soc_bresp),
        .m_axi_bvalid   (soc_bvalid),
        .m_axi_bready   (soc_bready),
        .m_axi_araddr   (soc_araddr),
        .m_axi_arlen    (soc_arlen),
        .m_axi_arsize   (soc_arsize),
        .m_axi_arburst  (soc_arburst),
        .m_axi_arlock   (soc_arlock),
        .m_axi_arcache  (soc_arcache),
        .m_axi_arprot   (soc_arprot),
        .m_axi_arregion (soc_arregion),
        .m_axi_arqos    (soc_arqos),
        .m_axi_arvalid  (soc_arvalid),
        .m_axi_arready  (soc_arready),
        .m_axi_rdata    (soc_rdata),
        .m_axi_rresp    (soc_rresp),
        .m_axi_rlast    (soc_rlast),
        .m_axi_rvalid   (soc_rvalid),
        .m_axi_rready   (soc_rready)
    );

`ifdef USE_DDR
    mig_wrap U_ddr (
        .aclk           (sys_clk),
        .aresetn        (!sys_rst),
        .s_axi_awaddr   (soc_awaddr[63:32]),
        .s_axi_awlen    (soc_awlen[15:8]),
        .s_axi_awsize   (soc_awsize[5:3]),
        .s_axi_awburst  (soc_awburst[3:2]),
        .s_axi_awvalid  (soc_awvalid[1]),
        .s_axi_awready  (soc_awready[1]),
        .s_axi_wdata    (soc_wdata[63:32]),
        .s_axi_wstrb    (soc_wstrb[7:4]),
        .s_axi_wlast    (soc_wlast[1]),
        .s_axi_wvalid   (soc_wvalid[1]),
        .s_axi_wready   (soc_wready[1]),
        .s_axi_bresp    (soc_bresp[3:2]),
        .s_axi_bvalid   (soc_bvalid[1]),
        .s_axi_bready   (soc_bready[1]),
        .s_axi_araddr   (soc_araddr[63:32]),
        .s_axi_arlen    (soc_arlen[15:8]),
        .s_axi_arsize   (soc_arsize[5:3]),
        .s_axi_arburst  (soc_arburst[3:2]),
        .s_axi_arvalid  (soc_arvalid[1]),
        .s_axi_arready  (soc_arready[1]),
        .s_axi_rdata    (soc_rdata[63:32]),
        .s_axi_rresp    (soc_rresp[3:2]),
        .s_axi_rlast    (soc_rlast[1]),
        .s_axi_rvalid   (soc_rvalid[1]),
        .s_axi_rready   (soc_rready[1]),
        .mig_sys_clk    (pll_clk2),
        .mig_reset      (!pll_lock),
        .ddr_init_done  (ddr_init_done),
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
    );
`else
    // Keep the reserved DDR crossbar slot well-defined when DDR is disabled.
    assign soc_awready[1] = 1'b0;
    assign soc_wready[1]  = 1'b0;
    assign soc_bresp[3:2] = 2'b11;
    assign soc_bvalid[1]  = 1'b0;
    assign soc_arready[1] = 1'b0;
    assign soc_rdata[63:32] = 32'h0;
    assign soc_rresp[3:2] = 2'b11;
    assign soc_rlast[1]   = 1'b0;
    assign soc_rvalid[1]  = 1'b0;
`endif

    gpio_wrap #(.GPIO_KIND(0)) U_switch (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(soc_awaddr[95:64]), .s_axi_awlen(soc_awlen[23:16]),
        .s_axi_awsize(soc_awsize[8:6]), .s_axi_awburst(soc_awburst[5:4]),
        .s_axi_awlock(soc_awlock[2]), .s_axi_awcache(soc_awcache[11:8]),
        .s_axi_awprot(soc_awprot[8:6]), .s_axi_awregion(soc_awregion[11:8]),
        .s_axi_awqos(soc_awqos[11:8]), .s_axi_awvalid(soc_awvalid[2]),
        .s_axi_awready(soc_awready[2]), .s_axi_wdata(soc_wdata[95:64]),
        .s_axi_wstrb(soc_wstrb[11:8]), .s_axi_wlast(soc_wlast[2]),
        .s_axi_wvalid(soc_wvalid[2]), .s_axi_wready(soc_wready[2]),
        .s_axi_bresp(soc_bresp[5:4]), .s_axi_bvalid(soc_bvalid[2]),
        .s_axi_bready(soc_bready[2]), .s_axi_araddr(soc_araddr[95:64]),
        .s_axi_arlen(soc_arlen[23:16]), .s_axi_arsize(soc_arsize[8:6]),
        .s_axi_arburst(soc_arburst[5:4]), .s_axi_arlock(soc_arlock[2]),
        .s_axi_arcache(soc_arcache[11:8]), .s_axi_arprot(soc_arprot[8:6]),
        .s_axi_arregion(soc_arregion[11:8]), .s_axi_arqos(soc_arqos[11:8]),
        .s_axi_arvalid(soc_arvalid[2]), .s_axi_arready(soc_arready[2]),
        .s_axi_rdata(soc_rdata[95:64]), .s_axi_rresp(soc_rresp[5:4]),
        .s_axi_rlast(soc_rlast[2]), .s_axi_rvalid(soc_rvalid[2]),
        .s_axi_rready(soc_rready[2]), .gpio_i(sw), .gpio_o(), .dig_value()
    );

    gpio_wrap #(.GPIO_KIND(1)) U_led (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(soc_awaddr[127:96]), .s_axi_awlen(soc_awlen[31:24]),
        .s_axi_awsize(soc_awsize[11:9]), .s_axi_awburst(soc_awburst[7:6]),
        .s_axi_awlock(soc_awlock[3]), .s_axi_awcache(soc_awcache[15:12]),
        .s_axi_awprot(soc_awprot[11:9]), .s_axi_awregion(soc_awregion[15:12]),
        .s_axi_awqos(soc_awqos[15:12]), .s_axi_awvalid(soc_awvalid[3]),
        .s_axi_awready(soc_awready[3]), .s_axi_wdata(soc_wdata[127:96]),
        .s_axi_wstrb(soc_wstrb[15:12]), .s_axi_wlast(soc_wlast[3]),
        .s_axi_wvalid(soc_wvalid[3]), .s_axi_wready(soc_wready[3]),
        .s_axi_bresp(soc_bresp[7:6]), .s_axi_bvalid(soc_bvalid[3]),
        .s_axi_bready(soc_bready[3]), .s_axi_araddr(soc_araddr[127:96]),
        .s_axi_arlen(soc_arlen[31:24]), .s_axi_arsize(soc_arsize[11:9]),
        .s_axi_arburst(soc_arburst[7:6]), .s_axi_arlock(soc_arlock[3]),
        .s_axi_arcache(soc_arcache[15:12]), .s_axi_arprot(soc_arprot[11:9]),
        .s_axi_arregion(soc_arregion[15:12]), .s_axi_arqos(soc_arqos[15:12]),
        .s_axi_arvalid(soc_arvalid[3]), .s_axi_arready(soc_arready[3]),
        .s_axi_rdata(soc_rdata[127:96]), .s_axi_rresp(soc_rresp[7:6]),
        .s_axi_rlast(soc_rlast[3]), .s_axi_rvalid(soc_rvalid[3]),
        .s_axi_rready(soc_rready[3]), .gpio_i(24'h0), .gpio_o(led), .dig_value()
    );

    gpio_wrap #(.GPIO_KIND(2)) U_digled (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(soc_awaddr[159:128]), .s_axi_awlen(soc_awlen[39:32]),
        .s_axi_awsize(soc_awsize[14:12]), .s_axi_awburst(soc_awburst[9:8]),
        .s_axi_awlock(soc_awlock[4]), .s_axi_awcache(soc_awcache[19:16]),
        .s_axi_awprot(soc_awprot[14:12]), .s_axi_awregion(soc_awregion[19:16]),
        .s_axi_awqos(soc_awqos[19:16]), .s_axi_awvalid(soc_awvalid[4]),
        .s_axi_awready(soc_awready[4]), .s_axi_wdata(soc_wdata[159:128]),
        .s_axi_wstrb(soc_wstrb[19:16]), .s_axi_wlast(soc_wlast[4]),
        .s_axi_wvalid(soc_wvalid[4]), .s_axi_wready(soc_wready[4]),
        .s_axi_bresp(soc_bresp[9:8]), .s_axi_bvalid(soc_bvalid[4]),
        .s_axi_bready(soc_bready[4]), .s_axi_araddr(soc_araddr[159:128]),
        .s_axi_arlen(soc_arlen[39:32]), .s_axi_arsize(soc_arsize[14:12]),
        .s_axi_arburst(soc_arburst[9:8]), .s_axi_arlock(soc_arlock[4]),
        .s_axi_arcache(soc_arcache[19:16]), .s_axi_arprot(soc_arprot[14:12]),
        .s_axi_arregion(soc_arregion[19:16]), .s_axi_arqos(soc_arqos[19:16]),
        .s_axi_arvalid(soc_arvalid[4]), .s_axi_arready(soc_arready[4]),
        .s_axi_rdata(soc_rdata[159:128]), .s_axi_rresp(soc_rresp[9:8]),
        .s_axi_rlast(soc_rlast[4]), .s_axi_rvalid(soc_rvalid[4]),
        .s_axi_rready(soc_rready[4]), .gpio_i(24'h0), .gpio_o(), .dig_value(dig_value)
    );

    uart_wrap U_uart (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(soc_awaddr[191:160]), .s_axi_awlen(soc_awlen[47:40]),
        .s_axi_awsize(soc_awsize[17:15]), .s_axi_awburst(soc_awburst[11:10]),
        .s_axi_awlock(soc_awlock[5]), .s_axi_awcache(soc_awcache[23:20]),
        .s_axi_awprot(soc_awprot[17:15]), .s_axi_awregion(soc_awregion[23:20]),
        .s_axi_awqos(soc_awqos[23:20]), .s_axi_awvalid(soc_awvalid[5]),
        .s_axi_awready(soc_awready[5]), .s_axi_wdata(soc_wdata[191:160]),
        .s_axi_wstrb(soc_wstrb[23:20]), .s_axi_wlast(soc_wlast[5]),
        .s_axi_wvalid(soc_wvalid[5]), .s_axi_wready(soc_wready[5]),
        .s_axi_bresp(soc_bresp[11:10]), .s_axi_bvalid(soc_bvalid[5]),
        .s_axi_bready(soc_bready[5]), .s_axi_araddr(soc_araddr[191:160]),
        .s_axi_arlen(soc_arlen[47:40]), .s_axi_arsize(soc_arsize[17:15]),
        .s_axi_arburst(soc_arburst[11:10]), .s_axi_arlock(soc_arlock[5]),
        .s_axi_arcache(soc_arcache[23:20]), .s_axi_arprot(soc_arprot[17:15]),
        .s_axi_arregion(soc_arregion[23:20]), .s_axi_arqos(soc_arqos[23:20]),
        .s_axi_arvalid(soc_arvalid[5]), .s_axi_arready(soc_arready[5]),
        .s_axi_rdata(soc_rdata[191:160]), .s_axi_rresp(soc_rresp[11:10]),
        .s_axi_rlast(soc_rlast[5]), .s_axi_rvalid(soc_rvalid[5]),
        .s_axi_rready(soc_rready[5]), .rx(rx), .tx(tx)
    );

    timer_wrap U_timer (
        .aclk(sys_clk), .aresetn(!sys_rst),
        .s_axi_awaddr(soc_awaddr[223:192]), .s_axi_awlen(soc_awlen[55:48]),
        .s_axi_awsize(soc_awsize[20:18]), .s_axi_awburst(soc_awburst[13:12]),
        .s_axi_awlock(soc_awlock[6]), .s_axi_awcache(soc_awcache[27:24]),
        .s_axi_awprot(soc_awprot[20:18]), .s_axi_awregion(soc_awregion[27:24]),
        .s_axi_awqos(soc_awqos[27:24]), .s_axi_awvalid(soc_awvalid[6]),
        .s_axi_awready(soc_awready[6]), .s_axi_wdata(soc_wdata[223:192]),
        .s_axi_wstrb(soc_wstrb[27:24]), .s_axi_wlast(soc_wlast[6]),
        .s_axi_wvalid(soc_wvalid[6]), .s_axi_wready(soc_wready[6]),
        .s_axi_bresp(soc_bresp[13:12]), .s_axi_bvalid(soc_bvalid[6]),
        .s_axi_bready(soc_bready[6]), .s_axi_araddr(soc_araddr[223:192]),
        .s_axi_arlen(soc_arlen[55:48]), .s_axi_arsize(soc_arsize[20:18]),
        .s_axi_arburst(soc_arburst[13:12]), .s_axi_arlock(soc_arlock[6]),
        .s_axi_arcache(soc_arcache[27:24]), .s_axi_arprot(soc_arprot[20:18]),
        .s_axi_arregion(soc_arregion[27:24]), .s_axi_arqos(soc_arqos[27:24]),
        .s_axi_arvalid(soc_arvalid[6]), .s_axi_arready(soc_arready[6]),
        .s_axi_rdata(soc_rdata[223:192]), .s_axi_rresp(soc_rresp[13:12]),
        .s_axi_rlast(soc_rlast[6]), .s_axi_rvalid(soc_rvalid[6]),
        .s_axi_rready(soc_rready[6])
    );

    digled_scan U_digled_scan (
        .clk     (sys_clk),
        .rst     (sys_rst),
        .value   (dig_value),
        .dig_en  (dig_en),
        .dig_seg (dig_seg)
    );
`endif

    bram_axi U_bram (
        .s_aclk         (sys_clk),
        .s_aresetn      (!sys_rst),
        .s_axi_awid     (4'h6),
        .s_axi_awaddr   (bram_awaddr ),
        .s_axi_awlen    (bram_awlen  ),
        .s_axi_awsize   (bram_awsize ),
        .s_axi_awburst  (bram_awburst),
        .s_axi_awready  (bram_awready),
        .s_axi_awvalid  (bram_awvalid),
        .s_axi_wdata    (bram_wdata  ),
        .s_axi_wstrb    (bram_wstrb  ),
        .s_axi_wvalid   (bram_wvalid ),
        .s_axi_wlast    (bram_wlast  ),
        .s_axi_wready   (bram_wready ),
        .s_axi_bready   (bram_bready ),
        .s_axi_bresp    (bram_bresp  ),
        .s_axi_bvalid   (bram_bvalid ),
        .s_axi_arid     (4'h6),
        .s_axi_araddr   (bram_araddr ),
        .s_axi_arlen    (bram_arlen  ),
        .s_axi_arsize   (bram_arsize ),
        .s_axi_arburst  (bram_arburst),
        .s_axi_arready  (bram_arready),
        .s_axi_arvalid  (bram_arvalid),
        .s_axi_rdata    (bram_rdata  ),
        .s_axi_rvalid   (bram_rvalid ),
        .s_axi_rlast    (bram_rlast  ),
        .s_axi_rready   (bram_rready ),
        .s_axi_rresp    (bram_rresp  )
    );

    cpu_top U_cpu (
        .cpu_clk        (sys_clk),
        .cpu_rst        (cpu_rst),

        // AXI4 Master Interface
        // write address channel
        .m_axi_awaddr   (cpu_awaddr),
        .m_axi_awlen    (cpu_awlen),
        .m_axi_awsize   (cpu_awsize),
        .m_axi_awburst  (cpu_awburst),
        .m_axi_awvalid  (cpu_awvalid),
        .m_axi_awready  (cpu_awready),
        // write data channel
        .m_axi_wdata    (cpu_wdata),
        .m_axi_wstrb    (cpu_wstrb),
        .m_axi_wlast    (cpu_wlast),
        .m_axi_wvalid   (cpu_wvalid),
        .m_axi_wready   (cpu_wready),
        // write response channel
        .m_axi_bready   (cpu_bready),
        .m_axi_bresp    (cpu_bresp),
        .m_axi_bvalid   (cpu_bvalid),
        // read address channel
        .m_axi_araddr   (cpu_araddr),
        .m_axi_arlen    (cpu_arlen),
        .m_axi_arsize   (cpu_arsize),
        .m_axi_arburst  (cpu_arburst),
        .m_axi_arvalid  (cpu_arvalid),
        .m_axi_arready  (cpu_arready),
        // read data channel
        .m_axi_rready   (cpu_rready),
        .m_axi_rdata    (cpu_rdata),
        .m_axi_rresp    (cpu_rresp),
        .m_axi_rlast    (cpu_rlast),
        .m_axi_rvalid   (cpu_rvalid)
    );

endmodule
