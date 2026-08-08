`timescale 1ns / 1ps

`include "defines.vh"

module cpu_top(
    input  wire         cpu_clk,
    input  wire         cpu_rst,        // high active

    // AXI4 Master Interface
    // write address channel
    output wire [31:0]  m_axi_awaddr,
    output wire [ 7:0]  m_axi_awlen,
    output wire [ 2:0]  m_axi_awsize,
    output wire [ 1:0]  m_axi_awburst,
    input  wire         m_axi_awready,
    output wire         m_axi_awvalid,
    // write data channel
    output wire [31:0]  m_axi_wdata,
    input  wire         m_axi_wready,
    output wire [ 3:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    // write response channel
    output wire         m_axi_bready,
    input  wire [ 1:0]  m_axi_bresp,
    input  wire         m_axi_bvalid,
    // read address channel
    output wire [31:0]  m_axi_araddr,
    output wire [ 7:0]  m_axi_arlen,
    output wire [ 2:0]  m_axi_arsize,
    output wire [ 1:0]  m_axi_arburst,
    input  wire         m_axi_arready,
    output wire         m_axi_arvalid,
    // read data channel
    input  wire [31:0]  m_axi_rdata,
    output wire         m_axi_rready,
    input  wire [ 1:0]  m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid
);

    wire        cpu2ic_rreq;
    wire [31:0] cpu2ic_addr;
    wire        ic2cpu_valid;
    wire [31:0] ic2cpu_inst;

    wire [ 3:0] cpu2dc_ren;
    wire [31:0] cpu2dc_addr;
    wire        dc2cpu_valid;
    wire [31:0] dc2cpu_rdata;
    wire [ 3:0] cpu2dc_wen;
    wire [31:0] cpu2dc_wdata;
    wire        dc2cpu_wresp;

    // ICache <-> memory bus interface
    wire         ic_dev_rrdy;
    wire [ 3:0]  ic_cpu_ren;
    wire [31:0]  ic_cpu_raddr;
    wire         ic_dev_rvalid;
    wire [127:0] ic_dev_rdata;
    wire [`IC_BLK_SIZE-1:0] ic_axi_rdata;

    // DCache <-> memory bus interface
    wire         dc_dev_wrdy;
    wire [ 3:0]  dc_cpu_wen;
    wire [31:0]  dc_cpu_waddr;
    wire [31:0]  dc_cpu_wdata;
    wire         dc_dev_rrdy;
    wire [ 3:0]  dc_cpu_ren;
    wire [31:0]  dc_cpu_raddr;
    wire         dc_dev_rvalid;
    wire [127:0] dc_dev_rdata;
    wire [`DC_BLK_SIZE-1:0] dc_axi_rdata;

    // axi_master has one request bit, while the Cache byte-read enables are
    // four bits.  Any asserted byte lane represents one AXI read request.
    wire ic_axi_ren = |ic_cpu_ren;
    wire dc_axi_ren = |dc_cpu_ren;

    // The uncached configuration returns one 32-bit AXI beat.  Keep the
    // Cache-side interface at 128 bits and extend the active AXI block width.
    assign ic_dev_rdata = {{(128-`IC_BLK_SIZE){1'b0}}, ic_axi_rdata};
    assign dc_dev_rdata = {{(128-`DC_BLK_SIZE){1'b0}}, dc_axi_rdata};

    cpu_core U_core (
        .cpu_clk        (cpu_clk),
        .cpu_rst        (cpu_rst),
        // Instruction Fetch Interface
        .ifetch_req     (cpu2ic_rreq),
        .ifetch_addr    (cpu2ic_addr),
        .ifetch_valid   (ic2cpu_valid),
        .ifetch_inst    (ic2cpu_inst),
        // Data Access Interface
        .daccess_ren    (cpu2dc_ren),
        .daccess_addr   (cpu2dc_addr),
        .daccess_rvalid (dc2cpu_valid),
        .daccess_rdata  (dc2cpu_rdata),
        .daccess_wen    (cpu2dc_wen),
        .daccess_wdata  (cpu2dc_wdata),
        .daccess_wresp  (dc2cpu_wresp)
    );

    ICache U_icache (
        .cpu_clk        (cpu_clk),
        .cpu_rst        (cpu_rst),
        // Interface to CPU
        .inst_rreq      (cpu2ic_rreq),
        .inst_addr      (cpu2ic_addr),
        .inst_valid     (ic2cpu_valid),
        .inst_out       (ic2cpu_inst),
        // Interface to Read Bus
        .dev_rrdy       (ic_dev_rrdy),
        .cpu_ren        (ic_cpu_ren),
        .cpu_raddr      (ic_cpu_raddr),
        .dev_rvalid     (ic_dev_rvalid),
        .dev_rdata      (ic_dev_rdata)
    );

    DCache U_dcache (
        .cpu_clk        (cpu_clk),
        .cpu_rst        (cpu_rst),
        // Interface to CPU
        .data_ren       (cpu2dc_ren),
        .data_addr      (cpu2dc_addr),
        .data_valid     (dc2cpu_valid),
        .data_rdata     (dc2cpu_rdata),
        .data_wen       (cpu2dc_wen),
        .data_wdata     (cpu2dc_wdata),
        .data_wresp     (dc2cpu_wresp),
        // Interface to Write Bus
        .dev_wrdy       (dc_dev_wrdy),
        .cpu_wen        (dc_cpu_wen),
        .cpu_waddr      (dc_cpu_waddr),
        .cpu_wdata      (dc_cpu_wdata),
        // Interface to Read Bus
        .dev_rrdy       (dc_dev_rrdy),
        .cpu_ren        (dc_cpu_ren),
        .cpu_raddr      (dc_cpu_raddr),
        .dev_rvalid     (dc_dev_rvalid),
        .dev_rdata      (dc_dev_rdata)
    );

    axi_master U_aximaster (
        .aclk           (cpu_clk),
        .areset         (cpu_rst),

        // ICache Interface
        .ic_dev_rrdy    (ic_dev_rrdy),
        .ic_cpu_ren     (ic_axi_ren),
        .ic_cpu_raddr   (ic_cpu_raddr),
        .ic_dev_rvalid  (ic_dev_rvalid),
        .ic_dev_rdata   (ic_axi_rdata),
        // DCache Interface
        .dc_dev_wrdy    (dc_dev_wrdy),
        .dc_cpu_wen     (dc_cpu_wen),
        .dc_cpu_waddr   (dc_cpu_waddr),
        .dc_cpu_wdata   (dc_cpu_wdata),
        .dc_dev_rrdy    (dc_dev_rrdy),
        .dc_cpu_ren     (dc_axi_ren),
        .dc_cpu_raddr   (dc_cpu_raddr),
        .dc_dev_rvalid  (dc_dev_rvalid),
        .dc_dev_rdata   (dc_axi_rdata),

        // AXI4 Master Interface
        // write address channel
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awready  (m_axi_awready),
        .m_axi_awvalid  (m_axi_awvalid),
        // write data channel
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wready   (m_axi_wready),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        // write response channel
        .m_axi_bready   (m_axi_bready),
        .m_axi_bresp    (m_axi_bresp),
        .m_axi_bvalid   (m_axi_bvalid),
        // read address channel
        .m_axi_araddr   (m_axi_araddr),
        .m_axi_arlen    (m_axi_arlen),
        .m_axi_arsize   (m_axi_arsize),
        .m_axi_arburst  (m_axi_arburst),
        .m_axi_arready  (m_axi_arready),
        .m_axi_arvalid  (m_axi_arvalid),
        // read data channel
        .m_axi_rdata    (m_axi_rdata),
        .m_axi_rready   (m_axi_rready),
        .m_axi_rresp    (m_axi_rresp),
        .m_axi_rlast    (m_axi_rlast),
        .m_axi_rvalid   (m_axi_rvalid)
    );
    
endmodule
