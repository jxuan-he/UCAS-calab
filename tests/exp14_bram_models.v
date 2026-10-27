// Fast cross-check only. Vivado verification uses real generated Xilinx IP.
module inst_ram(input clka,input ena,input [3:0] wea,input [17:0] addra,
 input [31:0] dina,output reg [31:0] douta);
reg [31:0] mem[0:262143];integer i,b;
initial begin
 for(i=0;i<262144;i=i+1)mem[i]=0;
 $readmemh("build/exp14/inst_ram.hex",mem);
end
always @(posedge clka)if(ena)begin
 for(b=0;b<4;b=b+1)if(wea[b])mem[addra][8*b+:8]<=dina[8*b+:8];
 douta<=mem[addra];
end
endmodule
module data_ram(input clka,input ena,input [3:0] wea,input [15:0] addra,
 input [31:0] dina,output reg [31:0] douta);
reg [31:0] mem[0:65535];integer i,b;
initial for(i=0;i<65536;i=i+1)mem[i]=0;
always @(posedge clka)if(ena)begin
 for(b=0;b<4;b=b+1)if(wea[b])mem[addra][8*b+:8]<=dina[8*b+:8];
 douta<=mem[addra];
end
endmodule
module clk_pll(input clk_in1,output cpu_clk,output timer_clk);
assign cpu_clk=clk_in1;assign timer_clk=clk_in1;
endmodule
