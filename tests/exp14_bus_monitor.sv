`timescale 1ns/1ps
// Checks the real official SoC buses, including discarded fetch responses.
module exp14_bus_monitor;
`define CPU tb_top.soc_lite.cpu
wire clk = tb_top.soc_lite.cpu_clk;
wire resetn = tb_top.soc_lite.cpu_resetn;
integer i_pending=0, d_pending=0, cycles=0;
integer ia=0, ir=0, da=0, dr=0, drops=0;
wire i_accept = `CPU.inst_sram_req && `CPU.inst_sram_addr_ok;
wire d_accept = `CPU.data_sram_req && `CPU.data_sram_addr_ok;
always @(posedge clk) begin
    if (!resetn) begin
        i_pending=0; d_pending=0; cycles=0;
        ia=0; ir=0; da=0; dr=0; drops=0;
    end else begin
        cycles=cycles+1;
        if (cycles>10000000) $fatal(1,"EXP14 timeout");
        if (`CPU.inst_sram_data_ok && i_pending!=1) $fatal(1,"orphan instruction response");
        if (`CPU.data_sram_data_ok && d_pending!=1) $fatal(1,"orphan data response");
        if (`CPU.data_sram_req && (`CPU.exe_final_exc || `CPU.older_redirect_pending))
            $fatal(1,"data request crossed exception boundary");
        if (`CPU.mem_valid && `CPU.mem_wait_resp && !`CPU.data_sram_data_ok && `CPU.mem_fire)
            $fatal(1,"MEM left before response");
        if (`CPU.exe_br_taken && !`CPU.exe_fire) $fatal(1,"branch lost under backpressure");
        if (`CPU.u_if_pc.state==2'd3 && `CPU.inst_sram_data_ok) drops=drops+1;
        ia=ia+i_accept; ir=ir+`CPU.inst_sram_data_ok;
        da=da+d_accept; dr=dr+`CPU.data_sram_data_ok;
        i_pending=i_pending+i_accept-`CPU.inst_sram_data_ok;
        d_pending=d_pending+d_accept-`CPU.data_sram_data_ok;
        if(i_pending<0 || i_pending>1 || d_pending<0 || d_pending>1)
            $fatal(1,"transaction conservation failed");
        if(tb_top.test_end && !tb_top.debug_end)
            $display("EXP14_BUS_CHECKS cycles=%0d I=%0d/%0d D=%0d/%0d dropped=%0d",cycles,ia,ir,da,dr,drops);
    end
end
`undef CPU
endmodule
