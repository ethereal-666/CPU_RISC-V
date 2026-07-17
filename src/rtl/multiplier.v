`timescale 1ns / 1ps

module multiplier #(
    parameter WIDTH = 32
)(
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] x,
    input  wire [WIDTH-1:0] y,
    input  wire             start,
    output reg  [2*WIDTH-1:0] z,
    output wire             busy
);

    localparam O_WID = 2*WIDTH;

    reg [O_WID-1:0] multiplicand;
    reg [WIDTH-1:0] multiplier;
    reg [O_WID-1:0] product;
    reg [WIDTH  :0] count;
    reg              negative;
    reg              busy_r;

    wire [WIDTH-1:0] x_abs = x[WIDTH-1] ? (~x + 1'b1) : x;
    wire [WIDTH-1:0] y_abs = y[WIDTH-1] ? (~y + 1'b1) : y;
    wire [O_WID-1:0] product_next = multiplier[0] ?
                                          product + multiplicand : product;

    assign busy = busy_r;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            z            <= {O_WID{1'b0}};
            multiplicand <= {O_WID{1'b0}};
            multiplier   <= {WIDTH{1'b0}};
            product      <= {O_WID{1'b0}};
            count        <= {(WIDTH+1){1'b0}};
            negative     <= 1'b0;
            busy_r       <= 1'b0;
        end else if (start && !busy_r) begin
            multiplicand <= {{WIDTH{1'b0}}, x_abs};
            multiplier   <= y_abs;
            product      <= {O_WID{1'b0}};
            count        <= WIDTH;
            negative     <= x[WIDTH-1] ^ y[WIDTH-1];
            busy_r       <= 1'b1;
        end else if (busy_r) begin
            product      <= product_next;
            multiplicand <= multiplicand << 1;
            multiplier   <= multiplier >> 1;
            count        <= count - 1'b1;
            if (count == 1) begin
                z      <= negative ? (~product_next + 1'b1) : product_next;
                busy_r <= 1'b0;
            end
        end
    end

endmodule
