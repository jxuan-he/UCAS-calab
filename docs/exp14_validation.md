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

进行中：完整 SoC，100 MHz CPU 与 100 MHz timer，综合及布线结果尚待报告。
最终结果写入本节后才能认定时序通过；exp13 旧报告中的 WNS 不用于本版本签核。

## 复现

在仓库根目录运行，Vivado 安装路径可按实际环境替换：

```powershell
& 'D:/vivado2025/2025.2/Vivado/bin/vivado.bat' -mode batch -source scripts/exp14_vivado.tcl -tclargs create
& 'D:/vivado2025/2025.2/Vivado/bin/vivado.bat' -mode batch -source scripts/exp14_vivado.tcl -tclargs sim 0x5501ff
& 'D:/vivado2025/2025.2/Vivado/bin/vivado.bat' -mode batch -source scripts/exp14_vivado.tcl -tclargs regress
./scripts/exp14_directed.ps1
& 'D:/vivado2025/2025.2/Vivado/bin/vivado.bat' -mode batch -source scripts/exp14_vivado.tcl -tclargs impl 0x5501ff 100
```

脚本读取仓库上一级 `output/exp14`，生成项目 `build/exp14_final/project/exp14.xpr`。
Vivado 项目直接引用根目录 CPU 源码；无需同时往工程加入另一套同名模块。
`create` 会重建本任务的生成项目，请勿对有手工改动的生成项目直接重建。

## 本地版本与硬件范围

工作分支 `codex/exp14-hs-sram`。阶段提交 `adafcf4` 保存首次通过短延迟完整 func 的实现。
不执行 push，不添加 Co-author，不修改同学的历史提交或其它未跟踪教学资料。
本次尚未进行实体开发板下载验证，不把仿真或布线结果称为上板通过。
