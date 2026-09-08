module IDU(
    input  [31:0] pc,
    input  [31:0] inst,
    // 只有 jirl 的 target 计算需要 rj_value
    input  [31:0] rj_value,

    // 给顶层regfile
    output [ 4:0] rf_raddr1,
    output [ 4:0] rf_raddr2,

    // 给EXE级的控制信号
    output [11:0] alu_op,
    output        src1_is_pc,
    output        src2_is_imm,
    output [31:0] imm,
    output        res_from_mem,
    output        gr_we,
    output        mem_we,
    output [ 4:0] dest,

    // 跳转
    output [31:0] br_target,
    output        is_beq,
    output        is_bne,
    output        is_jirl,
    output        is_bl,
    output        is_b
);

    // ================== 1. 指令字段切分 ==================
    wire [ 5:0] op_31_26 = inst[31:26];
    wire [ 3:0] op_25_22 = inst[25:22];
    wire [ 1:0] op_21_20 = inst[21:20];
    wire [ 4:0] op_19_15 = inst[19:15];

    wire [ 4:0] rd       = inst[ 4: 0];
    wire [ 4:0] rj       = inst[ 9: 5];
    wire [ 4:0] rk       = inst[14:10];

    wire [11:0] i12      = inst[21:10];
    wire [19:0] i20      = inst[24: 5];
    wire [15:0] i16      = inst[25:10];
    wire [25:0] i26      = {inst[ 9: 0], inst[25:10]};

    // ================== 2. One-Hot 解码 ==================
    wire [63:0] op_31_26_d = 64'b1 << op_31_26;
    wire [15:0] op_25_22_d = 16'b1 << op_25_22;
    wire [ 3:0] op_21_20_d =  4'b1 << op_21_20;
    wire [31:0] op_19_15_d = 32'b1 << op_19_15;

    // ================== 3. 指令识别（20条） ==================
    wire inst_add_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h00];
    wire inst_sub_w  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h02];
    wire inst_slt    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h04];
    wire inst_sltu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h05];
    wire inst_nor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h08];
    wire inst_and    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h09];
    wire inst_or     = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0a];
    wire inst_xor    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0b];
    wire inst_slli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h01];
    wire inst_srli_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h09];
    wire inst_srai_w = op_31_26_d[6'h00] & op_25_22_d[4'h1] & op_21_20_d[2'h0] & op_19_15_d[5'h11];
    wire inst_addi_w = op_31_26_d[6'h00] & op_25_22_d[4'ha];
    wire inst_ld_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h2];
    wire inst_st_w   = op_31_26_d[6'h0a] & op_25_22_d[4'h6];
    wire inst_jirl   = op_31_26_d[6'h13];
    wire inst_b      = op_31_26_d[6'h14];
    wire inst_bl     = op_31_26_d[6'h15];
    wire inst_beq    = op_31_26_d[6'h16];
    wire inst_bne    = op_31_26_d[6'h17];
    wire inst_lu12i_w= op_31_26_d[6'h05] & ~inst[25];

    // ================== 4. ALU 控制信号 ==================
    assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | inst_bl;
    assign alu_op[ 1] = inst_sub_w | inst_beq | inst_bne;
    assign alu_op[ 2] = inst_slt;
    assign alu_op[ 3] = inst_sltu;
    assign alu_op[ 4] = inst_and;
    assign alu_op[ 5] = inst_nor;
    assign alu_op[ 6] = inst_or;
    assign alu_op[ 7] = inst_xor;
    assign alu_op[ 8] = inst_slli_w;
    assign alu_op[ 9] = inst_srli_w;
    assign alu_op[10] = inst_srai_w;
    assign alu_op[11] = inst_lu12i_w;

    // ================== 5. 立即数生成 ==================
    wire need_ui5  = inst_slli_w | inst_srli_w | inst_srai_w;
    wire need_si12 = inst_addi_w | inst_ld_w   | inst_st_w;
    wire need_si20 = inst_lu12i_w;
    wire need_si26 = inst_b      | inst_bl;
    wire src2_is_4 = inst_jirl   | inst_bl;

    assign imm = src2_is_4 ? 32'h4 :
                 need_si20 ? {i20[19:0], 12'b0} :
                             {{20{i12[11]}}, i12[11:0]};

    wire [31:0] br_offs   = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                                        {{14{i16[15]}}, i16[15:0], 2'b0};

    wire [31:0] jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

    // ================== 6. 操作数选择控制 ==================
    wire src_reg_is_rd = inst_beq | inst_bne | inst_st_w;

    assign src1_is_pc  = inst_jirl | inst_bl;
    assign src2_is_imm = inst_slli_w | inst_srli_w | inst_srai_w |
                         inst_addi_w | inst_ld_w   | inst_st_w   |
                         inst_lu12i_w| inst_jirl   | inst_bl;

    // ================== 7. 访存/写回控制 ==================
    assign res_from_mem = inst_ld_w;
    assign gr_we        = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b;  // bl要写r1
    assign mem_we       = inst_st_w;
    assign dest         = inst_bl ? 5'd1 : rd;

    // ================== 8. 寄存器读地址 ==================
    assign rf_raddr1 = rj;
    assign rf_raddr2 = src_reg_is_rd ? rd : rk;

    // ================== 9. 跳转目标地址（ID级计算） ==================
    assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (pc + br_offs) :
                                                                     (rj_value + jirl_offs);

    // ================== 10. 分支类型输出（给EX级判断跳不跳） ==================
    assign is_beq  = inst_beq;
    assign is_bne  = inst_bne;
    assign is_jirl = inst_jirl;
    assign is_bl   = inst_bl;
    assign is_b    = inst_b;

endmodule