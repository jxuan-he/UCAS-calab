`define DATA_WIDTH 32
`define ADDR_WIDTH 5

module regfile(
    input  wire        clk,
    // READ PORT 1
    input  wire [`ADDR_WIDTH - 1:0] raddr1,
    output wire [`DATA_WIDTH - 1:0] rdata1,
    // READ PORT 2
    input  wire [`ADDR_WIDTH - 1:0] raddr2,
    output wire [`DATA_WIDTH - 1:0] rdata2,
    // WRITE PORT
    input  wire        we,       //write enable, HIGH valid
    input  wire [`ADDR_WIDTH - 1:0] waddr,
    input  wire [`DATA_WIDTH - 1:0] wdata
);
reg [31:0] rf[31:0];

//WRITE
always @(posedge clk) begin
    if ( we && waddr != `ADDR_WIDTH'b0 ) rf[waddr]<= wdata;
end

//READ OUT 1
// 写读同址旁路：WB 写与 ID 读同拍时，读口直通写入值（等价于“写前半拍、读后半拍”）
// 位掩码实现：fwd 命中给 wdata；raddr==r0 恒读 0；否则读 rf 数组
wire fwd1 = we & (waddr != `ADDR_WIDTH'b0) & (waddr == raddr1);   // fwd 蕴含 raddr1 != r0
wire rd1  = (raddr1 != `ADDR_WIDTH'b0);
assign rdata1 = ({`DATA_WIDTH{fwd1       }} & wdata)
              | ({`DATA_WIDTH{rd1 & ~fwd1}} & rf[raddr1]);

//READ OUT 2
wire fwd2 = we & (waddr != `ADDR_WIDTH'b0) & (waddr == raddr2);
wire rd2  = (raddr2 != `ADDR_WIDTH'b0);
assign rdata2 = ({`DATA_WIDTH{fwd2       }} & wdata)
              | ({`DATA_WIDTH{rd2 & ~fwd2}} & rf[raddr2]);

endmodule

