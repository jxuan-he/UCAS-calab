# myCPU —— LoongArch32 六级流水线 CPU

基于 LoongArch32 精简指令集的教学 CPU，Verilog 实现，对接龙芯实验环境（类 SRAM 接口）。
当前支持 exp12 的 syscall 例外和 exp13 的通用例外、软件中断、定时器中断及稳定计数器。
`environment/exp12` 与 `environment/exp13` 的 `myCPU` 目录均已放入对应 RTL。
两套工程的 PLL 配置要求 `cpu_clk=100MHz`，时序结果以各自的布线报告为准。

## 1. 已支持的指令

| 类别    | 指令                                                                                |
| ----- | --------------------------------------------------------------------------------- |
| 算术/逻辑 | `add.w` `sub.w` `slt` `sltu` `and` `or` `nor` `xor`                              |
| 移位    | `slli.w` `srli.w` `srai.w` `sll.w` `srl.w` `sra.w`                                |
| 立即数   | `addi.w` `lu12i.w` `slti` `sltui` `andi` `ori` `xori` `pcaddu12i`                  |
| 乘除法   | `mul.w` `mulh.w` `mulh.wu` `div.w` `mod.w` `div.wu` `mod.wu`                       |
| 访存    | `ld.w` `st.w` `ld.b` `ld.h` `ld.bu` `ld.hu` `st.b` `st.h`                          |
| 跳转    | `b` `bl` `beq` `bne` `blt` `bge` `bltu` `bgeu` `jirl`                            |
| 陷入/CSR | `syscall` `break` `ertn` `csrrd` `csrwr` `csrxchg` `rdcntvl.w` `rdcntvh.w` `rdcntid` |

同步例外支持 `SYS`、`BRK`、`INE`、`IPE`、取指地址不对齐 `ADEF`、访存地址不对齐 `ALE`。
例外信息随指令流到 WB 级统一提交，`ERA`、`ESTAT`、`PRMD` 等由 `CP0.v` 更新；
`EENTRY` 必须由软件先配置到实际可取指的 4 KiB 对齐入口。当前仅支持直接地址模式和
`ECFG.VS=0` 的统一入口。软件中断与定时器中断支持 `ECFG.LIE` 和 `CRMD.IE` 门控；
外部硬件中断、TLB、分页及其相关例外尚未实现。

`CP0.v` 内部统一采用 `cp0_<LoongArch CSR>_<字段>` 命名。教材中的 MIPS
`Status/Cause/EPC/BadVAddr/Count/Compare` 在本设计中按功能分别对应
`CRMD+PRMD+ECFG/ESTAT/ERA/BADV/稳定计数器/TCFG+TVAL+TICLR`；这些寄存器的格式和语义并不
完全相同，因此 RTL 保留 LoongArch 架构名。

## 2. 文件结构

```
mycpu_top.v    顶层：六级流水骨架，全部级间寄存器、握手、前递 MUX、访存接口
IF_PC.v        IF1 级：PC 寄存器、取指请求、分支重定向（含 pend 挂起）
IDU.v          ID 级：指令译码，生成 ALU 操作码/立即数/读写控制/分支目标
CP0.v          实验 CP0 模块：LoongArch32 CSR、软件/定时器中断、稳定计数器
control.v      数据冲突检测：load-use 阻塞 + EXE/MEM 前递选择（纯组合；MEM 级 load 不前递）
alu.v          EXE 级：12 种操作的组合逻辑 ALU
regfile.v      32×32 寄存器堆，r0 恒 0，内部写读旁路
div_gen.v      迭代无符号除法器，兼容 Vivado 2019.2
tests/         同步例外与精确冲刷的 Icarus Verilog 集成仿真
```

原仓库 `ip/div_gen/` 是 Vivado 2023.2 产物。exp12/exp13 改用同名的
`div_gen.v` 迭代除法器，避免 Vivado 2019.2 的 IP 版本不兼容。

EXE 级另有：乘法器（33 位统一有符号 `*` 进 DSP48，乘积 EXE→MEM 沿打一拍）、
除法器（RTL `div_gen`，无符号、32 拍运算；
有符号除法取绝对值送入、出结果按锁存符号恢复，余数符号跟随被除数）。

## 2.1 本次工作整理（不含 `environment/`）

本次改动围绕 exp12/exp13 的异常与中断处理、精确陷入、时序收敛和实验报告展开。这里按仓库根目录中的 RTL、仿真、图表和报告文件整理；实验工程目录不在本节逐项列举。

| 文件或目录 | 本次变化与作用 |
| --- | --- |
| `mycpu_top.v` | 将异常信息随指令从 ID 级传到 WB 级，在 WB 精确提交陷入；保存异常 PC 与必要的坏地址，屏蔽异常指令的 GPR/CSR 写回，并冲刷流水线中的年轻指令。加入 CSR 指令、`ertn`、软件/定时器中断、稳定计数器及其流水级控制。 |
| `CP0.v` | 新增 LoongArch CSR 状态模块，集中管理 `CRMD`、`PRMD`、`ECFG`、`ESTAT`、`ERA`、`BADV`、`EENTRY` 等寄存器，以及定时器和稳定计数器。 |
| `IDU.v` | 扩展特权指令和计数器指令译码，识别 `syscall`、`break`、`ertn`、CSR 操作及非法指令；将 `rj` 读地址直接接到指令字段，读寄存器语义仍单独用于相关停顿判断。 |
| `control.v` | 使用译码得到的 `rj` 使用标志控制相关停顿，同时保留寄存器地址比较和前递命中，避免无效指令译码链进入读地址/前递组合路径。 |
| `IF_PC.v` | 接入陷入入口和 `ertn` 返回重定向，并处理重定向期间的取指响应丢弃。 |
| `div_gen.v` | 新增纯 RTL 迭代无符号除法器，供较旧版本 Vivado 工程使用；有符号运算由 CPU 外层取绝对值并恢复符号。 |
| `README.md` | 更新支持功能、模块分工、陷入/返回行为、时序优化背景和本次文件变化说明。 |

### 本次实现的关键行为

- 同步例外在流水线中携带原因码与指令 PC，到 WB 级统一更新 CSR 并重定向到 `EENTRY`；`ertn` 在 WB 恢复 `PRMD` 保存的处理前特权级/中断使能状态，并返回 `ERA`。
- 通过较老指令优先提交和抑制年轻指令副作用实现精确陷入：异常或返回指令尚未提交时，年轻 store 不得发出写请求，年轻分支/除法操作也需被抑制。
- `rj` 地址直连优化消除了指令识别、`need_rj` 掩码对寄存器堆读地址的组合影响；`rj` 是否参与当前指令仍用于判断是否需要因数据相关而停顿。
- 时序记录聚焦 exp13：100 MHz 对应 10 ns 周期。优化前关键路径从 `id_inst_reg[27]/C` 到 `exe_br_target_reg[30]/D`，延迟 10.220 ns、WNS=-0.286 ns；`rj` 读地址直连后，这条译码/前递链被切断，优化后的关键路径转到 `exe_alu_src2_reg[4]/C` 至 Data RAM `ENARDEN`，延迟 9.687 ns、WNS=+0.002 ns。报告也记录了这轮调整的原因和路径变化。

## 3. 流水线结构

```
        ┌────────────── 前端（取指）──────────────┐
 IF1          IF2           ID           EXE          MEM          WB
┌───────┐  ┌────────┐  ┌─────────┐  ┌──────────┐  ┌─────────┐  ┌─────────┐
│ PC 寄存 │  │ 收 BRAM │  │ 译码 IDU │  │ ALU 运算  │→ │ 收 data  │→ │ 写回     │
│ 发取指  │→ │ 响应    │→ │ 读 regfile│→ │ 分支裁决  │  │ RAM 响应 │  │ regfile  │
│ 请求    │  │ kill 处理│  │ 冲突检测 │  │ 发访存请求│  │ （仅锁存） │  │ load 抽取 │
└───────┘  └────────┘  └─────────┘  └──────────┘  └─────────┘  └─────────┘
     ▲                                   │
     └───────────────────────────────────┘
         分支重定向 br_taken / br_target（来自 EXE，打回 IF1 的 PC）
         冲刷 IF1 / IF2 / ID 三级错误路径指令；
         EXE 的分支自身（bl/jirl 要写 link）正常流向 MEM / WB
```

为什么取指拆成 IF1 + IF2 两级：指令 BRAM 是**同步读**——本拍发地址，下一拍数据才回来。
IF1 发请求，IF2 收响应。数据 RAM 同理：EXE 拍发请求，MEM 拍收 `data_sram_rdata`——但**只锁存不消费**，
load 数据统一在 WB 拍交付（抽取/扩展也放 WB），原因见 5.2。

## 4. 握手协议（读懂代码的关键）

每级都用同一套四个信号，模板完全一致：

| 信号           | 含义                                           |
| ------------ | -------------------------------------------- |
| `x_valid`    | 本级寄存器里有没有有效指令                                |
| `x_ready_go` | 本级组合逻辑本拍能否算完（ID 会因冲突为 0；EXE 在除法驻留期间为 0）          |
| `x_allowin`  | 是否允许上一级打进来：`~x_valid                         |
| `x_fire`     | 握手成功：`x_valid && x_ready_go && next_allowin` |

级间寄存器统一套路：**fire 进则置 valid，fire 出则清 valid，数据只在进时锁存**。
看任何一级时，先找它的 `valid` always 块和数据锁存 always 块，逻辑立刻清晰。

## 5. 三大冲突处理机制（exp8/9 的核心）

### 5.1 前递（forwarding）

- EXE→ID、MEM→ID 两级前递，在 `control.v` 里做纯组合的地址比较，`fwd1_sel/fwd2_sel`
  在 `mycpu_top.v` 选通： `00=regfile  01=EXE 结果  10=MEM 结果`（就近优先）。
- **MEM 级前递只服务 ALU/乘法结果；load 不走 MEM 前递**（见 5.2）。
- `st.x` 的写数（`exe_rkd_value`）和 `jirl` 的目标计算（`rj_value`）也吃前递。
- WB→ID 的同拍冲突由 `regfile.v` 内部的写读旁路解决，不占用前递通道。
- `rj` 读地址直接取指令字段，避免 `known_inst → need_rj → 地址掩码` 进入读地址和前递组合链；
  `rj_used` 仍用于控制无关数据冲突造成的停顿。`rkd` 地址仍按指令语义屏蔽无效读，
  `control.v` 的前递命中继续按寄存器地址比较。

### 5.2 阻塞（stall）

唯一前递救不了的情况：**load 后紧跟使用者**。本设计里 load 统一「WB 拍交付」：
EXE 发地址 → MEM 拍 BRAM 出数**只锁存**进 `wb_sram_rdata`（不消费、不前递）→ WB 拍
做字节/半字抽取+扩展、写 regfile。消费者 d=1 停 2 拍、d=2 停 1 拍，最后经 regfile
写读旁路拿到 WB 拍抽好的值。

为什么不让 ld.w 走 MEM 前递（能少停一拍）？因为「BRAM 出数当拍串前递+加法器+锁存」
是天生最长的组合链（exp11 初版 WNS=-0.94ns 全毁在这条链上）；而且真实 cache 的
出数延迟可变，MEM 前递依赖「恰好 1 拍出数」的假设，扩展性为零。用不到 1% 的 CPI
（func 实测多停 871 拍/15 万拍）换时序收敛 + 架构统一 + cache 就绪。

### 5.3 冲刷（flush）

分支在 **EXE 级裁决**（`beq/bne` 用 ALU 减法结果判零，`blt/bge/bltu/bgeu` 复用
slt/sltu 比较结果最低位，`b/bl/jirl` 无条件跳）。
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

### exp10/11 的两轮时序修复

1. **乘法流水化（exp10）**：单周期 33×33 乘法（DSP48 级联+CARRY4）WNS=-1.53ns，
   乘积改到 EXE→MEM 沿锁存、高低位选择挪 MEM 级，mul 与 load 同构为「结果迟到型」。
2. **load 统一 WB 交付（exp11）**：子字访存加入后，MEM 级的字节/半字抽取逻辑压垮
   「BRAM 出数→抽取→前递→ID/EXE 锁存」链（WNS=-0.94ns）。修复分两步：抽取先挪 WB 级
   （-0.18ns），再撤掉 ld.w 的 MEM 前递、load 全走 WB 交付，BRAM 出数只接寄存器，
   整类长链消除。收敛依赖布线后物理优化：策略 `Performance_ExplorePostRoutePhysOpt`
   （phys_opt 前 -0.249ns → 后 +0.071ns；违规端点 17 个、TNS -1.56ns，布线占 70~84%，
   属实现噪声量级，phys_opt 一次清掉）。
   代价：load-use d=1 停 2 拍、d=2 停 1 拍，func 实测仅多停 871 拍（0.58% 执行时间）。

**教训/经验**：给 BRAM/存储器的使能信号尽量不要挂在一拍内跨多级的组合逻辑后面；
"多发无害的请求 + 响应侧丢弃"往往比"精确控制请求"时序好得多；存储器输出当拍只锁存、
不消费，是流水线 CPU 对接存储层次结构（cache/总线）的正确姿势。

## 7. 与 SoC 的接口约定

- `inst_sram_*`：指令 BRAM，同步读，CPU 只读（`we` 恒 0）。
- `data_sram_*`：数据 BRAM，同步读；EXE 拍发 `en/we/addr/wdata`，MEM 拍收 `rdata`。
  写支持字节使能（`st.b` 单道 / `st.h` 双道移位生成）；读数据锁存进 WB 拍再抽取。
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

乘法/除法照此办理了「不改动 control.v」：乘法当拍出结果，前递天然覆盖；除法驻留期间
消费者被 `exe_allowin=0` 挡住，完成拍走正常 EXE 前递通路。

### 改代码时的注意事项

- 级间寄存器动 `valid` 逻辑时，先想清楚 WB 陷入/`ertn` 与 EXE 分支的冲刷优先级。
- 任何"本拍发、下拍收"的存储器请求，撤回是不可能的——用 kill/丢弃思路解决，
  不要试图在请求侧做精确控制（见第 6 节）。
- 时钟约束在 SoC 侧。exp12/exp13 工程将 PLL 的 `cpu_clk` 配成 100 MHz。



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
e1f3a3c  删除 exp6 遗留的模板译码器
753020c  exp8&9: 堵住被 kill 的 IF2 槽位泄进 ID（exp8 纯阻塞首次暴露 pend 路径）
87803fc  exp10: 9 条算逻指令（slti/sltui/andi/ori/xori/sll.w/srl.w/sra.w/pcaddu12i）
bc88ad3  exp10: 7 条乘除指令（DSP48 单周期乘法 + div_gen IP 多周期除法驻留）
c7da39e  exp10: 乘积 EXE→MEM 沿锁存，100MHz WNS 收敛
86a90af  exp11: 4 条转移指令（blt/bge/bltu/bgeu，复用 slt/sltu 比较）
cbfe9bb  exp11: 6 条访存指令 + load 统一 WB 交付，WNS +0.063ns
```
