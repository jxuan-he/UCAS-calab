// Unsigned iterative divider with the same stream ports used by the CPU.
// One request is accepted at a time; EXE remains stalled until tvalid returns.
module div_gen(
    input  wire        aclk,
    input  wire        s_axis_dividend_tvalid,
    input  wire [31:0] s_axis_dividend_tdata,
    input  wire        s_axis_divisor_tvalid,
    input  wire [31:0] s_axis_divisor_tdata,
    output reg         m_axis_dout_tvalid,
    output reg  [63:0] m_axis_dout_tdata
);
reg [31:0] divisor;
reg [31:0] quotient;
reg [32:0] remainder;
reg [5:0]  count;
wire [32:0] shifted = {remainder[31:0], quotient[31]};
wire subtract = shifted >= {1'b0, divisor};
wire [32:0] next_remainder = subtract ? shifted - {1'b0, divisor} : shifted;
wire [31:0] next_quotient = {quotient[30:0], subtract};

initial begin
    divisor = 0;
    quotient = 0;
    remainder = 0;
    count = 0;
    m_axis_dout_tvalid = 0;
    m_axis_dout_tdata = 0;
end

always @(posedge aclk) begin
    m_axis_dout_tvalid <= 1'b0;
    if (count != 0) begin
        quotient <= next_quotient;
        remainder <= next_remainder;
        count <= count - 6'd1;
        if (count == 6'd1) begin
            m_axis_dout_tvalid <= 1'b1;
            m_axis_dout_tdata <= {next_quotient, next_remainder[31:0]};
        end
    end else if (s_axis_dividend_tvalid && s_axis_divisor_tvalid) begin
        quotient <= s_axis_dividend_tdata;
        divisor <= s_axis_divisor_tdata;
        remainder <= 33'b0;
        count <= 6'd32;
    end
end
endmodule
