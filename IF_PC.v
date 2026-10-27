// One outstanding fetch with a response buffer and explicit cancelled-request drain.
module IF_PC(
    input wire clk, input wire resetn,
    input wire redirect, input wire [31:0] redirect_target,
    input wire id_allowin,
    output wire fetch_valid,
    output reg [31:0] fetch_pc, output reg [31:0] fetch_inst,
    output wire inst_sram_req, output wire [31:0] inst_sram_addr,
    input wire inst_sram_addr_ok, input wire inst_sram_data_ok,
    input wire [31:0] inst_sram_rdata
);
localparam EMPTY=2'd0, WAIT=2'd1, HAVE=2'd2, DROP=2'd3;
reg [1:0] state;
reg [31:0] next_pc;
wire adef = |next_pc[1:0];
wire addr_fire = inst_sram_req && inst_sram_addr_ok;
assign inst_sram_req = resetn && state==EMPTY && !redirect && !adef;
assign inst_sram_addr = next_pc;
assign fetch_valid = resetn && state==HAVE && !redirect;
always @(posedge clk) begin
    if (!resetn) begin
        state <= EMPTY;
        next_pc <= 32'h1c00_0000;
        fetch_pc <= 32'h1c00_0000;
        fetch_inst <= 32'h0340_0000;
    end else if (redirect) begin
        next_pc <= redirect_target;
        // If data_ok is high, the cancelled response is consumed on this edge.
        if ((state==WAIT || state==DROP) && !inst_sram_data_ok)
            state <= DROP;
        else state <= EMPTY;
    end else begin
        case (state)
            EMPTY: if (adef || addr_fire) begin
                fetch_pc <= next_pc;
                next_pc <= next_pc + 32'd4;
                if (adef) begin
                    // No bus transaction: carry the original bad PC into ID.
                    fetch_inst <= 32'h0340_0000;
                    state <= HAVE;
                end else state <= WAIT;
            end
            WAIT: if (inst_sram_data_ok) begin
                fetch_inst <= inst_sram_rdata;
                state <= HAVE;
            end
            HAVE: if (id_allowin) state <= EMPTY;
            DROP: if (inst_sram_data_ok) state <= EMPTY;
            default: state <= EMPTY;
        endcase
    end
end
endmodule
