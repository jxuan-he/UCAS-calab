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

// ================== 顶层信号声明（IF ~ ID 相关） ==================

// IF1
wire [31:0] if1_pc;

// IF2
wire        if1_fire;
wire        if2_fire;
wire        if2_allowin;
reg         if2_valid;
reg  [31:0] if2_pc;
reg  [31:0] if2_inst;
reg         if1_fire_r;
wire [31:0] if2_pc_out;
wire [31:0] if2_inst_out;

// ID 级间
wire        id_allowin;
wire        id_ready_go;
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

// 跳转（来自 EXE 级，由顶层转发）
wire        exe_br_taken;
reg  [31:0] exe_br_target;

// 级间握手信号（集中声明，必须先于使用点）
wire        exe_allowin;
wire        exe_ready_go;
wire        exe_fire;
wire        mem_allowin;
wire        mem_ready_go;
wire        mem_fire;
wire        wb_allowin;

// WB 级间寄存器
reg         wb_valid;
reg  [31:0] wb_pc;
reg  [31:0] wb_final_result;
reg         wb_gr_we;
reg  [ 4:0] wb_dest;

// regfile 读端口
wire [31:0] rf_rdata1;
wire [31:0] rf_rdata2;


// ================== 1. IF1 实例化 ==================

IF_PC u_if_pc(
    .clk            (clk),
    .resetn          (resetn),
    .if2_allowin    (if2_allowin),
    .if1_fire       (if1_fire),
    .br_taken       (exe_br_taken),
    .br_target      (exe_br_target),
    .inst_sram_en   (inst_sram_en),
    .inst_sram_addr (inst_sram_addr),
    .if1_pc         (if1_pc)
);

// BRAM 接口
assign inst_sram_we    = 4'b0;
assign inst_sram_wdata = 32'b0;


// ================== 2. 顶层 IF2 逻辑 ==================


assign if2_pc_out   = if2_pc;
assign if2_inst_out = if1_fire_r ? inst_sram_rdata : if2_inst;


assign if2_allowin = ~if2_valid || if2_fire;
assign if1_fire    = inst_sram_en && if2_allowin;
assign id_ready_go = 1'b1;
assign id_allowin  = ~id_valid || (id_ready_go && exe_allowin);
assign if2_fire    = if2_valid && id_allowin;


always @(posedge clk) begin
    if (!resetn)
        if2_valid <= 1'b0;
    else if (exe_br_taken)   // 分支冲刷：压过 if1_fire，拒收在途错误指令
        if2_valid <= 1'b0;
    else if (if1_fire)
        if2_valid <= 1'b1;
    else if (if2_fire)
        if2_valid <= 1'b0;
end

// if2_pc：if1_fire 时锁存发请求时的地址
always @(posedge clk) begin
    if (!resetn)
        if2_pc <= 32'h0;
    else if (if1_fire)
        if2_pc <= if1_pc;
end

// if2_inst：if2_fire 时清 NOP；if1_fire 的下一拍锁存 BRAM 数据
always @(posedge clk) begin
    if (!resetn)
        if2_inst <= 32'h0340_0000;   // andi $r0,$r0,0 = LoongArch NOP
    else if (if2_fire)
        if2_inst <= 32'h0340_0000;   // 打出后本级清空为 NOP
    else if (if1_fire_r)
        if2_inst <= inst_sram_rdata;
end

// if1_fire 延迟一拍，标记 BRAM 数据到达
always @(posedge clk) begin
    if (!resetn)
        if1_fire_r <= 1'b0;
    else
        if1_fire_r <= if1_fire;
end


// ================== 3. IF2 -> ID 级间寄存器 ==================

// id_valid：fire 进则置位，fire 出则清零；分支冲刷最高优先级
always @(posedge clk) begin
    if (!resetn)
        id_valid <= 1'b0;
    else if (exe_br_taken)   // 分支冲刷：ID级错误指令作废
        id_valid <= 1'b0;
    else if (if2_fire)
        id_valid <= 1'b1;
    else if (id_fire)
        id_valid <= 1'b0;
end

// 数据锁存：只在 if2_fire 时更新
always @(posedge clk) begin
    if (!resetn) begin
        id_pc   <= 32'h0;
        id_inst <= 32'h0340_0000;    // andi $r0,$r0,0 = LoongArch NOP
    end
    else if (if2_fire) begin
        id_pc   <= if2_pc_out;
        id_inst <= if2_inst_out;
    end
end


// ================== 4. ID 级==================

IDU u_IDU (
    .pc           (id_pc),
    .inst         (id_inst),
    .rj_value     (rf_rdata1),
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
    .is_b         (id_is_b)
);

// ================== regfile ==================

wire        rf_we;
wire [ 4:0] rf_waddr;
wire [31:0] rf_wdata;

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


wire [31:0] alu_src1 = id_src1_is_pc ? id_pc : rf_rdata1;
wire [31:0] alu_src2 = id_src2_is_imm ? id_imm : rf_rdata2;

// ================== ID -> EXE 级间寄存器 ==================

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
reg  [31:0] exe_rkd_value;     


assign       exe_allowin   = ~exe_valid || (exe_ready_go && mem_allowin);
wire        id_fire       = id_valid && id_ready_go && exe_allowin;


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
        exe_pc           <= 32'h0;
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
        exe_rkd_value    <= rf_rdata2;     
    end
end


wire [31:0] exe_alu_result;

// MEM 
reg         mem_valid;
reg  [31:0] mem_pc;
reg  [31:0] mem_alu_result;
reg         mem_res_from_mem;
reg         mem_gr_we;
reg  [ 4:0] mem_dest;

// ================== 9. EXE 级组合逻辑 ==================


alu u_alu (
    .alu_op     (exe_alu_op),
    .alu_src1   (exe_alu_src1),
    .alu_src2   (exe_alu_src2),
    .alu_result (exe_alu_result)
);

// 跳转判断：beq/bne 用 ALU sub 结果是否为 0
// 必须 exe_valid 门控：否则被冲刷进来的分支死数据会再次误触发重定向
wire exe_rj_eq_rkd = (exe_alu_result == 32'b0);
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

assign exe_ready_go = 1'b1;
assign mem_allowin  = ~mem_valid || (mem_ready_go && wb_allowin);  // wb_allowin 临时
assign exe_fire     = exe_valid && exe_ready_go && mem_allowin;

// mem_valid：fire 进则置位，fire 出则清零
always @(posedge clk) begin
    if (!resetn)
        mem_valid <= 1'b0;
    else if (exe_fire)
        mem_valid <= 1'b1;
    else if (mem_fire)
        mem_valid <= 1'b0;
end

// 数据锁存：只在 exe_fire 时更新
always @(posedge clk) begin
    if (!resetn) begin
        mem_pc           <= 32'h0;
        mem_alu_result   <= 32'h0;
        mem_res_from_mem <= 1'b0;
        mem_gr_we        <= 1'b0;
        mem_dest         <= 5'h0;
    end
    else if (exe_fire) begin
        mem_pc           <= exe_pc;
        mem_alu_result   <= exe_alu_result;
        mem_res_from_mem <= exe_res_from_mem;
        mem_gr_we        <= exe_gr_we;
        mem_dest         <= exe_dest;
    end
end

// ================== 11. MEM 级组合逻辑（顶层） ==================
wire [31:0] mem_final_result = mem_res_from_mem ? data_sram_rdata : mem_alu_result;

// ================== 12. MEM -> WB 级间寄存器 ==================
assign mem_ready_go = 1'b1;
assign wb_allowin   = 1'b1;     // WB 是最后一级，恒允许接收
assign mem_fire     = mem_valid && mem_ready_go && wb_allowin;

always @(posedge clk) begin
    if (!resetn)
        wb_valid <= 1'b0;
    else if (mem_fire)
        wb_valid <= 1'b1;
    else
        wb_valid <= 1'b0;
end

always @(posedge clk) begin
    if (!resetn) begin
        wb_pc           <= 32'h0;
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

// ================== 13. WB 级组合逻辑（顶层） ==================
// 写回 regfile
assign rf_we    = wb_gr_we && wb_valid;
assign rf_waddr = wb_dest;
assign rf_wdata = wb_final_result;

// debug
assign debug_wb_pc       = wb_pc;
assign debug_wb_rf_we    = {4{rf_we}};
assign debug_wb_rf_wnum  = wb_dest;
assign debug_wb_rf_wdata = wb_final_result;

endmodule