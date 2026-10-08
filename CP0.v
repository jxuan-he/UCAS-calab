// LoongArch32 CP0/CSR register file used by exceptions and interrupts.
//
// Textbook MIPS names and their LoongArch counterparts:
//   Status   -> CRMD/PRMD/ECFG     Cause    -> ESTAT
//   EPC      -> ERA                BadVAddr -> BADV
//   Count    -> stable counter     Compare  -> TCFG/TVAL/TICLR timer
// These are related roles, not identical register formats or semantics, so the
// RTL uses the architectural LoongArch names with one consistent cp0_ prefix.
module CP0(
    input  wire        clk,
    input  wire        resetn,
    input  wire        trap,
    input  wire [ 5:0] trap_ecode,
    input  wire [ 8:0] trap_esubcode,
    input  wire [31:0] trap_pc,
    input  wire        trap_badv_we,
    input  wire [31:0] trap_badv,
    input  wire [31:0] trap_inst,
    input  wire        ertn,
    input  wire        csr_we,
    input  wire [13:0] csr_num,
    input  wire [31:0] csr_wdata,
    input  wire [31:0] csr_wmask,
    output reg  [31:0] csr_rdata,
    output wire [31:0] cp0_eentry,
    output wire [31:0] cp0_era,
    output wire [ 1:0] cp0_plv,
    output wire        cp0_has_interrupt,
    output wire [31:0] cp0_tid,
    output wire [63:0] cp0_stable_counter
);

localparam [13:0] CSR_CRMD   = 14'h000;
localparam [13:0] CSR_PRMD   = 14'h001;
localparam [13:0] CSR_ECFG   = 14'h004;
localparam [13:0] CSR_ESTAT  = 14'h005;
localparam [13:0] CSR_ERA    = 14'h006;
localparam [13:0] CSR_BADV   = 14'h007;
localparam [13:0] CSR_BADI   = 14'h008;
localparam [13:0] CSR_EENTRY = 14'h00c;
localparam [13:0] CSR_SAVE0  = 14'h030;
localparam [13:0] CSR_SAVE1  = 14'h031;
localparam [13:0] CSR_SAVE2  = 14'h032;
localparam [13:0] CSR_SAVE3  = 14'h033;
localparam [13:0] CSR_TID    = 14'h040;
localparam [13:0] CSR_TCFG   = 14'h041;
localparam [13:0] CSR_TVAL   = 14'h042;
localparam [13:0] CSR_TICLR  = 14'h044;

reg [ 1:0] cp0_crmd_plv;
reg        cp0_crmd_ie;
reg        cp0_crmd_da;
reg        cp0_crmd_pg;
reg [ 1:0] cp0_prmd_pplv;
reg        cp0_prmd_pie;
reg [12:0] cp0_ecfg_lie;
reg [ 1:0] cp0_estat_is_software;
reg [ 5:0] cp0_estat_ecode;
reg [ 8:0] cp0_estat_esubcode;
reg [31:0] cp0_era_reg;
reg [31:0] cp0_badv;
reg [31:0] cp0_badi;
reg [31:0] cp0_eentry_reg;
reg [31:0] cp0_save0;
reg [31:0] cp0_save1;
reg [31:0] cp0_save2;
reg [31:0] cp0_save3;
reg [31:0] cp0_tid_reg;
reg [31:0] cp0_tcfg;
reg [31:0] cp0_tval;
reg        cp0_timer_interrupt;
reg [63:0] cp0_stable_counter_reg;

wire [12:0] cp0_estat_is = {
    1'b0, cp0_timer_interrupt, 1'b0, 8'b0, cp0_estat_is_software
};
wire [31:0] cp0_csr_write_value =
    (csr_rdata & ~csr_wmask) | (csr_wdata & csr_wmask);

assign cp0_has_interrupt  = cp0_crmd_ie && (|(cp0_ecfg_lie & cp0_estat_is));
assign cp0_eentry         = cp0_eentry_reg;
assign cp0_era            = cp0_era_reg;
assign cp0_plv            = cp0_crmd_plv;
assign cp0_tid            = cp0_tid_reg;
assign cp0_stable_counter = cp0_stable_counter_reg;

// Combinational read returns the old CSR value in the CSR writeback cycle.
always @(*) begin
    case (csr_num)
        CSR_CRMD:   csr_rdata = {27'b0, cp0_crmd_pg, cp0_crmd_da,
                                  cp0_crmd_ie, cp0_crmd_plv};
        CSR_PRMD:   csr_rdata = {29'b0, cp0_prmd_pie, cp0_prmd_pplv};
        CSR_ECFG:   csr_rdata = {19'b0, cp0_ecfg_lie}; // VS=0
        CSR_ESTAT:  csr_rdata = {1'b0, cp0_estat_esubcode,
                                  cp0_estat_ecode, 3'b0, cp0_estat_is};
        CSR_ERA:    csr_rdata = cp0_era_reg;
        CSR_BADV:   csr_rdata = cp0_badv;
        CSR_BADI:   csr_rdata = cp0_badi;
        CSR_EENTRY: csr_rdata = cp0_eentry_reg;
        CSR_SAVE0:  csr_rdata = cp0_save0;
        CSR_SAVE1:  csr_rdata = cp0_save1;
        CSR_SAVE2:  csr_rdata = cp0_save2;
        CSR_SAVE3:  csr_rdata = cp0_save3;
        CSR_TID:    csr_rdata = cp0_tid_reg;
        CSR_TCFG:   csr_rdata = cp0_tcfg;
        CSR_TVAL:   csr_rdata = cp0_tval;
        CSR_TICLR:  csr_rdata = 32'b0;
        default:    csr_rdata = 32'b0;
    endcase
end

always @(posedge clk) begin
    if (!resetn) begin
        cp0_crmd_plv           <= 2'b0;
        cp0_crmd_ie            <= 1'b0;
        cp0_crmd_da            <= 1'b1;
        cp0_crmd_pg            <= 1'b0;
        cp0_prmd_pplv          <= 2'b0;
        cp0_prmd_pie           <= 1'b0;
        cp0_ecfg_lie           <= 13'b0;
        cp0_estat_is_software  <= 2'b0;
        cp0_estat_ecode        <= 6'b0;
        cp0_estat_esubcode     <= 9'b0;
        cp0_era_reg            <= 32'b0;
        cp0_badv               <= 32'b0;
        cp0_badi               <= 32'b0;
        cp0_eentry_reg         <= 32'b0;
        cp0_save0              <= 32'b0;
        cp0_save1              <= 32'b0;
        cp0_save2              <= 32'b0;
        cp0_save3              <= 32'b0;
        cp0_tid_reg            <= 32'b0;
        cp0_tcfg               <= 32'b0;
        cp0_tval               <= 32'b0;
        cp0_timer_interrupt    <= 1'b0;
        cp0_stable_counter_reg <= 64'b0;
    end
    else begin
        cp0_stable_counter_reg <= cp0_stable_counter_reg + 64'd1;

        if (cp0_tcfg[0]) begin
            if (cp0_tval == 32'b0) begin
                cp0_timer_interrupt <= 1'b1;
                if (cp0_tcfg[1])
                    cp0_tval <= {cp0_tcfg[31:2], 2'b0};
                else
                    cp0_tcfg[0] <= 1'b0;
            end
            else begin
                cp0_tval <= cp0_tval - 32'd1;
            end
        end

        if (trap) begin
            cp0_prmd_pplv      <= cp0_crmd_plv;
            cp0_prmd_pie       <= cp0_crmd_ie;
            cp0_crmd_plv       <= 2'b0;
            cp0_crmd_ie        <= 1'b0;
            cp0_estat_ecode    <= trap_ecode;
            cp0_estat_esubcode <= trap_esubcode;
            cp0_era_reg        <= trap_pc;
            cp0_badi           <= trap_inst;
            if (trap_badv_we)
                cp0_badv <= trap_badv;
        end
        else if (ertn) begin
            cp0_crmd_plv <= cp0_prmd_pplv;
            cp0_crmd_ie  <= cp0_prmd_pie;
        end
        else if (csr_we) begin
            case (csr_num)
                CSR_CRMD: begin
                    cp0_crmd_plv <= cp0_csr_write_value[1:0];
                    cp0_crmd_ie  <= cp0_csr_write_value[2];
                    cp0_crmd_da  <= cp0_csr_write_value[3];
                    cp0_crmd_pg  <= cp0_csr_write_value[4];
                end
                CSR_PRMD: begin
                    cp0_prmd_pplv <= cp0_csr_write_value[1:0];
                    cp0_prmd_pie  <= cp0_csr_write_value[2];
                end
                // LIE[10] is reserved by this experiment's interrupt subset.
                CSR_ECFG:
                    cp0_ecfg_lie <= cp0_csr_write_value[12:0] & 13'h1bff;
                CSR_ESTAT:
                    cp0_estat_is_software <= cp0_csr_write_value[1:0];
                CSR_ERA:
                    cp0_era_reg <= cp0_csr_write_value;
                CSR_EENTRY:
                    cp0_eentry_reg <= {cp0_csr_write_value[31:12], 12'b0};
                CSR_SAVE0: cp0_save0 <= cp0_csr_write_value;
                CSR_SAVE1: cp0_save1 <= cp0_csr_write_value;
                CSR_SAVE2: cp0_save2 <= cp0_csr_write_value;
                CSR_SAVE3: cp0_save3 <= cp0_csr_write_value;
                CSR_TID:   cp0_tid_reg <= cp0_csr_write_value;
                CSR_TCFG: begin
                    cp0_tcfg <= cp0_csr_write_value;
                    if (cp0_csr_write_value[0])
                        cp0_tval <= {cp0_csr_write_value[31:2], 2'b0};
                end
                CSR_TICLR:
                    if (cp0_csr_write_value[0])
                        cp0_timer_interrupt <= 1'b0;
                default: ;
            endcase
        end
    end
end

endmodule
