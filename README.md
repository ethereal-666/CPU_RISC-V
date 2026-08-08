# miniLA LoongArch32 SoC

本仓库是流水线 CPU 与 AXI SoC、DDR3、UART、GPIO、定时器合并后的 Vivado 2023.2 工程。

- Vivado 工程：`miniLA.xpr`
- RTL、约束和仿真：`src/`
- MIG 源配置：`miniLA.srcs/`
- 工程检查、仿真和位流脚本：`scripts/`
- LLaMA C 源码及编译脚本：`software/llama/`
- 已验证的 LLaMA BRAM 初始化文件：`src/coe/llama.coe`

打开工程后，可在 Tcl Console 中执行：

```tcl
source scripts/project_check.tcl
source scripts/select_llama_coe.tcl
source scripts/regenerate_ip.tcl
source scripts/sim_smoke.tcl
source scripts/build_fixed_bitstream.tcl
```

`select_llama_coe.tcl` 按以下顺序选择 LLaMA 程序：

1. `software/llama/main.coe`（在仓库内重新编译后的产物）；
2. `../5_llama2.c/main.coe`（兼容原来的同级目录）；
3. `src/coe/llama.coe`（仓库中已验证的默认版本）。

Vivado 生成的缓存、仿真输出、综合/实现结果和 IP 派生文件均由 `.gitignore` 排除。仓库只保存 RTL、XCI、MIG 配置、约束、测试和脚本等可复现输入。

如 IP 派生文件过期，可用 `source scripts/regenerate_ip.tcl` 重新生成全部 IP；也可在批处理模式下通过 `-tclargs clk_wiz_0` 只生成指定 IP。
