`timescale 1ns / 1ps

`include "defines.vh"

// 主存地址位宽：32bit
// Cache容量：1KB
// Cache块大小：128bit (4*32bit)
// Cache块个数：64

module DCache(
    input  wire         cpu_clk,
    input  wire         cpu_rst,        // high active
    // Interface to CPU
    input  wire [ 3:0]  data_ren,       // 来自CPU的读使能信号
    input  wire [31:0]  data_addr,      // 来自CPU的地址（读、写共用）
    output reg          data_valid,     // 输出给CPU的数据有效信号
    output reg  [31:0]  data_rdata,     // 输出给CPU的读数据
    input  wire [ 3:0]  data_wen,       // 来自CPU的写使能信号
    input  wire [31:0]  data_wdata,     // 来自CPU的写数据
    output reg          data_wresp,     // 输出给CPU的写响应（高电平表示DCache已完成写操作）
    // Interface to Write Bus
    input  wire         dev_wrdy,       // 主存/外设的写就绪信号（高电平表示主存/外设可接收DCache的写请求）
    output reg  [ 3:0]  cpu_wen,        // 输出给主存/外设的写使能信号
    output reg  [31:0]  cpu_waddr,      // 输出给主存/外设的写地址
    output reg  [31:0]  cpu_wdata,      // 输出给主存/外设的写数据
    // Interface to Read Bus
    input  wire         dev_rrdy,       // 主存/外设的读就绪信号（高电平表示主存/外设可接收DCache的读请求）
    output reg  [ 3:0]  cpu_ren,        // 输出给主存/外设的读使能信号
    output reg  [31:0]  cpu_raddr,      // 输出给主存/外设的读地址
    input  wire         dev_rvalid,     // 来自主存/外设的数据有效信号
    input  wire [127:0] dev_rdata       // 来自主存/外设的读数据
);

    // Peripherals access should be uncached.
    wire uncached = (data_addr[31:16] == 16'hFFFF) &
                    ((data_ren != 4'h0) | (data_wen != 4'h0));

`ifdef ENABLE_DCACHE    /******** 不要修改此行代码 ********/

    // 1 KiB cache: address[9:4] is the index and address[3:0] is the
    // byte offset, so every remaining address bit belongs to the tag.
    localparam TAG_WIDTH    = 22;
    localparam STORED_TAG_WIDTH = 5;
    localparam INDEX_WIDTH  = 6;
    localparam OFFSET_WIDTH = 2;
    localparam LINE_WIDTH   = 134;

    localparam R_IDLE        = 2'b00;
    localparam R_LOOKUP_WAIT = 2'b01;
    localparam R_TAG_CHECK   = 2'b10;
    localparam R_REFILL      = 2'b11;

    localparam W_IDLE        = 2'b00;
    localparam W_LOOKUP_WAIT = 2'b01;
    localparam W_TAG_CHECK   = 2'b10;
    localparam W_WRITE       = 2'b11;

    reg [ 1:0] r_state;
    reg [ 1:0] r_nstat;
    reg [31:0] r_addr_r;
    reg [ 3:0] r_ren_r;
    reg        r_uncached_r;
    reg        r_refill_req_sent;

    reg [ 1:0] w_state;
    reg [ 1:0] w_nstat;
    reg [31:0] w_addr_r;
    reg [31:0] w_data_r;
    reg [ 3:0] w_wen_r;
    reg        w_uncached_r;
    reg        w_req_sent;

    reg [63:0] valid_array;
    reg [TAG_WIDTH-1:0] tag_array [0:63];

    wire [LINE_WIDTH-1:0]   cache_line_r;                  // 从DCache读出的Cache块
    wire [TAG_WIDTH-1:0]    tag_from_cpu   = r_addr_r[31:10];    // 完整TAG字段
    wire [OFFSET_WIDTH-1:0] offset         = r_addr_r[3:2];      // 32位字偏移量
    wire                    valid_bit      = valid_array[r_addr_r[9:4]];    // Cache块的有效位
    wire [TAG_WIDTH-1:0]    tag_from_cache = tag_array[r_addr_r[9:4]];

    wire [TAG_WIDTH-1:0]    w_tag_from_cpu = w_addr_r[31:10];
    wire [OFFSET_WIDTH-1:0] w_offset       = w_addr_r[3:2];
    wire                    w_valid_bit    = valid_array[w_addr_r[9:4]];
    wire [TAG_WIDTH-1:0]    w_tag_from_cache = tag_array[w_addr_r[9:4]];

    wire hit_r = (r_state == R_TAG_CHECK) & ~r_uncached_r & valid_bit &
                 (tag_from_cpu == tag_from_cache);        // 读命中
    wire hit_w = (w_state == W_TAG_CHECK) & ~w_uncached_r & w_valid_bit &
                 (w_tag_from_cpu == w_tag_from_cache);    // 写命中

    wire read_refill_done = (r_state == R_REFILL) & dev_rvalid;
    wire read_bus_req     = (r_state == R_REFILL) & ~r_refill_req_sent & dev_rrdy;
    wire write_bus_req    = (w_state == W_WRITE) & ~w_req_sent & dev_wrdy;
    wire write_done       = (w_state == W_WRITE) & w_req_sent & dev_wrdy & (cpu_wen == 4'h0);

    wire [31:0] cache_word = (offset == 2'b00) ? cache_line_r[ 31:  0] :
                             (offset == 2'b01) ? cache_line_r[ 63: 32] :
                             (offset == 2'b10) ? cache_line_r[ 95: 64] :
                                                 cache_line_r[127: 96];

    wire [31:0] refill_word = (offset == 2'b00) ? dev_rdata[ 31:  0] :
                              (offset == 2'b01) ? dev_rdata[ 63: 32] :
                              (offset == 2'b10) ? dev_rdata[ 95: 64] :
                                                  dev_rdata[127: 96];

    always @(*) begin
        data_valid = cpu_rst ? 1'b0 : (hit_r | read_refill_done);
    end

    always @(*) begin
        data_rdata = cpu_rst ? 32'h0 :
                     (read_refill_done ? (r_uncached_r ? dev_rdata[31:0] : refill_word) : cache_word);
    end

    reg  [LINE_WIDTH-1:0]  wr_cache_data;                 // 写命中时写入DCache的数据块
    wire                  read_cache_we  = read_refill_done & ~r_uncached_r;
    wire                  write_cache_we = hit_w;
    wire                  cache_we       = read_cache_we | write_cache_we;     // DCache存储体的写使能信号
    wire [INDEX_WIDTH-1:0] cache_index    = read_cache_we ? r_addr_r[9:4] :
                                           (write_cache_we ? w_addr_r[9:4] :
                                           (((r_state == R_IDLE) & (|data_ren)) ? data_addr[9:4] :
                                           (((w_state == W_IDLE) & (|data_wen)) ? data_addr[9:4] :
                                           ((r_state != R_IDLE) ? r_addr_r[9:4] : w_addr_r[9:4]))));
    // Preserve the existing 134-bit RAM IP.  The five embedded tag bits are
    // legacy storage only; all hit checks use the complete tag_array.
    wire [LINE_WIDTH-1:0]  cache_line_w =
        read_cache_we ? {1'b1, tag_from_cpu[STORED_TAG_WIDTH-1:0], dev_rdata} : wr_cache_data;

    // DCache存储体：Block MEM IP核
    blk_mem_gen_1 U_dsram (
        .clka   (cpu_clk),
        .wea    (cache_we),
        .addra  (cache_index),
        .dina   (cache_line_w),
        .douta  (cache_line_r)
    );

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            r_state <= R_IDLE;
        end else begin
            r_state <= r_nstat;
        end
    end

    always @(*) begin
        case (r_state)
            R_IDLE: begin
                r_nstat = (|data_ren) ? R_LOOKUP_WAIT : R_IDLE;
            end
            R_LOOKUP_WAIT: begin
                r_nstat = R_TAG_CHECK;
            end
            R_TAG_CHECK: begin
                r_nstat = hit_r ? R_IDLE : R_REFILL;
            end
            R_REFILL: begin
                r_nstat = dev_rvalid ? R_IDLE : R_REFILL;
            end
            default: begin
                r_nstat = R_IDLE;
            end
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            r_addr_r <= 32'h0;
        end else if ((r_state == R_IDLE) & (|data_ren)) begin
            r_addr_r <= data_addr;
        end else begin
            r_addr_r <= r_addr_r;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            r_ren_r <= 4'h0;
        end else if ((r_state == R_IDLE) & (|data_ren)) begin
            r_ren_r <= data_ren;
        end else begin
            r_ren_r <= r_ren_r;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            r_uncached_r <= 1'b0;
        end else if ((r_state == R_IDLE) & (|data_ren)) begin
            r_uncached_r <= uncached;
        end else begin
            r_uncached_r <= r_uncached_r;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            r_refill_req_sent <= 1'b0;
        end else if (r_state != R_REFILL) begin
            r_refill_req_sent <= 1'b0;
        end else if (dev_rvalid) begin
            r_refill_req_sent <= 1'b0;
        end else if (read_bus_req) begin
            r_refill_req_sent <= 1'b1;
        end else begin
            r_refill_req_sent <= r_refill_req_sent;
        end
    end

    always @(*) begin
        cpu_ren   = read_bus_req ? (r_uncached_r ? r_ren_r : 4'hF) : 4'h0;
        cpu_raddr = r_uncached_r ? r_addr_r : {r_addr_r[31:4], 4'b0};
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            valid_array <= 64'h0;
        end else if (read_cache_we) begin
            valid_array[r_addr_r[9:4]] <= 1'b1;
        end else begin
            valid_array <= valid_array;
        end
    end

    // tag_array need not be reset because valid_array is cleared on reset.
    always @(posedge cpu_clk) begin
        if (read_cache_we) begin
            tag_array[r_addr_r[9:4]] <= tag_from_cpu;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            w_state <= W_IDLE;
        end else begin
            w_state <= w_nstat;
        end
    end

    always @(*) begin
        case (w_state)
            W_IDLE: begin
                w_nstat = (|data_wen) ? W_LOOKUP_WAIT : W_IDLE;
            end
            W_LOOKUP_WAIT: begin
                w_nstat = W_TAG_CHECK;
            end
            W_TAG_CHECK: begin
                w_nstat = W_WRITE;
            end
            W_WRITE: begin
                w_nstat = write_done ? W_IDLE : W_WRITE;
            end
            default: begin
                w_nstat = W_IDLE;
            end
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            w_addr_r <= 32'h0;
        end else if ((w_state == W_IDLE) & (|data_wen)) begin
            w_addr_r <= data_addr;
        end else begin
            w_addr_r <= w_addr_r;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            w_data_r <= 32'h0;
        end else if ((w_state == W_IDLE) & (|data_wen)) begin
            w_data_r <= data_wdata;
        end else begin
            w_data_r <= w_data_r;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            w_wen_r <= 4'h0;
        end else if ((w_state == W_IDLE) & (|data_wen)) begin
            w_wen_r <= data_wen;
        end else begin
            w_wen_r <= w_wen_r;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            w_uncached_r <= 1'b0;
        end else if ((w_state == W_IDLE) & (|data_wen)) begin
            w_uncached_r <= uncached;
        end else begin
            w_uncached_r <= w_uncached_r;
        end
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            w_req_sent <= 1'b0;
        end else if (w_state != W_WRITE) begin
            w_req_sent <= 1'b0;
        end else if (write_done) begin
            w_req_sent <= 1'b0;
        end else if (write_bus_req) begin
            w_req_sent <= 1'b1;
        end else begin
            w_req_sent <= w_req_sent;
        end
    end

    always @(*) begin
        cpu_wen   = write_bus_req ? w_wen_r : 4'h0;
        cpu_waddr = w_addr_r;
        cpu_wdata = w_data_r;
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_wresp <= 1'b0;
        end else begin
            data_wresp <= write_done;
        end
    end

    wire [31:0] old_write_word = (w_offset == 2'b00) ? cache_line_r[ 31:  0] :
                                 (w_offset == 2'b01) ? cache_line_r[ 63: 32] :
                                 (w_offset == 2'b10) ? cache_line_r[ 95: 64] :
                                                       cache_line_r[127: 96];

    wire [31:0] new_write_word = {
        w_wen_r[3] ? w_data_r[31:24] : old_write_word[31:24],
        w_wen_r[2] ? w_data_r[23:16] : old_write_word[23:16],
        w_wen_r[1] ? w_data_r[15: 8] : old_write_word[15: 8],
        w_wen_r[0] ? w_data_r[ 7: 0] : old_write_word[ 7: 0]
    };

    wire [127:0] new_cache_data = (w_offset == 2'b00) ? {cache_line_r[127: 32], new_write_word} :
                                  (w_offset == 2'b01) ? {cache_line_r[127: 64], new_write_word, cache_line_r[31:0]} :
                                  (w_offset == 2'b10) ? {cache_line_r[127: 96], new_write_word, cache_line_r[63:0]} :
                                                        {new_write_word, cache_line_r[95:0]};

    always @(*) begin
        wr_cache_data = {1'b1, w_tag_from_cpu[STORED_TAG_WIDTH-1:0], new_cache_data};
    end

    /******** 不要修改以下代码 ********/
`else

    localparam R_IDLE  = 2'b00;
    localparam R_STAT0 = 2'b01;
    localparam R_STAT1 = 2'b11;
    reg [1:0] r_state, r_nstat;
    reg [3:0] ren_r;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        r_state <= cpu_rst ? R_IDLE : r_nstat;
    end

    always @(*) begin
        case (r_state)
            R_IDLE:  r_nstat = (|data_ren) ? (dev_rrdy ? R_STAT1 : R_STAT0) : R_IDLE;
            R_STAT0: r_nstat = dev_rrdy ? R_STAT1 : R_STAT0;
            R_STAT1: r_nstat = dev_rvalid ? R_IDLE : R_STAT1;
            default: r_nstat = R_IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_valid <= 1'b0;
            cpu_ren    <= 4'h0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    data_valid <= 1'b0;

                    if (|data_ren) begin
                        if (dev_rrdy)
                            cpu_ren <= data_ren;
                        else
                            ren_r   <= data_ren;

                        cpu_raddr <= data_addr;
                    end else
                        cpu_ren   <= 4'h0;
                end
                R_STAT0: begin
                    cpu_ren    <= dev_rrdy ? ren_r : 4'h0;
                end   
                R_STAT1: begin
                    cpu_ren    <= 4'h0;
                    data_valid <= dev_rvalid ? 1'b1 : 1'b0;
                    data_rdata <= dev_rvalid ? dev_rdata : 32'h0;
                end
                default: begin
                    data_valid <= 1'b0;
                    cpu_ren    <= 4'h0;
                end 
            endcase
        end
    end

    localparam W_IDLE  = 2'b00;
    localparam W_STAT0 = 2'b01;
    localparam W_STAT1 = 2'b11;
    reg  [1:0] w_state, w_nstat;
    reg  [3:0] wen_r;
    wire       wr_resp = dev_wrdy & (cpu_wen == 4'h0) ? 1'b1 : 1'b0;

    always @(posedge cpu_clk or posedge cpu_rst) begin
        w_state <= cpu_rst ? W_IDLE : w_nstat;
    end

    always @(*) begin
        case (w_state)
            W_IDLE:  w_nstat = (|data_wen) ? (dev_wrdy ? W_STAT1 : W_STAT0) : W_IDLE;
            W_STAT0: w_nstat = dev_wrdy ? W_STAT1 : W_STAT0;
            W_STAT1: w_nstat = wr_resp ? W_IDLE : W_STAT1;
            default: w_nstat = W_IDLE;
        endcase
    end

    always @(posedge cpu_clk or posedge cpu_rst) begin
        if (cpu_rst) begin
            data_wresp <= 1'b0;
            cpu_wen    <= 4'h0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    data_wresp <= 1'b0;

                    if (|data_wen) begin
                        if (dev_wrdy)
                            cpu_wen <= data_wen;
                        else
                            wen_r   <= data_wen;

                        cpu_waddr  <= data_addr;
                        cpu_wdata  <= data_wdata;
                    end else
                        cpu_wen    <= 4'h0;
                end
                W_STAT0: begin
                    cpu_wen    <= dev_wrdy ? wen_r : 4'h0;
                end
                W_STAT1: begin
                    cpu_wen    <= 4'h0;
                    data_wresp <= wr_resp ? 1'b1 : 1'b0;
                end
                default: begin
                    data_wresp <= 1'b0;
                    cpu_wen    <= 4'h0;
                end
            endcase
        end
    end

`endif

endmodule
