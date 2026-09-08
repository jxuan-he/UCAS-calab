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
    
    // 输出
    output [31:0] if1_pc            // 当前 PC 寄存器值
);

    // ================== PC 寄存器 ==================
    reg [31:0] pc;

    always @(posedge clk) begin
        if (!resetn)
            pc <= 32'h1c000000;       // 同步复位到程序入口
        else if (if1_fire)
            pc <= br_taken ? br_target : pc + 32'h4;
    end

    // ================== 输出 ==================
    assign if1_pc         = pc;
    assign inst_sram_addr = pc;
    
    // 语义：IF2 能收我才读；复位期间不读
    assign inst_sram_en   = if2_allowin & resetn;

endmodule