`timescale 1ns / 1ps

`include "defines.vh"

// 主存地址位宽：32bit
// Cache容量：1KB
// Cache块大小：128bit / 4 * 32bit
// Cache块个数：64

module ICache(
    input  wire         cpu_clk,
    input  wire         cpu_rst,        // high active
    // Interface to CPU
    input  wire         inst_rreq,      // 来自CPU的取指请求
    input  wire [31:0]  inst_addr,      // 来自CPU的取指地址
    output reg          inst_valid,     // 输出给CPU的指令有效信号（读指令命中）
    output reg  [31:0]  inst_out,       // 输出给CPU的指令
    // Interface to Read Bus
    input  wire         dev_rrdy,       // 主存就绪信号（高电平表示主存可接收ICache的读请求）
    output reg  [ 3:0]  cpu_ren,        // 输出给主存的读使能信号
    output reg  [31:0]  cpu_raddr,      // 输出给主存的读地址
    input  wire         dev_rvalid,     // 来自主存的数据有效信号
    input  wire [127:0] dev_rdata       // 来自主存的读数据
);

`ifdef ENABLE_ICACHE    /******** 不要修改此行代码 ********/

    // 1 KiB cache: address[9:4] is the index and address[3:0] is the
    // byte offset, so every remaining address bit belongs to the tag.
    localparam TAG_WIDTH    = 22;
    localparam STORED_TAG_WIDTH = 5;
    localparam INDEX_WIDTH  = 6;
    localparam OFFSET_WIDTH = 2;
    localparam LINE_WIDTH   = 134;

    localparam IDLE        = 2'b00;
    localparam LOOKUP_WAIT = 2'b01;
    localparam TAG_CHECK   = 2'b10;
    localparam REFILL      = 2'b11;

    reg [ 1:0] state;
    reg [ 1:0] nstat;
    reg [31:0] inst_addr_r;
    reg [63:0] valid_array;
    reg [TAG_WIDTH-1:0] tag_array [0:63];
    reg        refill_req_sent;

    wire [LINE_WIDTH-1:0]   cache_line_r;                  // 从ICache读出的Cache块
    wire [TAG_WIDTH-1:0]    tag_from_cpu   = inst_addr_r[31:10];    // 完整TAG字段
    wire [OFFSET_WIDTH-1:0] offset         = inst_addr_r[3:2];      // 32位字偏移量
    wire                    valid_bit      = valid_array[inst_addr_r[9:4]];    // Cache块的有效位
    wire [TAG_WIDTH-1:0]    tag_from_cache = tag_array[inst_addr_r[9:4]];

    wire hit         = (state == TAG_CHECK) & valid_bit & (tag_from_cpu == tag_from_cache);
    wire refill_done = (state == REFILL) & dev_rvalid;
    wire refill_req  = (state == REFILL) & ~refill_req_sent & dev_rrdy;

    wire [31:0] cache_word = (offset == 2'b00) ? cache_line_r[ 31:  0] :
                             (offset == 2'b01) ? cache_line_r[ 63: 32] :
                             (offset == 2'b10) ? cache_line_r[ 95: 64] :
                                                 cache_line_r[127: 96];

    wire [31:0] refill_word = (offset == 2'b00) ? dev_rdata[ 31:  0] :
                              (offset == 2'b01) ? dev_rdata[ 63: 32] :
                              (offset == 2'b10) ? dev_rdata[ 95: 64] :
                                                  dev_rdata[127: 96];

    always @(*) begin
        inst_valid = hit | refill_done;
    end

    always @(*) begin
        inst_out = refill_done ? refill_word : cache_word;
    end

    wire                   cache_we     = refill_done;          // ICache存储体的写使能信号
    wire [INDEX_WIDTH-1:0] cache_index  = ((state == IDLE) & inst_rreq) ?
                                          inst_addr[9:4] : inst_addr_r[9:4];
    // Preserve the existing 134-bit RAM IP.  The five embedded tag bits are
    // legacy storage only; all hit checks use the complete tag_array.
    wire [LINE_WIDTH-1:0]  cache_line_w =
        {1'b1, tag_from_cpu[STORED_TAG_WIDTH-1:0], dev_rdata};

    // ICache存储体：Block MEM IP核
    blk_mem_gen_1 U_isram (
        .clka   (cpu_clk),
        .wea    (cache_we),
        .addra  (cache_index),
        .dina   (cache_line_w),
        .douta  (cache_line_r)
    );

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            state <= IDLE;
        end else begin
            state <= nstat;
        end
    end

    always @(*) begin
        case (state)
            IDLE: begin
                nstat = inst_rreq ? LOOKUP_WAIT : IDLE;
            end
            LOOKUP_WAIT: begin
                // blk_mem_gen_1 is synchronous-read.  Wait one full cycle
                // after selecting the index before checking tag/data.
                nstat = TAG_CHECK;
            end
            TAG_CHECK: begin
                nstat = hit ? IDLE : REFILL;
            end
            REFILL: begin
                nstat = dev_rvalid ? IDLE : REFILL;
            end
            default: begin
                nstat = IDLE;
            end
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            inst_addr_r <= 32'h0;
        end else if ((state == IDLE) & inst_rreq) begin
            inst_addr_r <= inst_addr;
        end else begin
            inst_addr_r <= inst_addr_r;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            valid_array <= 64'h0;
        end else if (cache_we) begin
            valid_array[inst_addr_r[9:4]] <= 1'b1;
        end else begin
            valid_array <= valid_array;
        end
    end

    // tag_array need not be reset because valid_array is cleared on reset.
    always @(posedge cpu_clk) begin
        if (cache_we) begin
            tag_array[inst_addr_r[9:4]] <= tag_from_cpu;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            refill_req_sent <= 1'b0;
        end else if (state != REFILL) begin
            refill_req_sent <= 1'b0;
        end else if (dev_rvalid) begin
            refill_req_sent <= 1'b0;
        end else if (refill_req) begin
            refill_req_sent <= 1'b1;
        end else begin
            refill_req_sent <= refill_req_sent;
        end
    end

    always @(*) begin
        cpu_ren   = refill_req ? 4'hF : 4'h0;
        cpu_raddr = {inst_addr_r[31:4], 4'b0};
    end



    /******** 不要修改以下代码 ********/
`else

    localparam IDLE  = 2'b00;
    localparam STAT0 = 2'b01;
    localparam STAT1 = 2'b11;
    reg [1:0] state, nstat;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        state <= cpu_rst ? IDLE : nstat;
    end

    always @(*) begin
        case (state)
            IDLE:    nstat = inst_rreq ? (dev_rrdy ? STAT1 : STAT0) : IDLE;
            STAT0:   nstat = dev_rrdy ? STAT1 : STAT0;
            STAT1:   nstat = dev_rvalid ? IDLE : STAT1;
            default: nstat = IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            inst_valid <= 1'b0;
            cpu_ren    <= 4'h0;
        end else begin
            case (state)
                IDLE: begin
                    inst_valid <= 1'b0;
                    cpu_ren    <= (inst_rreq & dev_rrdy) ? 4'hF : 4'h0;
                    cpu_raddr  <= inst_rreq ? inst_addr : 32'h0;
                end
                STAT0: begin
                    cpu_ren    <= dev_rrdy ? 4'hF : 4'h0;
                end
                STAT1: begin
                    cpu_ren    <= 4'h0;
                    inst_valid <= dev_rvalid ? 1'b1 : 1'b0;
                    inst_out   <= dev_rvalid ? dev_rdata[31:0] : 32'h0;
                end
                default: begin
                    inst_valid <= 1'b0;
                    cpu_ren    <= 4'h0;
                end
            endcase
        end
    end

`endif

endmodule
