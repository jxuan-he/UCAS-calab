# exp14 实现与验证记录

日期：2026-10-27。平台：Windows，Vivado 2025.2，目标器件 xc7a200tfbg676-1。

## 实现边界

在 exp13 基线 `56138f0` 上改造，不新增指令，不设计 AXI 桥。取指和数据各保留最多一笔未响应事务；
数据端只在 MEM 空闲时接收新事务。IF_PC 使用 EMPTY/WAIT/HAVE/DROP，缓存不能立即交付 ID 的指令，
冲刷后仍消耗旧响应。非对齐取指通过内部异常槽进入 ID，不等待不存在的总线响应。

load/store 在 EXE 等待地址握手，进入 MEM 后均等待响应；没有发请求的异常指令不等待 data_ok。
保留 `older_redirect_pending` 的精确异常门控。分支只在 `exe_fire` 发生，避免 MEM 堵塞时丢失 bl/jirl；
除法结果缓存到指令离开 EXE，避免完成脉冲消失及重复启动。迭代除法器新增复位输入。

接口遵循本地类 SRAM 环境至少一周期响应的约定；每端不支持多笔 outstanding，也不支持新请求在其接收同沿立即返回。
CPU/从方中途单独复位后的跨复位事务恢复不在本次实验范围，整套环境共同复位。

## 根据时序路径完成的两项调整

基础路线通过功能仿真后，又根据实际网表路径作了两项调整：

1. 取指 `req` 不再直接受组合 `redirect` 门控，避免 EXE 地址/握手/分支链进入高扇出的指令 RAM 使能。
   若旧地址恰好在重定向同沿被接收，转入 DROP 并消耗它的响应。控制状态保证旧指令不进入 ID；
   “地址接收与冲刷同拍”已有单独的 XSIM 测试。
2. EXE 内增加一组请求寄存器，保存地址、写数据、字节选通、size 和 wr。
   只在 MEM 空且当前指令没有异常、更老指令不会重定向时分配请求；下一拍再参与总线握手。
   EXE 仍停留到请求接收，不增加并发事务数；MEM、WB 和精确异常规则不变。
   这切断了 ALU→地址译码→addr_ok→EXE 级使能的长组合链，每笔访存增加一拍内部准备。

时钟 IP 明确使用 PLL 原语，以保持实验自带 XDC 的 PLLE2_ADV 引脚引用有效。
初次采用工具默认 MMCM 的生成目录 `build/exp14` 不用于时序签核；
最终工程为 `build/exp14_final`，包含数据请求寄存的 RTL SHA-256 见 `validation/exp14/functional_results.json`。
功能回归日志继续保存在第一次导出的 XSIM 目录旁，但每次都重新编译根目录当前 RTL；
仿真采用 SoC 自带的时钟旁路，PLL/MMCM 差异不参与功能仿真。

## Vivado 官方 SoC 功能验证

使用原 exp14 `soc_hs_bram` 的 SoC、bridge_1x2、sram_wrap 和 confreg 逻辑，
由 Vivado 2025.2 重新生成 blk_mem_gen 和 clk_wiz IP，指令 RAM 采用原 exp14 `inst_ram.coe`。
没有用手写 RAM 模型替代下表的 Vivado 验证。原环境文件未修改；生成目录仅替换绝对 trace 路径、随机种子，并加入监测实例。

| 随机种子（23 位） | 类型 | 功能点 | CPU 周期 | I 接收/响应 | D 接收/响应 | DROP 消耗 |
| --- | --- | --- | ---: | --- | --- | ---: |
| 0x5500ff | 无随机掩码等待 | 58/58，最终 PASS | 430284 | 143188/143187 | 6167/6167 | 164 |
| 0x5501ff | 短延迟 | 58/58，最终 PASS | 1009189 | 124844/124844 | 6167/6167 | 3587 |
| 0x5527ff | 短延迟，另一种子 | 58/58，最终 PASS | 1011338 | 125046/125046 | 6167/6167 | 3736 |
| 0x550001 | 长延迟 | 58/58，最终 PASS | 1839388 | 119894/119894 | 6167/6167 | 1859 |
| 0x551234 | 长延迟，另一种子 | 58/58，最终 PASS | 1835005 | 119854/119854 | 6167/6167 | 1802 |

计数在程序结束事件采样。无随机等待场景此时有一笔尚未返回的前端预取，这是允许的；
全程监测每端 `accepted - responded` 始终处于 0～1，而不是强制程序结束当拍总线必须空闲。
所有数据事务均已完成。DROP 计数只统计进入 DROP 后消耗的响应，重定向与响应同拍直接丢弃不计入此列。

原 testbench 按有效 GPR 写回事件推进 golden trace，比较 PC、寄存器号和有效字节；
另监测孤立响应、重复请求、访存越过异常边界、MEM 提前离开和分支在未转移时触发。

原始日志：`build/exp14/final_reports/sim_*.log`；相对本目录的仓库根目录。

## Vivado XSIM 定向验证

`tests/tb_exp14_fetch.sv`：地址等待、ID 反压下保存响应、旧响应排空、响应/重定向同拍、ADEF 内部完成，全部通过。

`tests/tb_exp14_stress.sv`：完整 CPU，数据响应固定等待 80 拍；检查 load-use、store→load、
子字通道、错误路径 store 抑制、bl link，以及除法完成后继续被 MEM 阻塞。

结果：701 周期，除法只启动 1 次，结果缓存等待 45 拍，分支等待 81 拍，3 次合法写入；全部通过。

两组测试既经过 Icarus 交叉检查，也经过 Vivado XSIM 编译、展开和执行。
另用简化 RAM 模型交叉运行了短延迟完整 func，结果同为 58/58；该辅助结果不替代官方 IP 仿真。

## 时序验证

**通过：完整 SoC 已完成布局布线，CPU 和 timer 均为 100 MHz。**

| 指标 | 最终值 |
| --- | ---: |
| 时钟周期 | 10.000 ns |
| WNS / TNS | +0.209 ns / 0.000 ns |
| 建立时间失败端点 | 0 / 13014 |
| WHS / THS | +0.051 ns / 0.000 ns |
| 保持时间失败端点 | 0 / 13014 |
| 最小脉宽裕量 WPWS | +3.000 ns |
| 无时钟的寄存器时序端点 | 0 |
| 未约束的内部时序端点 | 0 |
| LUT / 寄存器 | 3284 / 2679 |
| RAMB36 / DSP | 320 / 4 |

Vivado 报告明确给出 `All user specified timing constraints are met.`。
签核由重新打开最终 `soc_lite_top_routed.dcp` 独立导出，脚本退出码 0，
与功能验证所记录的根目录 RTL SHA-256 一致。源码阶段提交为 `056748b`。

报告已复制到 `validation/exp14/`，含 `timing_100MHz.rpt`、`check_timing_100MHz.rpt`、
`clocks_100MHz.rpt`、`utilization_100MHz.rpt`、`drc_100MHz.rpt`，以及机器可读的
`functional_results.json`、`timing_results.json` 和精简的 `functional_summary.txt`。

签核范围沿用实验自带 XDC：CPU↔timer 的两条 false path 保留，未另外添加例外来隐藏 CPU 内部违例。
实验 XDC 未给 15 个板级输入和 71 个板级输出配置外部延迟，因此本结果表示实验约束范围内的内部同步时序通过，
不代表已完成板级 I/O 或 CDC 的全面签核。DRC 为 0 错误、15 警告，涉及配置电压属性缺省及 DSP 流水建议；
未猜测实际板卡的配置电压，也未生成 bitstream 或执行实体上板。

早期生成工程没有进入最终签核；最终结果不引用 exp13 的时序报告。
Vivado 仅运行到 route_design 时，运行进度未必为 100%；脚本已改按步骤状态判断，
并允许用 `signoff` 直接检查已布线的不可变检查点，避免把 GUI 运行进度当成时序结论。

## 复现

在仓库根目录运行，Vivado 安装路径可按实际环境替换：

```powershell
& 'D:/vivado2025/2025.2/Vivado/bin/vivado.bat' -mode batch -source scripts/exp14_vivado.tcl -tclargs create
& 'D:/vivado2025/2025.2/Vivado/bin/vivado.bat' -mode batch -source scripts/exp14_vivado.tcl -tclargs sim 0x5501ff
& 'D:/vivado2025/2025.2/Vivado/bin/vivado.bat' -mode batch -source scripts/exp14_vivado.tcl -tclargs regress
./scripts/exp14_directed.ps1
& 'D:/vivado2025/2025.2/Vivado/bin/vivado.bat' -mode batch -source scripts/exp14_vivado.tcl -tclargs impl 0x5501ff 100
```

完成一次 `sim` 导出后，可用 `./scripts/exp14_fast_regress.ps1` 直接调用 Vivado XSIM 重跑五个种子。
若只需从已完成布线的检查点重新导出签核报告，使用同一 Tcl 的 `-tclargs signoff 0x5501ff 100`。
若需在 Vivado 中直接查看已布线设计，可 `open_checkpoint build/exp14_final/project/exp14.runs/impl_1/soc_lite_top_routed.dcp`。

脚本读取仓库上一级 `output/exp14`，生成项目 `build/exp14_final/project/exp14.xpr`。
Vivado 项目直接引用根目录 CPU 源码；无需同时往工程加入另一套同名模块。
`create` 会重建本任务的生成项目，请勿对有手工改动的生成项目直接重建。

## 本地版本与硬件范围

工作分支 `codex/exp14-hs-sram`。阶段提交 `adafcf4` 保存首次通过短延迟完整 func 的实现。
不执行 push，不添加 Co-author，不修改同学的历史提交或其它未跟踪教学资料。
本次未进行实体开发板下载验证，不把仿真或布线结果称为上板通过。
