// Exp15 AXI top. The pipeline still uses the Exp14 SRAM-like handshakes.
module mycpu_top(
    input  wire aclk,
    input  wire aresetn,

    output wire [3:0] arid,
    output wire [31:0] araddr,
    output wire [7:0] arlen,
    output wire [2:0] arsize,
    output wire [1:0] arburst, arlock,
    output wire [3:0] arcache,
    output wire [2:0] arprot,
    output wire arvalid,
    input wire arready,
    input wire [3:0] rid,
    input wire [31:0] rdata,
    input wire [1:0] rresp,
    input wire rlast, rvalid,
    output wire rready,
    output wire [3:0] awid,
    output wire [31:0] awaddr,
    output wire [7:0] awlen,
    output wire [2:0] awsize,
    output wire [1:0] awburst, awlock,
    output wire [3:0] awcache,
    output wire [2:0] awprot,
    output wire awvalid,
    input wire awready,
    output wire [3:0] wid,
    output wire [31:0] wdata,
    output wire [3:0] wstrb,
    output wire wlast, wvalid,
    input wire wready,
    input wire [3:0] bid,
    input wire [1:0] bresp,
    input wire bvalid,
    output wire bready,

    output wire [31:0] debug_wb_pc,
    output wire [3:0] debug_wb_rf_we,
    output wire [4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

wire         inst_sram_req;
wire [31:0]  inst_sram_addr;
wire         inst_sram_addr_ok;
wire         inst_sram_data_ok;
wire [31:0]  inst_sram_rdata;
wire         data_sram_req;
wire [31:0]  data_sram_addr;
wire         data_sram_addr_ok;
wire         data_sram_data_ok;
wire [31:0]  data_sram_rdata;
wire         data_sram_wr;
wire [1:0]   data_sram_size;
wire [3:0]   data_sram_wstrb;
wire [31:0]  data_sram_wdata;

mycpu_core u_core (
    .clk(aclk),
    .resetn(aresetn),
    .inst_sram_req(inst_sram_req),
    .inst_sram_addr(inst_sram_addr),
    .inst_sram_addr_ok(inst_sram_addr_ok),
    .inst_sram_data_ok(inst_sram_data_ok),
    .inst_sram_rdata(inst_sram_rdata),
    .data_sram_req(data_sram_req),
    .data_sram_addr(data_sram_addr),
    .data_sram_addr_ok(data_sram_addr_ok),
    .data_sram_data_ok(data_sram_data_ok),
    .data_sram_rdata(data_sram_rdata),
    .data_sram_wr(data_sram_wr),
    .data_sram_size(data_sram_size),
    .data_sram_wstrb(data_sram_wstrb),
    .data_sram_wdata(data_sram_wdata),
    .inst_sram_wr(),
    .inst_sram_size(),
    .inst_sram_wstrb(),
    .inst_sram_wdata(),
    .debug_wb_pc(debug_wb_pc),
    .debug_wb_rf_we(debug_wb_rf_we),
    .debug_wb_rf_wnum(debug_wb_rf_wnum),
    .debug_wb_rf_wdata(debug_wb_rf_wdata)
);

sram_axi_bridge u_bridge (
    .aclk(aclk),
    .aresetn(aresetn),
    .inst_req(inst_sram_req),
    .inst_addr(inst_sram_addr),
    .inst_addr_ok(inst_sram_addr_ok),
    .inst_data_ok(inst_sram_data_ok),
    .inst_rdata(inst_sram_rdata),
    .data_req(data_sram_req),
    .data_addr(data_sram_addr),
    .data_addr_ok(data_sram_addr_ok),
    .data_data_ok(data_sram_data_ok),
    .data_rdata(data_sram_rdata),
    .data_wr(data_sram_wr),
    .data_size(data_sram_size),
    .data_wstrb(data_sram_wstrb),
    .data_wdata(data_sram_wdata),
    .arid(arid),
    .araddr(araddr),
    .arlen(arlen),
    .arsize(arsize),
    .arburst(arburst),
    .arlock(arlock),
    .arcache(arcache),
    .arprot(arprot),
    .arvalid(arvalid),
    .arready(arready),
    .rid(rid),
    .rdata(rdata),
    .rresp(rresp),
    .rlast(rlast),
    .rvalid(rvalid),
    .rready(rready),
    .awid(awid),
    .awaddr(awaddr),
    .awlen(awlen),
    .awsize(awsize),
    .awburst(awburst),
    .awlock(awlock),
    .awcache(awcache),
    .awprot(awprot),
    .awvalid(awvalid),
    .awready(awready),
    .wid(wid),
    .wdata(wdata),
    .wstrb(wstrb),
    .wlast(wlast),
    .wvalid(wvalid),
    .wready(wready),
    .bid(bid),
    .bresp(bresp),
    .bvalid(bvalid),
    .bready(bready)
);

endmodule
