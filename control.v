// control.v —— 数据冲突检测与前递选择
// 职责边界：只做纯组合的地址比较与决策，不懂指令语义
//   - 假读已由 IDU 钳零到 r0，天然不误命中
//   - WB->ID（d=3）已由 regfile 内部写读旁路解决，这里只比较 EXE/MEM 两级
module control(
    // 消费侧：ID 级
    input  wire        id_valid,
    input  wire [ 4:0] id_rf_raddr1,
    input  wire [ 4:0] id_rf_raddr2,

    // 生产侧：EXE 级间寄存器
    input  wire        exe_valid,
    input  wire        exe_gr_we,
    input  wire        exe_res_from_mem,   // EXE 是 load 时 ALU 结果是地址，不可前递
    input  wire        exe_is_mul,         // EXE 是乘法时结果在 DSP 里流水，当拍不可前递
    input  wire [ 4:0] exe_dest,

    // 生产侧：MEM 级间寄存器
    input  wire        mem_valid,
    input  wire        mem_gr_we,
    input  wire [ 4:0] mem_dest,

    // 输出
    output wire        id_stall,           // 拉高：ID 停住，前端随之冻结，EXE 进 bubble
    output wire [ 1:0] fwd1_sel,           // rf_rdata1 前递选择：00=regfile 01=EXE 10=MEM
    output wire [ 1:0] fwd2_sel            // rf_rdata2 前递选择：同上
);

    // 命中检测：dest != 0 排除写 r0 的生产者（其值本就被丢弃，不能前递）
    wire exe_hit1 = exe_valid & exe_gr_we & (exe_dest != 5'd0) & (exe_dest == id_rf_raddr1);
    wire exe_hit2 = exe_valid & exe_gr_we & (exe_dest != 5'd0) & (exe_dest == id_rf_raddr2);
    wire mem_hit1 = mem_valid & mem_gr_we & (mem_dest != 5'd0) & (mem_dest == id_rf_raddr1);
    wire mem_hit2 = mem_valid & mem_gr_we & (mem_dest != 5'd0) & (mem_dest == id_rf_raddr2);

    // 阻塞：前递救不了的冲突是「结果迟到型」生产者的 d=1
    // - load：数据要 MEM 拍末才从 BRAM 回来，消费者 EXE 拍头就要，物理上差一拍
    // - mul ：乘积在 DSP 链里多打一拍（mul_prod_mem），EXE 当拍拿不出结果，同构处理
    assign id_stall = id_valid & (exe_res_from_mem | exe_is_mul) & (exe_hit1 | exe_hit2);

    // 前递：就近优先（EXE 比 MEM 新，同地址双命中时必须取 EXE）
    // EXE 是 load 时其 ALU 结果是访存地址而非数据、是 mul 时乘积还没出来，
    // 两种都不可作为 EXE 前递源；此时 id_stall 拉高，消费者当拍不锁存，fwd_sel 为无关项
    assign fwd1_sel = (exe_hit1 & ~exe_res_from_mem & ~exe_is_mul) ? 2'b01 :
                       mem_hit1                                    ? 2'b10 : 2'b00;
    assign fwd2_sel = (exe_hit2 & ~exe_res_from_mem & ~exe_is_mul) ? 2'b01 :
                       mem_hit2                                    ? 2'b10 : 2'b00;

endmodule
