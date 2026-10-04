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
    output        is_b,

    // 乘除（exp10 B 类）
    output        is_mul_w,
    output        is_mulh_w,
    output        is_mulh_wu,
    output        is_div_w,
    output        is_mod_w,
    output        is_div_wu,
    output        is_mod_wu
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

    // ================== 3. 指令识别（20 + exp10 A类9 + B类7 = 36条） ==================
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

    // exp10 A 类：算术逻辑扩展（全部复用现有 ALU 操作，alu_op 不扩位）
    wire inst_slti     = op_31_26_d[6'h00] & op_25_22_d[4'h8];
    wire inst_sltui    = op_31_26_d[6'h00] & op_25_22_d[4'h9];
    wire inst_andi     = op_31_26_d[6'h00] & op_25_22_d[4'hd];
    wire inst_ori      = op_31_26_d[6'h00] & op_25_22_d[4'he];
    wire inst_xori     = op_31_26_d[6'h00] & op_25_22_d[4'hf];
    // 寄存器移位（移位量来自 rk[4:0]），与 add/sub 同属 3R 运算组，靠 op_19_15 区分
    wire inst_sll_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0e];
    wire inst_srl_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h0f];
    wire inst_sra_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h10];
    wire inst_pcaddu12i= op_31_26_d[6'h07];   // rd = pc + {si20,12'b0}

    // exp10 B 类：乘除（编码已从 test.s 机器码验证；div/mod 组 op_21_20=0x2，与 mul 组不同）
    wire inst_mul_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h18];
    wire inst_mulh_w   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h19];
    wire inst_mulh_wu  = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h1] & op_19_15_d[5'h1a];
    wire inst_div_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h00];
    wire inst_mod_w    = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h01];
    wire inst_div_wu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h02];
    wire inst_mod_wu   = op_31_26_d[6'h00] & op_25_22_d[4'h0] & op_21_20_d[2'h2] & op_19_15_d[5'h03];

    // ================== 4. ALU 控制信号 ==================
    assign alu_op[ 0] = inst_add_w | inst_addi_w | inst_ld_w | inst_st_w | inst_jirl | inst_bl
                      | inst_pcaddu12i;
    assign alu_op[ 1] = inst_sub_w | inst_beq | inst_bne;
    assign alu_op[ 2] = inst_slt  | inst_slti;
    assign alu_op[ 3] = inst_sltu | inst_sltui;
    assign alu_op[ 4] = inst_and  | inst_andi;
    assign alu_op[ 5] = inst_nor;
    assign alu_op[ 6] = inst_or   | inst_ori;
    assign alu_op[ 7] = inst_xor  | inst_xori;
    assign alu_op[ 8] = inst_slli_w | inst_sll_w;
    assign alu_op[ 9] = inst_srli_w | inst_srl_w;
    assign alu_op[10] = inst_srai_w | inst_sra_w;
    assign alu_op[11] = inst_lu12i_w;

    // ================== 5. 立即数生成 ==================
    wire need_ui5  = inst_slli_w | inst_srli_w | inst_srai_w;
    // sltui 的 u 指"无符号比较"，立即数仍走符号扩展；零扩展只有逻辑运算三条
    wire need_si12 = inst_addi_w | inst_slti | inst_sltui | inst_ld_w | inst_st_w;
    wire need_ui12 = inst_andi | inst_ori | inst_xori;
    wire need_si20 = inst_lu12i_w | inst_pcaddu12i;
    wire need_si26 = inst_b      | inst_bl;
    wire src2_is_4 = inst_jirl   | inst_bl;

    // 位掩码四选一：4 / si20 / ui12 / si12格式，one-hot 互斥
    // si12 项必须含 need_ui5：移位量 sa 在 i12 低 5 位，与 si12 共用扩展通路
    assign imm = ({32{src2_is_4}} & 32'h4                     )
               | ({32{need_si20}} & {i20[19:0], 12'b0}       )
               | ({32{need_ui12}} & {20'b0, i12[11:0]}       )
               | ({32{need_si12 | need_ui5}} & {{20{i12[11]}}, i12[11:0]});

    wire [31:0] br_offs   = need_si26 ? {{ 4{i26[25]}}, i26[25:0], 2'b0} :
                                        {{14{i16[15]}}, i16[15:0], 2'b0};

    wire [31:0] jirl_offs = {{14{i16[15]}}, i16[15:0], 2'b0};

    // ================== 6. 操作数选择控制 ==================
    wire src_reg_is_rd = inst_beq | inst_bne | inst_st_w;

    assign src1_is_pc  = inst_jirl | inst_bl | inst_pcaddu12i;
    assign src2_is_imm = inst_slli_w | inst_srli_w | inst_srai_w |
                         inst_addi_w | inst_slti   | inst_sltui  |
                         inst_andi  | inst_ori    | inst_xori   |
                         inst_ld_w  | inst_st_w   |
                         inst_lu12i_w| inst_jirl  | inst_bl     | inst_pcaddu12i;

    // ================== 7. 访存/写回控制 ==================
    assign res_from_mem = inst_ld_w;
    assign gr_we        = ~inst_st_w & ~inst_beq & ~inst_bne & ~inst_b;  // bl要写r1
    assign mem_we       = inst_st_w;
    assign dest         = inst_bl ? 5'd1 : rd;

    // ================== 8. 寄存器读地址 ==================
    // 真实读使能：不读寄存器的指令把读地址用位掩码钳到 r0，r0 天然无相关，
    // 使下游冲突检测退化为纯等值比较（配合 dest != 0 排除）
    wire need_rj  = ~inst_b & ~inst_bl & ~inst_lu12i_w & ~inst_pcaddu12i;
    wire need_rkd = inst_add_w | inst_sub_w | inst_slt  | inst_sltu |
                    inst_nor   | inst_and   | inst_or   | inst_xor  |
                    inst_sll_w | inst_srl_w | inst_sra_w |          // 寄存器移位真读 rk
                    inst_mul_w | inst_mulh_w| inst_mulh_wu|          // 乘除全读 rj/rk
                    inst_div_w | inst_mod_w | inst_div_wu | inst_mod_wu |
                    inst_beq   | inst_bne   | inst_st_w;

    assign rf_raddr1 = {5{need_rj}} & rj;
    assign rf_raddr2 = {5{need_rkd}} & (src_reg_is_rd ? rd : rk);

    // ================== 9. 跳转目标地址（ID级计算） ==================
    assign br_target = (inst_beq || inst_bne || inst_bl || inst_b) ? (pc + br_offs) :
                                                                     (rj_value + jirl_offs);

    // ================== 10. 分支类型输出（给EX级判断跳不跳） ==================
    assign is_beq  = inst_beq;
    assign is_bne  = inst_bne;
    assign is_jirl = inst_jirl;
    assign is_bl   = inst_bl;
    assign is_b    = inst_b;

    // ================== 11. 乘除类型输出 ==================
    assign is_mul_w   = inst_mul_w;
    assign is_mulh_w  = inst_mulh_w;
    assign is_mulh_wu = inst_mulh_wu;
    assign is_div_w   = inst_div_w;
    assign is_mod_w   = inst_mod_w;
    assign is_div_wu  = inst_div_wu;
    assign is_mod_wu  = inst_mod_wu;

endmodule