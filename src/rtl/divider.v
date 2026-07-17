`timescale 1ns / 1ps

module divider #(
    parameter WIDTH = 32,
    parameter SIGNED_OP = 1'b0
)(
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] x,
    input  wire [WIDTH-1:0] y,
    input  wire             start,
    output reg  [WIDTH-1:0] z,
    output reg  [WIDTH-1:0] r,
    output reg              busy
);

    reg [WIDTH-1:0] dividend;
    reg [WIDTH-1:0] divisor;
    reg [WIDTH-1:0] quotient;
    reg [WIDTH  :0] remainder;
    reg [WIDTH  :0] count;
    reg              quotient_negative;
    reg              remainder_negative;

    wire x_negative = SIGNED_OP && x[WIDTH-1];
    wire y_negative = SIGNED_OP && y[WIDTH-1];
    wire [WIDTH-1:0] x_abs = x_negative ? (~x + 1'b1) : x;
    wire [WIDTH-1:0] y_abs = y_negative ? (~y + 1'b1) : y;
    wire [WIDTH  :0] remainder_shift = {remainder[WIDTH-1:0], dividend[WIDTH-1]};
    wire             remainder_ge_divisor = remainder_shift >= {1'b0, divisor};

    reg [WIDTH  :0] remainder_next;
    reg [WIDTH-1:0] quotient_next;

    always @(*) begin
        if (remainder_ge_divisor) begin
            remainder_next = remainder_shift - {1'b0, divisor};
        end else begin
            remainder_next = remainder_shift;
        end
    end

    always @(*) begin
        quotient_next = {quotient[WIDTH-2:0], remainder_ge_divisor};
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            z <= {WIDTH{1'b0}};
        end else if (start && !busy && (y_abs == {WIDTH{1'b0}})) begin
            z <= {WIDTH{1'b1}};
        end else if (busy && (divisor != {WIDTH{1'b0}}) && (count == 1)) begin
            z <= quotient_negative ? (~quotient_next + 1'b1) : quotient_next;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            r <= {WIDTH{1'b0}};
        end else if (start && !busy && (y_abs == {WIDTH{1'b0}})) begin
            r <= x;
        end else if (busy && (divisor != {WIDTH{1'b0}}) && (count == 1)) begin
            r <= remainder_negative ?
                    (~remainder_next[WIDTH-1:0] + 1'b1) :
                      remainder_next[WIDTH-1:0];
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dividend <= {WIDTH{1'b0}};
        end else if (start && !busy) begin
            dividend <= x_abs;
        end else if (busy && (divisor != {WIDTH{1'b0}})) begin
            dividend <= dividend << 1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            divisor <= {WIDTH{1'b0}};
        end else if (start && !busy) begin
            divisor <= y_abs;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            quotient <= {WIDTH{1'b0}};
        end else if (start && !busy) begin
            quotient <= {WIDTH{1'b0}};
        end else if (busy && (divisor != {WIDTH{1'b0}})) begin
            quotient <= quotient_next;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            remainder <= {(WIDTH+1){1'b0}};
        end else if (start && !busy) begin
            remainder <= {(WIDTH+1){1'b0}};
        end else if (busy && (divisor != {WIDTH{1'b0}})) begin
            remainder <= remainder_next;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count <= {(WIDTH+1){1'b0}};
        end else if (start && !busy && (y_abs == {WIDTH{1'b0}})) begin
            count <= 1;
        end else if (start && !busy) begin
            count <= WIDTH;
        end else if (busy) begin
            count <= count - 1'b1;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            quotient_negative <= 1'b0;
        end else if (start && !busy) begin
            quotient_negative <= x_negative ^ y_negative;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            remainder_negative <= 1'b0;
        end else if (start && !busy) begin
            remainder_negative <= x_negative;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy <= 1'b0;
        end else if (start && !busy) begin
            busy <= 1'b1;
        end else if (busy && (divisor == {WIDTH{1'b0}})) begin
            busy <= 1'b0;
        end else if (busy && (count == 1)) begin
            busy <= 1'b0;
        end
    end

endmodule
