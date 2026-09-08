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
assign rdata1 = (raddr1==5'b0) ? 32'b0 : rf[raddr1];

//READ OUT 2
assign rdata2 = (raddr2==5'b0) ? 32'b0 : rf[raddr2];

endmodule

