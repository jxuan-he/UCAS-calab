module mycpu_top(
    input  wire        clk,
    input  wire        resetn,

    output wire        inst_sram_en,
    output wire [ 3:0] inst_sram_we,
    output wire [31:0] inst_sram_addr,
    output wire [31:0] inst_sram_wdata,
    input  wire [31:0] inst_sram_rdata,

    output wire        data_sram_en,
    output wire [ 3:0] data_sram_we,
    output wire [31:0] data_sram_addr,
    output wire [31:0] data_sram_wdata,
    input  wire [31:0] data_sram_rdata,
    output wire [31:0] debug_wb_pc,
    output wire [ 3:0] debug_wb_rf_we,
    output wire [ 4:0] debug_wb_rf_wnum,
    output wire [31:0] debug_wb_rf_wdata
);

// ================== 顶层信号声明 ==================

// IF1
wire [31:0] if1_pc;
wire        if1_fire;
wire        if1_kill;      // IF1 侧标记：本拍 fire 的地址是错误路径
reg         if1_fire_r;
reg         if1_kill_r;    // 标记本次到达的响应该丢弃

// IF2
wire        if2_fire;
wire        if2_allowin;
reg         if2_valid;
reg  [31:0] if2_pc;
reg  [31:0] if2_inst;
wire [31:0] if2_pc_out;
wire [31:0] if2_inst_out;

// ID 级间
wire        id_allowin;
wire        id_ready_go;
wire        id_fire;
reg         id_valid;
reg  [31:0] id_pc;
reg  [31:0] id_inst;

// ID 输出
wire [ 4:0] id_rf_raddr1;
wire [ 4:0] id_rf_raddr2;
wire [11:0] id_alu_op;
wire        id_src1_is_pc;
wire        id_src2_is_imm;
wire [31:0] id_imm;
wire        id_res_from_mem;
wire        id_gr_we;
wire        id_mem_we;
wire [ 4:0] id_dest;
wire [31:0] id_br_target;
wire        id_is_beq;
wire        id_is_bne;
wire        id_is_jirl;
wire        id_is_bl;
wire        id_is_b;
wire        id_is_mul_w;
wire        id_is_mulh_w;
wire        id_is_mulh_wu;
wire        id_is_div_w;
wire        id_is_mod_w;
wire        id_is_div_wu;
wire        id_is_mod_wu;

// 跳转（来自 EXE 级，由顶层转发）
wire        exe_br_taken;
reg  [31:0] exe_br_target;
wire        exe_rj_eq_rkd;

// 级间握手信号
wire        exe_allowin;
wire        exe_ready_go;
wire        exe_fire;
wire        mem_allowin;
wire        mem_ready_go;
wire        mem_fire;
wire        wb_allowin;
wire        wb_fire;

// EXE 级间寄存器
reg         exe_valid;
reg  [31:0] exe_pc;
reg  [31:0] exe_alu_src1;
reg  [31:0] exe_alu_src2;
reg  [11:0] exe_alu_op;
reg         exe_mem_we;
reg         exe_res_from_mem;
reg         exe_gr_we;
reg  [ 4:0] exe_dest;
reg         exe_is_beq;
reg         exe_is_bne;
reg         exe_is_jirl;
reg         exe_is_bl;
reg         exe_is_b;
reg         exe_is_mul_w;
reg         exe_is_mulh_w;
reg         exe_is_mulh_wu;
reg         exe_is_div_w;
reg         exe_is_mod_w;
reg         exe_is_div_wu;
reg         exe_is_mod_wu;
reg  [31:0] exe_rkd_value;

// MEM 级间寄存器
reg         mem_valid;
reg  [31:0] mem_pc;
reg  [31:0] mem_alu_result;
reg         mem_res_from_mem;
reg         mem_gr_we;
reg         mem_is_mul;      // MEM 级是乘法（乘积在 mul_prod_mem）
reg         mem_is_mulh;     // MEM 级是取高位的乘法
reg  [63:0] mul_prod_mem;    // 乘积流水寄存器：EXE→MEM 沿锁存，等 DSP 吸收
reg  [ 4:0] mem_dest;

// WB 级间寄存器
reg         wb_valid;
reg  [31:0] wb_pc;
reg  [31:0] wb_final_result;
reg         wb_gr_we;
reg  [ 4:0] wb_dest;

// regfile 端口
wire [31:0] rf_rdata1;
wire [31:0] rf_rdata2;
wire        rf_we;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;
wire [31:0] rf_rdata1_fwd;
wire [31:0] rf_rdata2_fwd;

// 数据冲突检测与前递（control）
wire        id_stall;
wire [ 1:0] fwd1_sel;
wire [ 1:0] fwd2_sel;
wire [31:0] exe_alu_result;    // EXE 组合结果，前递源之一
wire [31:0] exe_result;        // EXE 最终输出：ALU/除 二选一（乘法走 mul_prod_mem）
wire        exe_is_mul;         // EXE 级是乘法（结果迟到型，见 control.v）
wire [31:0] mem_final_result;  // MEM 组合结果，前递源之一

wire [31:0] alu_src1;
wire [31:0] alu_src2;


// ================== 1. IF1 实例化 ==================

IF_PC u_if_pc(
    .clk            (clk),
    .resetn         (resetn),
    .if2_allowin    (if2_allowin),
    .if1_fire       (if1_fire),
    .br_taken       (exe_br_taken),
    .br_target      (exe_br_target),
    .inst_sram_en   (inst_sram_en),
    .inst_sram_addr (inst_sram_addr),
    .if1_kill       (if1_kill),
    .if1_pc         (if1_pc)
);

assign inst_sram_we    = 4'b0;
assign inst_sram_wdata = 32'b0;


// ================== 2. 顶层 IF2 逻辑 ==================

assign if2_pc_out   = if2_pc;
assign if2_inst_out = if1_fire_r ? inst_sram_rdata : if2_inst;

// 被 kill 标记占位的槽位（错误路径响应当拍到达）视为空槽，允许接收新请求
assign if2_allowin = ~if2_valid || if2_fire || if1_kill_r;
assign if1_fire    = inst_sram_en && if2_allowin;
assign id_ready_go = ~id_stall;
assign id_allowin  = ~id_valid || (id_ready_go && exe_allowin);
// kill 标记的槽位是错误路径响应：允许被新请求覆盖（见 if2_allowin），但绝不允许流向 ID
// （exp8 纯阻塞下 bl/jirl 在 EXE 与 ID 阻塞同拍会触发 pend，kill 槽位到达时 ID 已空，不加门控会漏进 ID）
assign if2_fire    = if2_valid && id_allowin && ~if1_kill_r;

always @(posedge clk) begin
    if (!resetn)
        if2_valid <= 1'b0;
    else if (exe_br_taken)   // 分支冲刷：压过 if1_fire，清掉已在 IF2 的错误指令
        if2_valid <= 1'b0;
    else if (if1_fire)
        if2_valid <= 1'b1;
    else if (if2_fire)
        if2_valid <= 1'b0;
end

always @(posedge clk) begin
    if (!resetn)
        if2_pc <= 32'h1c000000;
    else if (if1_fire)
        if2_pc <= if1_pc;
end

always @(posedge clk) begin
    if (!resetn)
        if2_inst <= 32'h0340_0000;   // andi $r0,$r0,0 = LoongArch NOP
    else if (if2_fire | if1_kill_r)
        if2_inst <= 32'h0340_0000;
    else if (if1_fire_r)
        if2_inst <= inst_sram_rdata;
end

always @(posedge clk) begin
    if (!resetn) begin
        if1_kill_r <= 1'b0;
    end
    else if (if1_fire) begin
        if1_kill_r <= if1_kill;
    end
    else if (if2_fire) begin
        if1_kill_r <= 1'b0;
    end
end

always @(posedge clk) begin
    if (!resetn) begin
        if1_fire_r <= 1'b0;
    end
    else if (if1_fire) begin
        if1_fire_r <= 1'b1;
    end
    else  begin
        if1_fire_r <= 1'b0;
    end
end
// ================== 3. IF2 -> ID 级间寄存器 ==================

// id_valid：fire 进则置位，fire 出则清零；分支冲刷最高优先级
always @(posedge clk) begin
    if (!resetn)
        id_valid <= 1'b0;
    else if (exe_br_taken)
        id_valid <= 1'b0;
    else if (if2_fire)
        id_valid <= 1'b1;
    else if (id_fire)
        id_valid <= 1'b0;
end

always @(posedge clk) begin
    if (!resetn) begin
        id_pc   <= 32'h1c000000;
        id_inst <= 32'h0340_0000;
    end
    else if (if2_fire) begin
        id_pc   <= if2_pc_out;
        id_inst <= if2_inst_out;
    end
end


// ================== 4. ID 级 ==================

IDU u_IDU (
    .pc           (id_pc),
    .inst         (id_inst),
    .rj_value     (rf_rdata1_fwd),   // jirl 目标计算也吃前递
    .rf_raddr1    (id_rf_raddr1),
    .rf_raddr2    (id_rf_raddr2),
    .alu_op       (id_alu_op),
    .src1_is_pc   (id_src1_is_pc),
    .src2_is_imm  (id_src2_is_imm),
    .imm          (id_imm),
    .res_from_mem (id_res_from_mem),
    .gr_we        (id_gr_we),
    .mem_we       (id_mem_we),
    .dest         (id_dest),
    .br_target    (id_br_target),
    .is_beq       (id_is_beq),
    .is_bne       (id_is_bne),
    .is_jirl      (id_is_jirl),
    .is_bl        (id_is_bl),
    .is_b         (id_is_b),
    .is_mul_w     (id_is_mul_w),
    .is_mulh_w    (id_is_mulh_w),
    .is_mulh_wu   (id_is_mulh_wu),
    .is_div_w     (id_is_div_w),
    .is_mod_w     (id_is_mod_w),
    .is_div_wu    (id_is_div_wu),
    .is_mod_wu    (id_is_mod_wu)
);

// ================== regfile ==================

regfile u_regfile (
    .clk    (clk),
    .raddr1 (id_rf_raddr1),
    .rdata1 (rf_rdata1),
    .raddr2 (id_rf_raddr2),
    .rdata2 (rf_rdata2),
    .we     (rf_we),
    .waddr  (rf_waddr),
    .wdata  (rf_wdata)
);

assign rf_rdata1_fwd = ({32{fwd1_sel == 2'b01}} & exe_result      )
                     | ({32{fwd1_sel == 2'b10}} & mem_final_result)
                     | ({32{fwd1_sel == 2'b00}} & rf_rdata1       );
assign rf_rdata2_fwd = ({32{fwd2_sel == 2'b01}} & exe_result      )
                     | ({32{fwd2_sel == 2'b10}} & mem_final_result)
                     | ({32{fwd2_sel == 2'b00}} & rf_rdata2       );

assign alu_src1 = id_src1_is_pc ? id_pc : rf_rdata1_fwd;
assign alu_src2 = id_src2_is_imm ? id_imm : rf_rdata2_fwd;

// ================== 数据冲突检测与前递选择 ==================

control u_control(
    .id_valid         (id_valid),
    .id_rf_raddr1     (id_rf_raddr1),
    .id_rf_raddr2     (id_rf_raddr2),
    .exe_valid        (exe_valid),
    .exe_gr_we        (exe_gr_we),
    .exe_res_from_mem (exe_res_from_mem),
    .exe_is_mul       (exe_is_mul),
    .exe_dest         (exe_dest),
    .mem_valid        (mem_valid),
    .mem_gr_we        (mem_gr_we),
    .mem_dest         (mem_dest),
    .id_stall         (id_stall),
    .fwd1_sel         (fwd1_sel),
    .fwd2_sel         (fwd2_sel)
);

// ================== ID -> EXE 级间寄存器 ==================

assign exe_allowin = ~exe_valid || (exe_ready_go && mem_allowin);
assign id_fire     = id_valid && id_ready_go && exe_allowin;

always @(posedge clk) begin
    if (!resetn)
        exe_valid <= 1'b0;
    else if (exe_br_taken)   // 分支冲刷：压过 id_fire，挡住当拍正试图进入EXE的错误指令
        exe_valid <= 1'b0;
    else if (id_fire)
        exe_valid <= 1'b1;
    else if (exe_fire)
        exe_valid <= 1'b0;
end

always @(posedge clk) begin
    if (!resetn) begin
        exe_pc           <= 32'h1c000000;
        exe_alu_src1     <= 32'h0;
        exe_alu_src2     <= 32'h0;
        exe_alu_op       <= 12'h0;
        exe_mem_we       <= 1'b0;
        exe_res_from_mem <= 1'b0;
        exe_gr_we        <= 1'b0;
        exe_dest         <= 5'h0;
        exe_br_target    <= 32'h0;
        exe_is_beq       <= 1'b0;
        exe_is_bne       <= 1'b0;
        exe_is_jirl      <= 1'b0;
        exe_is_bl        <= 1'b0;
        exe_is_b         <= 1'b0;
        exe_is_mul_w     <= 1'b0;
        exe_is_mulh_w    <= 1'b0;
        exe_is_mulh_wu   <= 1'b0;
        exe_is_div_w     <= 1'b0;
        exe_is_mod_w     <= 1'b0;
        exe_is_div_wu    <= 1'b0;
        exe_is_mod_wu    <= 1'b0;
        exe_rkd_value    <= 32'h0;
    end
    else if (id_fire) begin
        exe_pc           <= id_pc;
        exe_alu_src1     <= alu_src1;
        exe_alu_src2     <= alu_src2;
        exe_alu_op       <= id_alu_op;
        exe_mem_we       <= id_mem_we;
        exe_res_from_mem <= id_res_from_mem;
        exe_gr_we        <= id_gr_we;
        exe_dest         <= id_dest;
        exe_br_target    <= id_br_target;
        exe_is_beq       <= id_is_beq;
        exe_is_bne       <= id_is_bne;
        exe_is_jirl      <= id_is_jirl;
        exe_is_bl        <= id_is_bl;
        exe_is_b         <= id_is_b;
        exe_is_mul_w     <= id_is_mul_w;
        exe_is_mulh_w    <= id_is_mulh_w;
        exe_is_mulh_wu   <= id_is_mulh_wu;
        exe_is_div_w     <= id_is_div_w;
        exe_is_mod_w     <= id_is_mod_w;
        exe_is_div_wu    <= id_is_div_wu;
        exe_is_mod_wu    <= id_is_mod_wu;
        exe_rkd_value    <= rf_rdata2_fwd;  // st_w 写数也吃前递
    end
end


// ================== 9. EXE 级组合逻辑 ==================

alu u_alu (
    .alu_op     (exe_alu_op),
    .alu_src1   (exe_alu_src1),
    .alu_src2   (exe_alu_src2),
    .alu_result (exe_alu_result)
);

// ================== 乘法器（exp10，行为级 *，综合进 DSP48） ==================
// 33 位统一有符号乘法：有符号扩符号位、无符号乘补 0，66 位积弃高 2 位
// mul.w 的低 32 位与有/无符号无关，故只有 mulh 两条需要区分
// 时序教训（exp10 初版 WNS -1.53ns）：33x33 = 2 个 DSP 级联 + fabric CARRY4 长尾，
// 再串 exe_result MUX 伸到 br_target/前递/MEM 锁存等 488 个端点，100MHz 收不掉。
// 改造：乘积在 EXE→MEM 沿打一拍（mul_prod_mem，供 Vivado 吸进 DSP 内部 PREG/MREG），
// 结果移出组合 exe_result；mul 在 control.v 里与 load 同构为「结果迟到型」。
assign    exe_is_mul  = exe_is_mul_w | exe_is_mulh_w | exe_is_mulh_wu;
wire        exe_is_mulh = exe_is_mulh_w | exe_is_mulh_wu;
wire [32:0] mul_a       = {exe_is_mulh_wu ? 1'b0 : exe_alu_src1[31], exe_alu_src1};
wire [32:0] mul_b       = {exe_is_mulh_wu ? 1'b0 : exe_alu_src2[31], exe_alu_src2};
wire [65:0] mul_prod    = $signed(mul_a) * $signed(mul_b);

// ================== 除法器（exp10，Xilinx Divider Generator IP × 1） ==================
// 只配一个无符号 IP：有符号除法先取绝对值送入，符号位启动拍锁存，出结果时恢复
// （商符号 = 两操作数异或，余数符号跟随被除数——手册规定）
// 反过来用有符号 IP 无法直接支持 div.wu/mod.wu（操作数 MSB 置位时会被误解为负数），
// 而无符号 IP + 外层符号恢复可同时覆盖有/无符号四条指令，故选无符号。
// 除数为 0 时手册规定"结果可以为任意值，但不触发例外"，故不做任何特判。
// tvalid 握手成功后必须撤销，否则 IP 认为来了新任务；div_doing 保证一次只启动一单。
// EXE 内指令是全流水最老的，不可能被冲刷，故除法器无需取消机制。
wire        exe_is_div     = exe_is_div_w | exe_is_mod_w | exe_is_div_wu | exe_is_mod_wu;
wire        exe_div_uns    = exe_is_div_wu | exe_is_mod_wu;
reg         div_doing;
reg         div_q_neg;     // 商应为负
reg         div_r_neg;     // 余数应为负

wire [31:0] div_a_abs = (~exe_div_uns & exe_alu_src1[31]) ? ~exe_alu_src1 + 32'd1 : exe_alu_src1;
wire [31:0] div_b_abs = (~exe_div_uns & exe_alu_src2[31]) ? ~exe_alu_src2 + 32'd1 : exe_alu_src2;

// NonBlocking 模式下 IP 无 tready：tvalid 打一拍即被无条件接收，启动拍 = div_tvalid 本身
wire        div_tvalid = exe_valid & exe_is_div & ~div_doing;
wire        div_dout_tvalid;
wire [63:0] div_dout_tdata;

wire div_in_fire = div_tvalid;
wire div_done    = div_dout_tvalid;

always @(posedge clk) begin
    if (!resetn)          div_doing <= 1'b0;
    else if (div_in_fire) div_doing <= 1'b1;
    else if (div_done)    div_doing <= 1'b0;
end

always @(posedge clk) begin
    if (div_in_fire) begin
        div_q_neg <= ~exe_div_uns & (exe_alu_src1[31] ^ exe_alu_src2[31]);
        div_r_neg <= ~exe_div_uns &  exe_alu_src1[31];
    end
end

div_gen u_div (
    .aclk                   (clk),
    .s_axis_dividend_tvalid (div_tvalid),
    .s_axis_dividend_tdata  (div_a_abs),
    .s_axis_divisor_tvalid  (div_tvalid),
    .s_axis_divisor_tdata   (div_b_abs),
    .m_axis_dout_tvalid     (div_dout_tvalid),
    .m_axis_dout_tdata      (div_dout_tdata)
);

// IP 输出布局：[63:32]=商，[31:0]=余数；按启动时锁存的符号恢复
wire [31:0] quo_raw = div_dout_tdata[63:32];
wire [31:0] rem_raw = div_dout_tdata[31:0];
wire [31:0] quo     = div_q_neg ? ~quo_raw + 32'd1 : quo_raw;
wire [31:0] rem     = div_r_neg ? ~rem_raw + 32'd1 : rem_raw;
wire [31:0] div_result = (exe_is_mod_w | exe_is_mod_wu) ? rem : quo;

// EXE 最终输出：ALU / 除 二选一（乘法结果走 mul_prod_mem 流水寄存器，不在此列）
// 下游（MEM 锁存、前递源）统一看 exe_result
assign exe_result = exe_is_div ? div_result : exe_alu_result;

// 跳转判断：beq/bne 用 ALU sub 结果是否为 0
// 必须 exe_valid 门控：否则被冲刷进来的分支死数据会再次误触发重定向
assign exe_rj_eq_rkd = (exe_alu_result == 32'b0);
assign exe_br_taken = exe_valid &&
                      ((exe_is_beq && exe_rj_eq_rkd) ||
                       (exe_is_bne && !exe_rj_eq_rkd) ||
                       exe_is_jirl || exe_is_bl || exe_is_b);

// 数据 RAM 请求（本拍发出，下拍 MEM 级收 data_sram_rdata）
assign data_sram_en    = exe_valid && (exe_res_from_mem || exe_mem_we);
assign data_sram_we    = exe_mem_we ? 4'hf : 4'h0;
assign data_sram_addr  = exe_alu_result;
assign data_sram_wdata = exe_rkd_value;

// ================== 10. EXE -> MEM 级间寄存器 ==================

// 除法驻留等待：结果未出则 EXE 不放行，整条流水线自然停住
assign exe_ready_go = ~exe_is_div | div_done;
assign mem_allowin  = ~mem_valid || (mem_ready_go && wb_allowin);
assign exe_fire     = exe_valid && exe_ready_go && mem_allowin;

always @(posedge clk) begin
    if (!resetn)
        mem_valid <= 1'b0;
    else if (exe_fire)
        mem_valid <= 1'b1;
    else if (mem_fire)
        mem_valid <= 1'b0;
end

always @(posedge clk) begin
    if (!resetn) begin
        mem_pc           <= 32'h1c000000;
        mem_alu_result   <= 32'h0;
        mem_res_from_mem <= 1'b0;
        mem_gr_we        <= 1'b0;
        mem_dest         <= 5'h0;
        mem_is_mul       <= 1'b0;
        mem_is_mulh      <= 1'b0;
        mul_prod_mem     <= 64'h0;
    end
    else if (exe_fire) begin
        mem_pc           <= exe_pc;
        mem_alu_result   <= exe_result;   // 已是 ALU/除 选完的最终结果
        mem_res_from_mem <= exe_res_from_mem;
        mem_gr_we        <= exe_gr_we;
        mem_dest         <= exe_dest;
        mem_is_mul       <= exe_is_mul;   // 乘积与指令同拍搭车进 MEM 级
        mem_is_mulh      <= exe_is_mulh;
        mul_prod_mem     <= mul_prod[63:0];
    end
end

// ================== 11. MEM 级组合逻辑 ==================

// 三选一位掩码 MUX：load 数据 / 乘积（高低位）/ ALU 结果，one-hot 互斥，同 rf_rdata_fwd 风格
assign mem_final_result = ({32{mem_res_from_mem        }} & data_sram_rdata     )
                        | ({32{mem_is_mul & mem_is_mulh}} & mul_prod_mem[63:32] )
                        | ({32{mem_is_mul & ~mem_is_mulh}} & mul_prod_mem[31:0] )
                        | ({32{~mem_res_from_mem & ~mem_is_mul}} & mem_alu_result);

// ================== 12. MEM -> WB 级间寄存器 ==================

assign mem_ready_go = 1'b1;
assign wb_allowin   = 1'b1;
assign mem_fire     = mem_valid && mem_ready_go && wb_allowin;
assign wb_fire      = wb_valid && wb_allowin;

always @(posedge clk) begin
    if (!resetn)
        wb_valid <= 1'b0;
    else if (mem_fire)
        wb_valid <= 1'b1;
    else if (wb_fire)
        wb_valid <= 1'b0;
end

always @(posedge clk) begin
    if (!resetn) begin
        wb_pc           <= 32'h1c000000;
        wb_final_result <= 32'h0;
        wb_gr_we        <= 1'b0;
        wb_dest         <= 5'h0;
    end
    else if (mem_fire) begin
        wb_pc           <= mem_pc;
        wb_final_result <= mem_final_result;
        wb_gr_we        <= mem_gr_we;
        wb_dest         <= mem_dest;
    end
end

// ================== 13. WB 级组合逻辑 ==================

assign rf_we    = wb_gr_we && wb_valid;
assign rf_waddr = wb_dest;
assign rf_wdata = wb_final_result;

assign debug_wb_pc       = wb_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = wb_dest;
assign debug_wb_rf_wdata = wb_final_result;

endmodule
