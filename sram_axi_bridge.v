// Single-beat AXI3 bridge for the two SRAM-like ports.
module sram_axi_bridge (
    input wire aclk, aresetn,
    input wire inst_req,
    input wire [31:0] inst_addr,
    output wire inst_addr_ok, inst_data_ok,
    output wire [31:0] inst_rdata,
    input wire data_req, data_wr,
    input wire [1:0] data_size,
    input wire [31:0] data_addr, data_wdata,
    input wire [3:0] data_wstrb,
    output wire data_addr_ok, data_data_ok,
    output wire [31:0] data_rdata,
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
    output wire bready
);

localparam [2:0] IDLE = 3'd0, READ_ADDR = 3'd1, READ_DATA = 3'd2,
                 WRITE_SEND = 3'd3, WRITE_RESP = 3'd4, COMPLETE = 3'd5;

reg [2:0]  state;
reg        owner_data;
reg [31:0] req_addr;
reg [1:0]  req_size;
reg [31:0] req_wdata;
reg [3:0]  req_wstrb;
reg        aw_pending;
reg        w_pending;
reg [31:0] read_data;

// The previous AXI response has already been captured in COMPLETE. Deliver
// it to the old owner while allowing the next request to enter the bridge.
wire can_accept = aresetn && (state == IDLE || state == COMPLETE);
assign data_addr_ok = can_accept;
assign inst_addr_ok = can_accept && !data_req;

assign data_data_ok = aresetn && state == COMPLETE && owner_data;
assign inst_data_ok = aresetn && state == COMPLETE && !owner_data;
assign data_rdata = read_data;
assign inst_rdata = read_data;

assign arid    = {3'b0, owner_data};
assign araddr  = req_addr;
assign arlen   = 8'd0;
assign arsize  = {1'b0, req_size};
assign arburst = 2'b01;
assign arlock  = 2'b00;
assign arcache = 4'b0;
assign arprot  = 3'b0;
assign arvalid = aresetn && state == READ_ADDR;
assign rready  = aresetn && state == READ_DATA;

assign awid    = 4'd1;
assign awaddr  = req_addr;
assign awlen   = 8'd0;
assign awsize  = {1'b0, req_size};
assign awburst = 2'b01;
assign awlock  = 2'b00;
assign awcache = 4'b0;
assign awprot  = 3'b0;
assign awvalid = aresetn && state == WRITE_SEND && aw_pending;

assign wid    = 4'd1;
assign wdata  = req_wdata;
assign wstrb  = req_wstrb;
assign wlast  = 1'b1;
assign wvalid = aresetn && state == WRITE_SEND && w_pending;
assign bready = aresetn && state == WRITE_RESP;

wire aw_fire = awvalid && awready;
wire w_fire  = wvalid && wready;

always @(posedge aclk) begin
    if (!aresetn) begin
        state      <= IDLE;
        owner_data <= 1'b0;
        req_addr   <= 32'b0;
        req_size   <= 2'b0;
        req_wdata  <= 32'b0;
        req_wstrb  <= 4'b0;
        aw_pending <= 1'b0;
        w_pending  <= 1'b0;
        read_data  <= 32'b0;
    end else begin
        case (state)
            IDLE, COMPLETE: begin
                if (data_req && data_addr_ok) begin
                    owner_data <= 1'b1;
                    req_addr   <= data_addr;
                    req_size   <= data_size;
                    req_wdata  <= data_wdata;
                    req_wstrb  <= data_wstrb;
                    aw_pending <= data_wr;
                    w_pending  <= data_wr;
                    state      <= data_wr ? WRITE_SEND : READ_ADDR;
                end else if (inst_req && inst_addr_ok) begin
                    owner_data <= 1'b0;
                    req_addr   <= inst_addr;
                    req_size   <= 2'd2;
                    state      <= READ_ADDR;
                end else begin
                    state      <= IDLE;
                end
            end

            READ_ADDR: begin
                if (arvalid && arready)
                    state <= READ_DATA;
            end

            READ_DATA: begin
                // One outstanding request identifies the owner. The SoC
                // returns a single matching beat. Bus errors are outside Exp15.
                if (rvalid && rready) begin
                    read_data <= rdata;
                    state <= COMPLETE;
                end
            end

            WRITE_SEND: begin
                if (aw_fire)
                    aw_pending <= 1'b0;
                if (w_fire)
                    w_pending <= 1'b0;
                if ((!aw_pending || aw_fire) && (!w_pending || w_fire))
                    state <= WRITE_RESP;
            end

            WRITE_RESP: begin
                // Serialize later reads behind the write response.
                if (bvalid && bready)
                    state <= COMPLETE;
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule
