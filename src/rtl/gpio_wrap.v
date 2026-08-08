`timescale 1ns / 1ps

module gpio_wrap #(
    parameter integer GPIO_KIND = 0
)(
    input  wire        aclk,
    input  wire        aresetn,
    input  wire [31:0] s_axi_awaddr,
    input  wire [ 7:0] s_axi_awlen,
    input  wire [ 2:0] s_axi_awsize,
    input  wire [ 1:0] s_axi_awburst,
    input  wire [ 0:0] s_axi_awlock,
    input  wire [ 3:0] s_axi_awcache,
    input  wire [ 2:0] s_axi_awprot,
    input  wire [ 3:0] s_axi_awregion,
    input  wire [ 3:0] s_axi_awqos,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [ 3:0] s_axi_wstrb,
    input  wire        s_axi_wlast,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [ 1:0] s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire [ 7:0] s_axi_arlen,
    input  wire [ 2:0] s_axi_arsize,
    input  wire [ 1:0] s_axi_arburst,
    input  wire [ 0:0] s_axi_arlock,
    input  wire [ 3:0] s_axi_arcache,
    input  wire [ 2:0] s_axi_arprot,
    input  wire [ 3:0] s_axi_arregion,
    input  wire [ 3:0] s_axi_arqos,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [ 1:0] s_axi_rresp,
    output wire        s_axi_rlast,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    input  wire [23:0] gpio_i,
    output wire [23:0] gpio_o,
    output wire [31:0] dig_value
);

    wire [31:0] gpio_awaddr;
    wire        gpio_awvalid;
    wire        gpio_awready;
    wire [31:0] gpio_wdata;
    wire [ 3:0] gpio_wstrb;
    wire        gpio_wvalid;
    wire        gpio_wready;
    wire [ 1:0] gpio_bresp;
    wire        gpio_bvalid;
    wire        gpio_bready;
    wire [31:0] gpio_araddr;
    wire        gpio_arvalid;
    wire        gpio_arready;
    wire [31:0] gpio_rdata;
    wire [ 1:0] gpio_rresp;
    wire        gpio_rvalid;
    wire        gpio_rready;

    generate
        if (GPIO_KIND == 0) begin : GEN_SWITCH
            assign gpio_o = 24'h0;
            assign dig_value = 32'h0;

            axi_gpio_1 U_switch (
                .s_axi_aclk    (aclk),
                .s_axi_aresetn (aresetn),
                .s_axi_awaddr  (gpio_awaddr[8:0]),
                .s_axi_awvalid (gpio_awvalid),
                .s_axi_awready (gpio_awready),
                .s_axi_wdata   (gpio_wdata),
                .s_axi_wstrb   (gpio_wstrb),
                .s_axi_wvalid  (gpio_wvalid),
                .s_axi_wready  (gpio_wready),
                .s_axi_bresp   (gpio_bresp),
                .s_axi_bvalid  (gpio_bvalid),
                .s_axi_bready  (gpio_bready),
                .s_axi_araddr  (gpio_araddr[8:0]),
                .s_axi_arvalid (gpio_arvalid),
                .s_axi_arready (gpio_arready),
                .s_axi_rdata   (gpio_rdata),
                .s_axi_rresp   (gpio_rresp),
                .s_axi_rvalid  (gpio_rvalid),
                .s_axi_rready  (gpio_rready),
                .gpio_io_i     (gpio_i)
            );
        end else if (GPIO_KIND == 1) begin : GEN_LED
            assign dig_value = 32'h0;

            axi_gpio_2 U_led (
                .s_axi_aclk    (aclk),
                .s_axi_aresetn (aresetn),
                .s_axi_awaddr  (gpio_awaddr[8:0]),
                .s_axi_awvalid (gpio_awvalid),
                .s_axi_awready (gpio_awready),
                .s_axi_wdata   (gpio_wdata),
                .s_axi_wstrb   (gpio_wstrb),
                .s_axi_wvalid  (gpio_wvalid),
                .s_axi_wready  (gpio_wready),
                .s_axi_bresp   (gpio_bresp),
                .s_axi_bvalid  (gpio_bvalid),
                .s_axi_bready  (gpio_bready),
                .s_axi_araddr  (gpio_araddr[8:0]),
                .s_axi_arvalid (gpio_arvalid),
                .s_axi_arready (gpio_arready),
                .s_axi_rdata   (gpio_rdata),
                .s_axi_rresp   (gpio_rresp),
                .s_axi_rvalid  (gpio_rvalid),
                .s_axi_rready  (gpio_rready),
                .gpio_io_o     (gpio_o)
            );
        end else begin : GEN_DIGLED
            assign gpio_o = 24'h0;

            axi_gpio_3 U_digled (
                .s_axi_aclk    (aclk),
                .s_axi_aresetn (aresetn),
                .s_axi_awaddr  (gpio_awaddr[8:0]),
                .s_axi_awvalid (gpio_awvalid),
                .s_axi_awready (gpio_awready),
                .s_axi_wdata   (gpio_wdata),
                .s_axi_wstrb   (gpio_wstrb),
                .s_axi_wvalid  (gpio_wvalid),
                .s_axi_wready  (gpio_wready),
                .s_axi_bresp   (gpio_bresp),
                .s_axi_bvalid  (gpio_bvalid),
                .s_axi_bready  (gpio_bready),
                .s_axi_araddr  (gpio_araddr[8:0]),
                .s_axi_arvalid (gpio_arvalid),
                .s_axi_arready (gpio_arready),
                .s_axi_rdata   (gpio_rdata),
                .s_axi_rresp   (gpio_rresp),
                .s_axi_rvalid  (gpio_rvalid),
                .s_axi_rready  (gpio_rready),
                .gpio_io_o     (dig_value)
            );
        end
    endgenerate

    axi_protocol_converter_0 U_gpio_converter (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awlen    (s_axi_awlen),
        .s_axi_awsize   (s_axi_awsize),
        .s_axi_awburst  (s_axi_awburst),
        .s_axi_awlock   (s_axi_awlock),
        .s_axi_awcache  (s_axi_awcache),
        .s_axi_awprot   (s_axi_awprot),
        .s_axi_awregion (s_axi_awregion),
        .s_axi_awqos    (s_axi_awqos),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wlast    (s_axi_wlast),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arlen    (s_axi_arlen),
        .s_axi_arsize   (s_axi_arsize),
        .s_axi_arburst  (s_axi_arburst),
        .s_axi_arlock   (s_axi_arlock),
        .s_axi_arcache  (s_axi_arcache),
        .s_axi_arprot   (s_axi_arprot),
        .s_axi_arregion (s_axi_arregion),
        .s_axi_arqos    (s_axi_arqos),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rlast    (s_axi_rlast),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .m_axi_awaddr   (gpio_awaddr),
        .m_axi_awprot   (),
        .m_axi_awvalid  (gpio_awvalid),
        .m_axi_awready  (gpio_awready),
        .m_axi_wdata    (gpio_wdata),
        .m_axi_wstrb    (gpio_wstrb),
        .m_axi_wvalid   (gpio_wvalid),
        .m_axi_wready   (gpio_wready),
        .m_axi_bresp    (gpio_bresp),
        .m_axi_bvalid   (gpio_bvalid),
        .m_axi_bready   (gpio_bready),
        .m_axi_araddr   (gpio_araddr),
        .m_axi_arprot   (),
        .m_axi_arvalid  (gpio_arvalid),
        .m_axi_arready  (gpio_arready),
        .m_axi_rdata    (gpio_rdata),
        .m_axi_rresp    (gpio_rresp),
        .m_axi_rvalid   (gpio_rvalid),
        .m_axi_rready   (gpio_rready)
    );

endmodule

module digled_scan(
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] value,
    output reg  [ 7:0] dig_en,
    output reg  [ 7:0] dig_seg
);

    reg [16:0] scan_counter;
    wire [2:0] scan_index = scan_counter[16:14];
    reg [3:0] digit;

    always @(posedge clk) begin
        if (rst)
            scan_counter <= 17'h0;
        else
            scan_counter <= scan_counter + 17'h1;
    end

    always @(*) begin
        dig_en = ~(8'b0000_0001 << scan_index);
        case (scan_index)
            3'd0: digit = value[ 3: 0];
            3'd1: digit = value[ 7: 4];
            3'd2: digit = value[11: 8];
            3'd3: digit = value[15:12];
            3'd4: digit = value[19:16];
            3'd5: digit = value[23:20];
            3'd6: digit = value[27:24];
            default: digit = value[31:28];
        endcase

        case (digit)
            4'h0: dig_seg = 8'h03;
            4'h1: dig_seg = 8'h9F;
            4'h2: dig_seg = 8'h25;
            4'h3: dig_seg = 8'h0D;
            4'h4: dig_seg = 8'h99;
            4'h5: dig_seg = 8'h49;
            4'h6: dig_seg = 8'h41;
            4'h7: dig_seg = 8'h1F;
            4'h8: dig_seg = 8'h01;
            4'h9: dig_seg = 8'h09;
            4'hA: dig_seg = 8'h11;
            4'hB: dig_seg = 8'hC1;
            4'hC: dig_seg = 8'h63;
            4'hD: dig_seg = 8'h85;
            4'hE: dig_seg = 8'h61;
            default: dig_seg = 8'h71;
        endcase
    end

endmodule
