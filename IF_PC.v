module IF_PC(
    input         clk,
    input         resetn,

    // 反压：IF2 允许接收时才发起取指
    input         if2_allowin,

    // 传递成功：IF1->IF2 链路打通，允许更新 PC
    input         if1_fire,

    // 跳转（来自 EX 级，经顶层转发）
    input         br_taken,
    input  [31:0] br_target,

    // 指令 BRAM 接口
    output        inst_sram_en,     // 高有效：IF2 能收且非复位时才读
    output [31:0] inst_sram_addr,   // 当前 PC
    output        if1_kill,         // 本拍若 fire，其地址必为错误路径（pend 装填拍或 br_taken 拍）
                                    // 标记随请求发出，响应到达时由 IF2 丢弃对应指令

    // 输出
    output [31:0] if1_pc            // 当前 PC 寄存器值
);

    // ================== 挂起重定向 ==================
    // br_taken 当拍若 fire 不出去（前端被数据冲突 stall 反压），
    // 跳转目标会随 br_taken 一拍后消失而丢失，故锁存进 pending：
    // 下一拍把 pend_target 装填进 pc。装填拍照常 fire（握手连续性），
    // 但此时地址还是旧 pc，属错误路径，由 if1_kill 标记、IF2 收到后置 NOP。
    // pend_valid 与新的 br_taken 互斥：每次 br_taken 必冲刷前端，
    // pending 存活期（1拍）内不可能有新分支流到 EXE。
    reg        pend_valid;
    reg [31:0] pend_target;

    wire br_miss_fire = br_taken & ~if1_fire;   // 想跳但跳不成

    always @(posedge clk) begin
        if (!resetn) begin
            pend_valid  <= 1'b0;
            pend_target <= 32'h0;
        end
        else if (br_miss_fire) begin
            pend_valid  <= 1'b1;
            pend_target <= br_target;
        end
        else if (pend_valid)            // 装填进 pc 的同一拍释放
            pend_valid <= 1'b0;
    end

    // ================== next_pc：pc 的唯一数据源 ==================
    // 三路互斥，位掩码无需优先级：
    //   - pend_valid：挂起重定向装填（本拍 inst_sram_en=0 不 fire；存活期 1 拍内
    //     前端被冲刷掏空，不可能有新 br_taken，故与第二路互斥）
    //   - br_taken：当拍判出的跳转
    //   - 默认 pc+4 顺序流
    // pc 的更新条件也随之统一：pending 装填拍 或 正常 fire 拍
    reg  [31:0] pc;

    wire [31:0] next_pc = {32{ pend_valid             }} & pend_target
                        | {32{~pend_valid &  br_taken }} & br_target
                        | {32{~pend_valid & ~br_taken }} & (pc + 32'h4);

    always @(posedge clk) begin
        if (!resetn)
            pc <= 32'h1c000000;         // 同步复位到程序入口
        else if (pend_valid | if1_fire)
            pc <= next_pc;
    end

    // ================== 输出 ==================
    assign if1_pc         = pc;
    assign inst_sram_addr = pc;

    // 语义：IF2 能收我就读，复位期间不读。
    // pend 装填拍也照常发请求（握手连续性：已发起的事务不可撤回，
    // 将来换真实内存亦然），错误路径的响应由 if1_kill 标记、IF2 丢弃
    assign inst_sram_en   = if2_allowin & resetn;
    assign if1_kill       = pend_valid | br_taken;

endmodule
