`timescale 1ns / 1ps

// Course-prescribed wrapper around the MIG and AXI Interconnect.
// The slave side is synchronous to the CPU clock; the master side is
// synchronous to the MIG-generated ui_clk.
module mig_wrap (
    input  wire         aclk,
    input  wire         aresetn,
    input  wire [31:0]  s_axi_awaddr,
    input  wire [ 7:0]  s_axi_awlen,
    input  wire [ 2:0]  s_axi_awsize,
    input  wire [ 1:0]  s_axi_awburst,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,
    input  wire [31:0]  s_axi_wdata,
    input  wire [ 3:0]  s_axi_wstrb,
    input  wire         s_axi_wlast,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,
    output wire [ 1:0]  s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,
    input  wire [31:0]  s_axi_araddr,
    input  wire [ 7:0]  s_axi_arlen,
    input  wire [ 2:0]  s_axi_arsize,
    input  wire [ 1:0]  s_axi_arburst,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,
    output wire [31:0]  s_axi_rdata,
    output wire [ 1:0]  s_axi_rresp,
    output wire         s_axi_rlast,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready,

    input  wire         mig_sys_clk,
    input  wire         mig_reset,
    output reg          ddr_init_done,
    output wire [14:0]  ddr3_addr,
    output wire [ 2:0]  ddr3_ba,
    output wire         ddr3_cas_n,
    output wire [ 0:0]  ddr3_ck_p,
    output wire [ 0:0]  ddr3_ck_n,
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
);

    wire        ui_clk;
    wire        ui_rst;
    wire [ 3:0] mig_awid;
    wire [28:0] mig_awaddr;
    wire [ 7:0] mig_awlen;
    wire [ 2:0] mig_awsize;
    wire [ 1:0] mig_awburst;
    wire [ 0:0] mig_awlock;
    wire [ 3:0] mig_awcache;
    wire [ 2:0] mig_awprot;
    wire [ 3:0] mig_awqos;
    wire        mig_awvalid;
    wire        mig_awready;
    wire [31:0] mig_wdata;
    wire [ 3:0] mig_wstrb;
    wire        mig_wlast;
    wire        mig_wvalid;
    wire        mig_wready;
    wire        mig_bready;
    wire [ 3:0] mig_bid;
    wire [ 1:0] mig_bresp;
    wire        mig_bvalid;
    wire [ 3:0] mig_arid;
    wire [28:0] mig_araddr;
    wire [ 7:0] mig_arlen;
    wire [ 2:0] mig_arsize;
    wire [ 1:0] mig_arburst;
    wire [ 0:0] mig_arlock;
    wire [ 3:0] mig_arcache;
    wire [ 2:0] mig_arprot;
    wire [ 3:0] mig_arqos;
    wire        mig_arvalid;
    wire        mig_arready;
    wire        mig_rready;
    wire [ 3:0] mig_rid;
    wire [31:0] mig_rdata;
    wire [ 1:0] mig_rresp;
    wire        mig_rlast;
    wire        mig_rvalid;

    (* ASYNC_REG = "TRUE" *) reg [1:0] mig_reset_sync;
    wire mig_rst;
    wire init_calib_complete;
    reg  init_calib_complete_r;

    // MIG calibration is a cold-reset operation.  Assert reset when its source
    // PLL is unlocked, then release it synchronously in the 200 MHz domain.
    // A board-button warm reset uses aresetn to clear the AXI transaction layer
    // without needlessly restarting the physical DDR calibration.
    always @(posedge mig_sys_clk or posedge mig_reset) begin
        if (mig_reset)
            mig_reset_sync <= 2'b11;
        else
            mig_reset_sync <= {mig_reset_sync[0], 1'b0};
    end
    assign mig_rst = mig_reset_sync[1];

    // Synchronize MIG calibration completion back into the CPU clock domain.
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            init_calib_complete_r <= 1'b0;
            ddr_init_done         <= 1'b0;
        end
        else begin
            init_calib_complete_r <= init_calib_complete;
            ddr_init_done         <= init_calib_complete_r;
        end
    end

    axi_interconnect_0 U_axi_interconnect (
        .INTERCONNECT_ACLK      (aclk),
        .INTERCONNECT_ARESETN   (aresetn),
        .S00_AXI_ARESET_OUT_N   (),
        .S00_AXI_ACLK           (aclk),
        .S00_AXI_AWID           (1'b0),
        .S00_AXI_AWADDR         (s_axi_awaddr),
        .S00_AXI_AWLEN          (s_axi_awlen),
        .S00_AXI_AWSIZE         (s_axi_awsize),
        .S00_AXI_AWBURST        (s_axi_awburst),
        .S00_AXI_AWLOCK         (1'b0),
        .S00_AXI_AWCACHE        (4'h0),
        .S00_AXI_AWPROT         (3'h0),
        .S00_AXI_AWQOS          (4'h0),
        .S00_AXI_AWVALID        (s_axi_awvalid),
        .S00_AXI_AWREADY        (s_axi_awready),
        .S00_AXI_WDATA          (s_axi_wdata),
        .S00_AXI_WSTRB          (s_axi_wstrb),
        .S00_AXI_WLAST          (s_axi_wlast),
        .S00_AXI_WVALID         (s_axi_wvalid),
        .S00_AXI_WREADY         (s_axi_wready),
        .S00_AXI_BID            (),
        .S00_AXI_BRESP          (s_axi_bresp),
        .S00_AXI_BVALID         (s_axi_bvalid),
        .S00_AXI_BREADY         (s_axi_bready),
        .S00_AXI_ARID           (1'b1),
        .S00_AXI_ARADDR         (s_axi_araddr),
        .S00_AXI_ARLEN          (s_axi_arlen),
        .S00_AXI_ARSIZE         (s_axi_arsize),
        .S00_AXI_ARBURST        (s_axi_arburst),
        .S00_AXI_ARLOCK         (1'b0),
        .S00_AXI_ARCACHE        (4'h0),
        .S00_AXI_ARPROT         (3'h0),
        .S00_AXI_ARQOS          (4'h0),
        .S00_AXI_ARVALID        (s_axi_arvalid),
        .S00_AXI_ARREADY        (s_axi_arready),
        .S00_AXI_RID            (),
        .S00_AXI_RDATA          (s_axi_rdata),
        .S00_AXI_RRESP          (s_axi_rresp),
        .S00_AXI_RLAST          (s_axi_rlast),
        .S00_AXI_RVALID         (s_axi_rvalid),
        .S00_AXI_RREADY         (s_axi_rready),
        .M00_AXI_ARESET_OUT_N   (),
        .M00_AXI_ACLK           (ui_clk),
        .M00_AXI_AWID           (mig_awid),
        .M00_AXI_AWADDR         (mig_awaddr),
        .M00_AXI_AWLEN          (mig_awlen),
        .M00_AXI_AWSIZE         (mig_awsize),
        .M00_AXI_AWBURST        (mig_awburst),
        .M00_AXI_AWLOCK         (mig_awlock),
        .M00_AXI_AWCACHE        (mig_awcache),
        .M00_AXI_AWPROT         (mig_awprot),
        .M00_AXI_AWQOS          (mig_awqos),
        .M00_AXI_AWVALID        (mig_awvalid),
        .M00_AXI_AWREADY        (mig_awready),
        .M00_AXI_WDATA          (mig_wdata),
        .M00_AXI_WSTRB          (mig_wstrb),
        .M00_AXI_WLAST          (mig_wlast),
        .M00_AXI_WVALID         (mig_wvalid),
        .M00_AXI_WREADY         (mig_wready),
        .M00_AXI_BID            (mig_bid),
        .M00_AXI_BRESP          (mig_bresp),
        .M00_AXI_BVALID         (mig_bvalid),
        .M00_AXI_BREADY         (mig_bready),
        .M00_AXI_ARID           (mig_arid),
        .M00_AXI_ARADDR         (mig_araddr),
        .M00_AXI_ARLEN          (mig_arlen),
        .M00_AXI_ARSIZE         (mig_arsize),
        .M00_AXI_ARBURST        (mig_arburst),
        .M00_AXI_ARLOCK         (mig_arlock),
        .M00_AXI_ARCACHE        (mig_arcache),
        .M00_AXI_ARPROT         (mig_arprot),
        .M00_AXI_ARQOS          (mig_arqos),
        .M00_AXI_ARVALID        (mig_arvalid),
        .M00_AXI_ARREADY        (mig_arready),
        .M00_AXI_RID            (mig_rid),
        .M00_AXI_RDATA          (mig_rdata),
        .M00_AXI_RRESP          (mig_rresp),
        .M00_AXI_RLAST          (mig_rlast),
        .M00_AXI_RVALID         (mig_rvalid),
        .M00_AXI_RREADY         (mig_rready)
    );

    mig_7series_0 U_mig (
        .sys_clk_i           (mig_sys_clk),
        .sys_rst             (mig_rst),
        .ui_clk              (ui_clk),
        .ui_clk_sync_rst     (ui_rst),
        .aresetn             (!ui_rst),
        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0),
        .s_axi_awid          (mig_awid),
        .s_axi_awaddr        (mig_awaddr),
        .s_axi_awlen         (mig_awlen),
        .s_axi_awsize        (mig_awsize),
        .s_axi_awburst       (mig_awburst),
        .s_axi_awlock        (mig_awlock),
        .s_axi_awcache       (mig_awcache),
        .s_axi_awprot        (mig_awprot),
        .s_axi_awqos         (mig_awqos),
        .s_axi_awvalid       (mig_awvalid),
        .s_axi_awready       (mig_awready),
        .s_axi_wdata         (mig_wdata),
        .s_axi_wstrb         (mig_wstrb),
        .s_axi_wlast         (mig_wlast),
        .s_axi_wvalid        (mig_wvalid),
        .s_axi_wready        (mig_wready),
        .s_axi_bid           (mig_bid),
        .s_axi_bresp         (mig_bresp),
        .s_axi_bvalid        (mig_bvalid),
        .s_axi_bready        (mig_bready),
        .s_axi_arid          (mig_arid),
        .s_axi_araddr        (mig_araddr),
        .s_axi_arlen         (mig_arlen),
        .s_axi_arsize        (mig_arsize),
        .s_axi_arburst       (mig_arburst),
        .s_axi_arlock        (mig_arlock),
        .s_axi_arcache       (mig_arcache),
        .s_axi_arprot        (mig_arprot),
        .s_axi_arqos         (mig_arqos),
        .s_axi_arvalid       (mig_arvalid),
        .s_axi_arready       (mig_arready),
        .s_axi_rid           (mig_rid),
        .s_axi_rdata         (mig_rdata),
        .s_axi_rresp         (mig_rresp),
        .s_axi_rlast         (mig_rlast),
        .s_axi_rvalid        (mig_rvalid),
        .s_axi_rready        (mig_rready),
        .init_calib_complete (init_calib_complete),
        .ddr3_addr           (ddr3_addr),
        .ddr3_ba             (ddr3_ba),
        .ddr3_cas_n          (ddr3_cas_n),
        .ddr3_ck_n           (ddr3_ck_n),
        .ddr3_ck_p           (ddr3_ck_p),
        .ddr3_cke            (ddr3_cke),
        .ddr3_ras_n          (ddr3_ras_n),
        .ddr3_we_n           (ddr3_we_n),
        .ddr3_dq             (ddr3_dq),
        .ddr3_dqs_n          (ddr3_dqs_n),
        .ddr3_dqs_p          (ddr3_dqs_p),
        .ddr3_reset_n        (ddr3_reset_n),
        .ddr3_cs_n           (ddr3_cs_n),
        .ddr3_dm             (ddr3_dm),
        .ddr3_odt            (ddr3_odt)
    );

endmodule
