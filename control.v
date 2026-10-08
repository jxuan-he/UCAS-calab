// control.v —— 数据冲突检测与前递选择
// 职责边界：只做纯组合的地址比较与决策，不懂指令语义
//   - rj 地址直接来自指令字段；只在真实使用 rj 时计入停顿
//   - 前递命中保持纯地址比较，避免译码进入前递数据路径
//   - WB->ID（d=3）已由 regfile 内部写读旁路解决，这里只比较 EXE/MEM 两级
module control(
    // 消费侧：ID 级
    input  wire        id_valid,
    input  wire [ 4:0] id_rf_raddr1,
    input  wire [ 4:0] id_rf_raddr2,
    input  wire        id_rj_used,

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
    input  wire        mem_res_from_mem,   // MEM 是 load：数据统一 WB 拍才交付，MEM 不可前递

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

    // 阻塞：「结果迟到型」生产者（load 数据 WB 拍才写回；mul 乘积多打一拍）
    // load 统一 WB 拍交付：d=1（EXE 级）停两拍、d=2（MEM 级）停一拍，之后由 regfile 写读旁路供给
    assign id_stall = id_valid & ((exe_res_from_mem | exe_is_mul) & ((id_rj_used & exe_hit1) | exe_hit2)
                                | mem_res_from_mem & ((id_rj_used & mem_hit1) | mem_hit2));

    // 前递：就近优先（同地址双命中取 EXE）；load/mul 当拍无结果，不可作 EXE 前递源；
    // MEM 级 load 不可前递（数据未回），但此时 id_stall 拉高，消费者不锁存，此项为无关项
    assign fwd1_sel = (exe_hit1 & ~exe_res_from_mem & ~exe_is_mul) ? 2'b01 :
                       (mem_hit1 & ~mem_res_from_mem)              ? 2'b10 : 2'b00;
    assign fwd2_sel = (exe_hit2 & ~exe_res_from_mem & ~exe_is_mul) ? 2'b01 :
                       (mem_hit2 & ~mem_res_from_mem)              ? 2'b10 : 2'b00;

endmodule
