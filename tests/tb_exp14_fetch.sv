`timescale 1ns/1ps
module tb_exp14_fetch;
reg clk=0;always #5 clk=~clk;
reg resetn=0,redirect=0,allowin=0,addr_ok=0,data_ok=0;
reg [31:0] target=0,rdata=0;
wire valid,req;wire [31:0] pc,inst,addr;
IF_PC dut(.clk(clk),.resetn(resetn),.redirect(redirect),.redirect_target(target),
 .id_allowin(allowin),.fetch_valid(valid),.fetch_pc(pc),.fetch_inst(inst),
 .inst_sram_req(req),.inst_sram_addr(addr),.inst_sram_addr_ok(addr_ok),
 .inst_sram_data_ok(data_ok),.inst_sram_rdata(rdata));
task tick;begin @(posedge clk);#1;@(negedge clk);end endtask
task check(input bit ok,input [255:0] message);begin if(!ok)$fatal(1,"%s",message);end endtask
initial begin
 tick();resetn=1;
 repeat(4)begin tick();check(req&&addr=='h1c000000&&!valid,"address changed before acceptance");end
 addr_ok=1;tick();addr_ok=0;check(!req&&!valid,"request duplicated while waiting");
 repeat(4)tick();
 rdata='h12345678;data_ok=1;tick();data_ok=0;
 check(valid&&pc=='h1c000000&&inst=='h12345678,"response PC mismatch");
 repeat(4)begin tick();check(valid&&inst=='h12345678&&!req,"buffer lost under backpressure");end
 allowin=1;tick();allowin=0;
 addr_ok=1;tick();addr_ok=0;
 redirect=1;target='h1c000100;tick();redirect=0;
 repeat(4)begin tick();check(!req&&!valid,"cancelled request was forgotten");end
 data_ok=1;rdata='hdeadbeef;tick();data_ok=0;
 check(req&&addr=='h1c000100&&!valid,"old response delivered after redirect");
 addr_ok=1;tick();addr_ok=0;
 redirect=1;target='h1c000200;data_ok=1;tick();redirect=0;data_ok=0;#1;
 check(req&&addr=='h1c000200&&!valid,"same-edge redirect/response stuck");
 redirect=1;target='h1c000003;tick();redirect=0;
 check(!req,"ADEF issued bus request");tick();
 check(valid&&pc=='h1c000003,"ADEF did not complete internally");
 $display("EXP14_FETCH_PASS stalled_address buffered_response drop simultaneous_redirect ADEF");$finish;
end
initial begin #10000;$fatal(1,"fetch timeout");end
endmodule
