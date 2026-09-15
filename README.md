# myCPU —— LoongArch32 六级流水线 CPU

基于 LoongArch32 精简指令集的教学 CPU，Verilog 实现，对接龙芯实验环境（类 SRAM 接口）。
当前状态：**exp7 / exp8 / exp9 全部完成**（六级流水 + 阻塞/冲刷/前递），**主频 100MHz**（xc7a200tfbg676-1）。

> 注意：100MHz 布线后 WNS ≈ -0.08ns，仅 3 个端点轻微违例（最差是 PC→指令 BRAM 地址的
> 纯布线延迟，以及 data RAM→前递→jirl 目标加法器路径），板上实测可运行；
> 若要严格收敛，见第 6 节末尾。

## 1. 已支持的指令（20 条）

| 类别    | 指令                                                  |
| ----- | --------------------------------------------------- |
| 算术/逻辑 | `add.w` `sub.w` `slt` `sltu` `and` `or` `nor` `xor` |
| 移位    | `slli.w` `srli.w` `srai.w`                          |
| 立即数   | `addi.w` `lu12i.w`                                  |
| 访存    | `ld.w` `st.w`                                       |
| 跳转    | `b` `bl` `beq` `bne` `jirl`                         |

尚未支持：乘除法、字节/半字访存、例外/中断/CSR、TLB（后续实验在此基础上扩展）。

## 2. 文件结构

```
mycpu_top.v    顶层：六级流水骨架，全部级间寄存器、握手、前递 MUX、访存接口
IF_PC.v        IF1 级：PC 寄存器、取指请求、分支重定向（含 pend 挂起）
IDU.v          ID 级：指令译码，生成 ALU 操作码/立即数/读写控制/分支目标
control.v      数据冲突检测：load-use 阻塞 + EXE/MEM 前递选择（纯组合）
alu.v          EXE 级：12 种操作的组合逻辑 ALU
regfile.v      32×32 寄存器堆，r0 恒 0，内部写读旁路
decoder_*.v    实验模板译码器（当前未例化，IDU 用移位做 one-hot）
```

## 3. 流水线结构

```
        ┌────────────── 前端（取指）──────────────┐
 IF1          IF2           ID           EXE          MEM          WB
┌───────┐  ┌────────┐  ┌─────────┐  ┌──────────┐  ┌─────────┐  ┌─────────┐
│ PC 寄存 │  │ 收 BRAM │  │ 译码 IDU │  │ ALU 运算  │  │ 收 data  │  │ 写回     │
│ 发取指  │→ │ 响应    │→ │ 读 regfile│→ │ 分支裁决  │→ │ RAM 响应 │→ │ regfile  │
│ 请求    │  │ kill 处理│  │ 冲突检测 │  │ 发访存请求│  │          │  │ debug 输出│
└───────┘  └────────┘  └─────────┘  └──────────┘  └─────────┘  └─────────┘
     ▲                                   │
     └───────────────────────────────────┘
         分支重定向 br_taken / br_target（来自 EXE，打回 IF1 的 PC）
         冲刷 IF1 / IF2 / ID 三级错误路径指令；
         EXE 的分支自身（bl/jirl 要写 link）正常流向 MEM / WB
```

为什么取指拆成 IF1 + IF2 两级：指令 BRAM 是**同步读**——本拍发地址，下一拍数据才回来。
IF1 发请求，IF2 收响应。数据 RAM 同理：EXE 拍发请求，MEM 拍收 `data_sram_rdata`。

## 4. 握手协议（读懂代码的关键）

每级都用同一套四个信号，模板完全一致：

| 信号           | 含义                                           |
| ------------ | -------------------------------------------- |
| `x_valid`    | 本级寄存器里有没有有效指令                                |
| `x_ready_go` | 本级组合逻辑本拍能否算完（目前只有 ID 会因冲突为 0）                |
| `x_allowin`  | 是否允许上一级打进来：`~x_valid                         |
| `x_fire`     | 握手成功：`x_valid && x_ready_go && next_allowin` |

级间寄存器统一套路：**fire 进则置 valid，fire 出则清 valid，数据只在进时锁存**。
看任何一级时，先找它的 `valid` always 块和数据锁存 always 块，逻辑立刻清晰。

## 5. 三大冲突处理机制（exp8/9 的核心）

### 5.1 前递（forwarding）

- EXE→ID、MEM→ID 两级前递，在 `control.v` 里做纯组合的地址比较，`fwd1_sel/fwd2_sel`
  在 `mycpu_top.v` 选通： `00=regfile  01=EXE 结果  10=MEM 结果`（就近优先）。
- `st.w` 的写数（`exe_rkd_value`）和 `jirl` 的目标计算（`rj_value`）也吃前递。
- WB→ID 的同拍冲突由 `regfile.v` 内部的写读旁路解决，不占用前递通道。
- IDU 把"假读"的寄存器地址钳到 r0（`need_rj/need_rkd` 掩码），r0 天然无相关，
  使 `control.v` 退化成纯等值比较，不用懂指令语义。

### 5.2 阻塞（stall）

唯一前递救不了的情况：**load 后紧跟使用者**（load 数据 MEM 拍末才从 BRAM 回来，
使用者在 EXE 拍头就要，物理上差一拍）。此时 `id_stall` 拉高：
ID 停住 → 前端随之冻结 → EXE 进一个 bubble，一拍后从 MEM 前递解决。

### 5.3 冲刷（flush）

分支在 **EXE 级裁决**（`beq/bne` 用 ALU 减法结果判零，`b/bl/jirl` 无条件跳）。
`exe_br_taken` 有效时，分支后面的三条错误路径指令全部作废：

- **IF1**：本拍在飞的取指请求地址是错误路径，由 `if1_kill` 标记，响应到达时 IF2 置 NOP；
- **IF2 / ID**：`if2_valid` / `id_valid` 同拍清零；
- **EXE**：分支自身**不被冲刷**（本拍 `exe_fire=1` 正常送入 MEM，`bl/jirl` 的 link 写回不受影响）。
  `exe_valid` 在 `exe_br_taken` 时清零，是为了挡住当拍正从 ID 经 `id_fire` 进来的错误指令。

注意 `exe_br_taken` 必须带 `exe_valid` 门控，否则被冲刷的死数据会二次误触发重定向。

### 5.4 前端的两个配套机制（IF_PC.v / IF2 逻辑）

- **pend 挂起**：`br_taken` 当拍若前端被 stall 反压、取指请求发不出去，跳转目标会随
  `br_taken` 一拍后消失而丢失，故锁存进 `pend_target`，下一拍装填进 PC。
- **if1_kill**：pend 装填拍 / `br_taken` 拍发出的取指请求，其地址属于错误路径，
  标记随请求发出，响应到达时 IF2 把该指令置 NOP（LoongArch NOP = `0x03400000`，
  即 `andi $r0,$r0,0`）。

## 6. 主频 100MHz 是怎么来的

曾经的关键路径（50MHz 版，WNS≈1.8ns，布线占 86%）：

```
id_inst 译码 → 读地址生成 → control 冲突检测 → id_stall
             → id_allowin → if2_fire → if2_allowin → inst_sram_en → 指令 BRAM 使能
```

一条组合链横跨 ID/IF2/IF1 三级再横穿整个芯片连到 200+ 块 RAMB36 的使能端。
优化手段：**取指常开**——`inst_sram_en = resetn`（IF_PC.v），反正取指是只读的、
多发请求无副作用，错误路径的响应本来就有 `if1_kill` 机制兜底。
stall 时 PC 不更新，只是重复取同一条指令，IF2 槽位被占着，响应直接丢弃即可。
这一刀切断了整条组合链，实现后 cpu_clk 从 50MHz 提到 100MHz。

100MHz 下仅剩的 3 个轻微违例端点（供后续收紧参考）：

1. `u_if_pc/pc_reg[2]/[11]` → 指令 BRAM `ADDRARDADDR`（0 级逻辑、~95% 纯布线）
   —— PC 寄存器到 BRAM 地址口太远，可靠布局约束（pblock 拉近 CPU 与 inst_ram）解决；
2. `data_ram` 读出 → MEM 前递 → IDU jirl 目标加法器 → `exe_br_target_reg[30]`
   （14 级逻辑）—— jirl 目标计算在 ID 级，串了"BRAM 读出→前递 MUX→加法器"一整条链。

**教训/经验**：给 BRAM/存储器的使能信号尽量不要挂在一拍内跨多级的组合逻辑后面；
"多发无害的请求 + 响应侧丢弃"往往比"精确控制请求"时序好得多。

## 7. 与 SoC 的接口约定

- `inst_sram_*`：指令 BRAM，同步读，CPU 只读（`we` 恒 0）。
- `data_sram_*`：数据 BRAM，同步读；EXE 拍发 `en/we/addr/wdata`，MEM 拍收 `rdata`。
- `debug_wb_*`：写回级追踪信号，实验环境用来和 golden trace 比对。
- 复位：`resetn` 低有效，PC 复位到 `0x1c000000`。

## 8. 给队友的开发指引

### 加一条新指令要动哪里

1. `IDU.v`：加 `inst_xxx` 译码 → 挂到 `alu_op`/立即数/操作数选择/写回控制上
   → 如需新读口习惯，更新 `need_rj`/`need_rkd`；
2. `alu.v`：若需要新运算，扩 `alu_op` 位宽并加运算分支；
3. `mycpu_top.v`：若引入新的级间信号，在头部声明区补声明，并挂进 ID→EXE（及后续）
   级间寄存器；
4. 冲突检测一般**不用动**——`control.v` 只看地址不看指令。

### 改代码时的注意事项

- 级间寄存器动 `valid` 逻辑时，先想清除和 `exe_br_taken` 冲刷的优先级关系。
- 任何"本拍发、下拍收"的存储器请求，撤回是不可能的——用 kill/丢弃思路解决，
  不要试图在请求侧做精确控制（见第 6 节）。
- 时钟约束在 SoC 侧（exp9/soc_verify 工程的 xdc），改主频去那里，CPU 内部无时钟假设。

### 验证流程

- 功能验证：`exp9/func` 下的测试程序（`make` 生成 inst_ram.coe），在
  `exp9/soc_verify/soc_bram` 跑 Vivado 仿真，与 `gettrace/golden_trace.txt` 比对。
- 上板/时序：`exp9/soc_verify/soc_bram/run_vivado` 工程实现后看
  `soc_lite_top_timing_summary_routed.rpt` 的 WNS。

## 9. 提交历史（设计演进参考）

```
bd7c145  exp6 original code（单周期）
dce3b59  exp7: create a 6-pipeline stage CPU（搭骨架）
c93e59e  分支冲刷：清各级 valid
4a6ba65  统一 NOP 编码 0x03400000
715ca3d  IDU 假读钳零到 r0，简化冲突检测
3227ac6  regfile 写读旁路，解决 WB→ID 同拍冲突
7b11fe5  wb_valid 统一进置出清模板
6616327  exp8&9: support pipeline stall, flush and forwarding
4c104e9  perf: 取指常开，主频 50MHz → 100MHz
```
