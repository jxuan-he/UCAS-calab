`timescale 1ns/1ps
module tb_exp14_stress;
reg clk=0; always #5 clk=~clk;
reg resetn=0;
reg ipending=0,dpending=0;
wire iq,iw,dq,dw; wire [1:0] isz,dsz; wire [3:0] ist, dst;
wire [31:0] ia,idataw,da,ddataw,pc,wd;
reg iok=0,dok=0; reg [31:0] idatar=0,ddatar=0;
wire iaok=!ipending, daok=!dpending;
wire [3:0] we; wire [4:0] wn;
mycpu_top dut(.clk(clk),.resetn(resetn),
 .inst_sram_req(iq),.inst_sram_wr(iw),.inst_sram_size(isz),.inst_sram_wstrb(ist),
 .inst_sram_addr(ia),.inst_sram_wdata(idataw),.inst_sram_addr_ok(iaok),.inst_sram_data_ok(iok),.inst_sram_rdata(idatar),
 .data_sram_req(dq),.data_sram_wr(dw),.data_sram_size(dsz),.data_sram_wstrb(dst),
 .data_sram_addr(da),.data_sram_wdata(ddataw),.data_sram_addr_ok(daok),.data_sram_data_ok(dok),.data_sram_rdata(ddatar),
 .debug_wb_pc(pc),.debug_wb_rf_we(we),.debug_wb_rf_wnum(wn),.debug_wb_rf_wdata(wd));
reg [31:0] rom[0:63],mem[0:127],regs[0:31];
reg [31:0] iaddr; integer countdown=0;
integer i,b,cycles=0,div_starts=0,held=0,branch_wait=0,writes=0;
function [31:0] ri(input [31:0] op,input integer rd,rj,imm);
 ri=op | ((imm & 4095)<<10) | (rj<<5) | rd;
endfunction
initial begin
 for(i=0;i<64;i=i+1)rom[i]=32'h03400000;
 for(i=0;i<128;i=i+1)mem[i]=0;
 for(i=0;i<32;i=i+1)regs[i]=0;
 mem[64]=32'h11223344;
 rom[0]=ri('h02800000,2,0,'h100);
 rom[1]=ri('h02800000,4,0,100);
 rom[2]=ri('h02800000,5,0,7);
 rom[3]=ri('h28800000,8,2,0);
 rom[4]='h00200000 | (5<<10) | (4<<5) | 9;
 rom[5]=ri('h29800000,9,2,4);
 rom[6]=ri('h28800000,10,2,4);
 rom[7]=ri('h28800000,11,2,0);
 rom[8]='h54000000 | (3<<10);
 rom[9]=ri('h29800000,4,2,8);
 rom[10]=ri('h02800000,20,0,1);
 rom[11]=ri('h02800000,12,0,-1);
 rom[12]=ri('h29000000,12,2,1);
 rom[13]=ri('h2a000000,13,2,1);
 rom[14]=ri('h29400000,12,2,2);
 rom[15]=ri('h2a400000,14,2,2);
 rom[16]=ri('h02800000,31,0,'h5a);
 rom[17]='h50000000;
 repeat(5) @(negedge clk); resetn=1;
end
always @(posedge clk) begin
 iok<=0; dok<=0;
 if(!resetn) begin ipending<=0; dpending<=0; end
 else begin
  cycles=cycles+1;
  if(cycles>5000)$fatal(1,"stress timeout pc=%h",pc);
  if(iq&&iaok)begin ipending<=1;iaddr<=ia;end
  if(ipending)begin iok<=1;idatar<=rom[iaddr[7:2]];ipending<=0;end
  if(dq&&daok)begin
   dpending<=1; countdown<=80; ddatar<=mem[da[8:2]];
   if(da=='h108)$fatal(1,"wrong-path store escaped");
   if(dw)begin
    writes=writes+1;
    for(b=0;b<4;b=b+1)if(dst[b])mem[da[8:2]][8*b+:8]<=ddataw[8*b+:8];
   end
  end
  if(dpending)begin
   if(countdown==0)begin dok<=1;dpending<=0;end
   else countdown<=countdown-1;
  end
  if(dut.div_in_fire)div_starts=div_starts+1;
  if(dut.div_result_valid && !dut.mem_allowin)held=held+1;
  if(dut.exe_valid&&dut.exe_is_bl&&!dut.mem_allowin)branch_wait=branch_wait+1;
  if(|we && wn!=0)regs[wn]=wd;
  if(|we && wn==31)begin
   if(wd!='h5a||regs[9]!=14||regs[10]!=14||regs[8]!='h11223344||regs[11]!='h11223344||
      regs[1]!='h1c000024||regs[13]!=255||regs[14]!=65535||regs[20]!=0||
      mem[64]!='hffffff44||mem[65]!=14||writes!=3||div_starts!=1||held==0||branch_wait==0)
      $fatal(1,"stress mismatch div=%d starts=%d held=%d branch_wait=%d link=%h",regs[9],div_starts,held,branch_wait,regs[1]);
   $display("EXP14_STRESS_PASS cycles=%0d div_starts=%0d held=%0d branch_wait=%0d writes=%0d",cycles,div_starts,held,branch_wait,writes);
   $finish;
  end
 end
end
endmodule
