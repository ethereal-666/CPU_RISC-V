`timescale 1ns / 1ps

`include "defines.vh"

module axi_master(
    input  wire         aclk,
    input  wire         areset,     // high active

    // ICache Interface
    output wire         ic_dev_rrdy,
    input  wire         ic_cpu_ren,
    input  wire [31:0]  ic_cpu_raddr,
    output reg          ic_dev_rvalid,
    output reg  [`IC_BLK_SIZE-1:0]  ic_dev_rdata,
    // DCache Interface
    output wire         dc_dev_wrdy,
    input  wire [ 3:0]  dc_cpu_wen,
    input  wire [31:0]  dc_cpu_waddr,
    input  wire [31:0]  dc_cpu_wdata,
    output wire         dc_dev_rrdy,
    input  wire         dc_cpu_ren,
    input  wire [31:0]  dc_cpu_raddr,
    output reg          dc_dev_rvalid,
    output reg  [`DC_BLK_SIZE-1:0]  dc_dev_rdata,

    // AXI4 Master Interface
    // write address channel
    output reg  [31:0]  m_axi_awaddr,
    output reg  [ 7:0]  m_axi_awlen,
    output reg  [ 2:0]  m_axi_awsize,
    output reg  [ 1:0]  m_axi_awburst,
    output reg          m_axi_awvalid,
    input  wire         m_axi_awready,
    // write data channel
    output reg  [31:0]  m_axi_wdata,
    output reg  [ 3:0]  m_axi_wstrb,
    output reg          m_axi_wlast,
    output reg          m_axi_wvalid,
    input  wire         m_axi_wready,
    // write response channel
    output reg          m_axi_bready,
    input  wire [ 1:0]  m_axi_bresp,
    input  wire         m_axi_bvalid,
    // read address channel
    output reg  [31:0]  m_axi_araddr,
    output reg  [ 7:0]  m_axi_arlen,
    output reg  [ 2:0]  m_axi_arsize,
    output reg  [ 1:0]  m_axi_arburst,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    // read data channel
    output reg          m_axi_rready,
    input  wire [31:0]  m_axi_rdata,
    input  wire [ 1:0]  m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid
);

    localparam [2:0] S_IDLE   = 3'b000;
    localparam [2:0] S_R_ADDR = 3'b001;
    localparam [2:0] S_R_DATA = 3'b010;
    localparam [2:0] S_W_SEND = 3'b011;
    localparam [2:0] S_W_RESP = 3'b100;

    localparam       R_OWNER_IC = 1'b0;
    localparam       R_OWNER_DC = 1'b1;

    reg [  2:0] state;
    reg         r_owner;
    reg [  1:0] r_beat;
    reg [127:0] rdata_buffer;

    // A data read has higher priority than an instruction fetch.  If both
    // requests are accepted together, preserve the instruction request and
    // issue it immediately after the data read finishes.
    reg         pending_ic_req;
    reg [ 31:0] pending_ic_addr;

    // AW and W are independent AXI channels.  These flags remember a
    // completed channel while the other one is still waiting for READY.
    reg         aw_done;
    reg         w_done;

    // Cache requests are accepted only while the arbiter is truly idle.
    // Combinational READY prevents another cache from sampling a stale
    // registered high value on the edge where one request wins arbitration.
    assign ic_dev_rrdy = (state == S_IDLE);
    assign dc_dev_rrdy = (state == S_IDLE);
    assign dc_dev_wrdy = (state == S_IDLE);

    wire [127:0] rdata_with_current =
        (r_beat == 2'd0) ? {rdata_buffer[127: 32], m_axi_rdata} :
        (r_beat == 2'd1) ? {rdata_buffer[127: 64], m_axi_rdata,
                            rdata_buffer[ 31:  0]} :
        (r_beat == 2'd2) ? {rdata_buffer[127: 96], m_axi_rdata,
                            rdata_buffer[ 63:  0]} :
                           {m_axi_rdata, rdata_buffer[95:0]};

    // A single controller serializes writes and reads.  Its arbitration order
    // follows the lab guide: data write, data read, then instruction read.
    always @(posedge aclk or posedge areset) begin
        if (areset) begin
            state            <= S_IDLE;
            r_owner          <= R_OWNER_IC;
            r_beat           <= 2'd0;
            rdata_buffer     <= 128'h0;
            pending_ic_req   <= 1'b0;
            pending_ic_addr  <= 32'h0;
            aw_done          <= 1'b0;
            w_done           <= 1'b0;

            ic_dev_rvalid    <= 1'b0;
            ic_dev_rdata     <= {`IC_BLK_SIZE{1'b0}};
            dc_dev_rvalid    <= 1'b0;
            dc_dev_rdata     <= {`DC_BLK_SIZE{1'b0}};

            m_axi_awaddr     <= 32'h0;
            m_axi_awlen      <= 8'h0;
            m_axi_awsize     <= 3'd2;
            m_axi_awburst    <= 2'b01;
            m_axi_awvalid    <= 1'b0;
            m_axi_wdata      <= 32'h0;
            m_axi_wstrb      <= 4'h0;
            m_axi_wlast      <= 1'b0;
            m_axi_wvalid     <= 1'b0;
            m_axi_bready     <= 1'b0;

            m_axi_araddr     <= 32'h0;
            m_axi_arlen      <= 8'h0;
            m_axi_arsize     <= 3'd2;
            m_axi_arburst    <= 2'b01;
            m_axi_arvalid    <= 1'b0;
            m_axi_rready     <= 1'b1;
        end else begin
            // Read responses to a Cache are one-cycle pulses.  RREADY may
            // remain asserted permanently for this single-outstanding master.
            ic_dev_rvalid <= 1'b0;
            dc_dev_rvalid <= 1'b0;
            m_axi_rready  <= 1'b1;

            case (state)
                S_IDLE: begin
                    m_axi_arvalid <= 1'b0;
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_wlast   <= 1'b0;
                    m_axi_bready  <= 1'b0;

                    if (|dc_cpu_wen) begin
                        m_axi_awaddr    <= {dc_cpu_waddr[31:2], 2'b00};
                        m_axi_awlen     <= 8'd0;
                        m_axi_awsize    <= 3'd2;
                        m_axi_awburst   <= 2'b01;
                        m_axi_awvalid   <= 1'b1;
                        m_axi_wdata     <= dc_cpu_wdata;
                        m_axi_wstrb     <= dc_cpu_wen;
                        m_axi_wlast     <= 1'b1;
                        m_axi_wvalid    <= 1'b1;
                        aw_done         <= 1'b0;
                        w_done          <= 1'b0;
                        state           <= S_W_SEND;

                        if (ic_cpu_ren) begin
                            pending_ic_req  <= 1'b1;
                            pending_ic_addr <= ic_cpu_raddr;
                        end else begin
                            pending_ic_req  <= 1'b0;
                        end
                    end else if (dc_cpu_ren) begin
                        r_owner         <= R_OWNER_DC;
                        r_beat          <= 2'd0;
                        rdata_buffer    <= 128'h0;
                        m_axi_araddr    <= {dc_cpu_raddr[31:2], 2'b00};
                        // MMIO registers are single-beat accesses.  Sending
                        // a cache-line burst to the 16-byte UARTLite window
                        // can wrap onto RX FIFO and consume queued bytes.
                        m_axi_arlen     <= (dc_cpu_raddr[31:16] == 16'hFFFF) ?
                                           8'd0 : (`DC_BLK_LEN - 1);
                        m_axi_arsize    <= 3'd2;
                        m_axi_arburst   <= 2'b01;
                        m_axi_arvalid   <= 1'b1;
                        state           <= S_R_ADDR;

                        if (ic_cpu_ren) begin
                            pending_ic_req  <= 1'b1;
                            pending_ic_addr <= ic_cpu_raddr;
                        end else begin
                            pending_ic_req  <= 1'b0;
                        end
                    end else if (ic_cpu_ren) begin
                        r_owner         <= R_OWNER_IC;
                        r_beat          <= 2'd0;
                        rdata_buffer    <= 128'h0;
                        m_axi_araddr    <= {ic_cpu_raddr[31:2], 2'b00};
                        m_axi_arlen     <= `IC_BLK_LEN - 1;
                        m_axi_arsize    <= 3'd2;
                        m_axi_arburst   <= 2'b01;
                        m_axi_arvalid   <= 1'b1;
                        pending_ic_req  <= 1'b0;
                        state           <= S_R_ADDR;
                    end
                end

                S_R_ADDR: begin

                    // AXI requires ARVALID and all address information to
                    // remain stable until the slave raises ARREADY.
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        state         <= S_R_DATA;
                    end
                end

                S_R_DATA: begin

                    if (m_axi_rvalid) begin
                        if (m_axi_rlast) begin
                            if (r_owner == R_OWNER_DC) begin
                                dc_dev_rdata  <= rdata_with_current[`DC_BLK_SIZE-1:0];
                                dc_dev_rvalid <= 1'b1;
                            end else begin
                                ic_dev_rdata  <= rdata_with_current[`IC_BLK_SIZE-1:0];
                                ic_dev_rvalid <= 1'b1;
                            end

                            r_beat       <= 2'd0;
                            rdata_buffer <= 128'h0;

                            if ((r_owner == R_OWNER_DC) && pending_ic_req) begin
                                r_owner         <= R_OWNER_IC;
                                m_axi_araddr    <= {pending_ic_addr[31:2], 2'b00};
                                m_axi_arlen     <= `IC_BLK_LEN - 1;
                                m_axi_arsize    <= 3'd2;
                                m_axi_arburst   <= 2'b01;
                                m_axi_arvalid   <= 1'b1;
                                pending_ic_req  <= 1'b0;
                                state           <= S_R_ADDR;
                            end else begin
                                state       <= S_IDLE;
                            end
                        end else begin
                            rdata_buffer <= rdata_with_current;
                            r_beat       <= r_beat + 1'b1;
                        end
                    end
                end

                S_W_SEND: begin
                    m_axi_bready <= 1'b0;

                    // VALID and its payload stay stable until that channel's
                    // handshake.  AW and W may finish in either order.
                    if (m_axi_awvalid && m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        aw_done       <= 1'b1;
                    end
                    if (m_axi_wvalid && m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        m_axi_wlast  <= 1'b0;
                        w_done       <= 1'b1;
                    end

                    if ((aw_done || (m_axi_awvalid && m_axi_awready)) &&
                        (w_done  || (m_axi_wvalid  && m_axi_wready))) begin
                        m_axi_bready <= 1'b1;
                        state        <= S_W_RESP;
                    end
                end

                S_W_RESP: begin
                    m_axi_awvalid <= 1'b0;
                    m_axi_wvalid  <= 1'b0;
                    m_axi_wlast   <= 1'b0;

                    if (m_axi_bvalid && m_axi_bready) begin
                        m_axi_bready <= 1'b0;
                        aw_done      <= 1'b0;
                        w_done       <= 1'b0;

                        // Reasserting write-ready completes the DCache-side
                        // request/response protocol after the AXI B response.

                        if (pending_ic_req) begin
                            r_owner         <= R_OWNER_IC;
                            r_beat          <= 2'd0;
                            rdata_buffer    <= 128'h0;
                            m_axi_araddr    <= {pending_ic_addr[31:2], 2'b00};
                            m_axi_arlen     <= `IC_BLK_LEN - 1;
                            m_axi_arsize    <= 3'd2;
                            m_axi_arburst   <= 2'b01;
                            m_axi_arvalid   <= 1'b1;
                            pending_ic_req  <= 1'b0;
                            state           <= S_R_ADDR;
                        end else begin
                            state       <= S_IDLE;
                        end
                    end
                end

                default: begin
                    state            <= S_IDLE;
                    pending_ic_req   <= 1'b0;
                    m_axi_arvalid    <= 1'b0;
                    m_axi_awvalid    <= 1'b0;
                    m_axi_wvalid     <= 1'b0;
                    m_axi_wlast      <= 1'b0;
                    m_axi_bready     <= 1'b0;
                end
            endcase
        end
    end


endmodule
