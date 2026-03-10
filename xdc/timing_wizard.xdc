# ==============================================================
# 1. 主时钟约束
#    时钟来自 Zynq PS FCLK_CLK0，在 Block Design 中产生
#    如果你用的是外部晶振直接进 PL，把下面这行换成：
#    create_clock -name clk -period 10.000 [get_ports clk]
# ==============================================================
create_clock -name fclk0 -period 6.666667 \
    [get_pins system_i/processing_system7_0/inst/PS7_i/FCLKCLK[0]]

# ==============================================================
# 2. 生成时钟（如果 Block Design 里有 Clocking Wizard / MMCM）
#    没有的话注释掉这段
# ==============================================================
# create_generated_clock -name clk_cpu \
#     -source [get_pins system_i/clk_wiz_0/inst/mmcm_adv_inst/CLKIN1] \
#     -multiply_by 1 -divide_by 1 \
#     [get_pins system_i/clk_wiz_0/inst/mmcm_adv_inst/CLKOUT0]

# ==============================================================
# 3. I/O 延时约束
#    你的顶层端口只有 clk/rst_n 和调试输出，均为 PL 内部信号
#    BRAM Port B 信号（instr_addra 等）来自 PS AXI，不需要板级约束
#    ILA 调试端口由 Vivado 自动处理，也不需要约束
#    只需约束 rst_n（如果是外部引脚）
# ==============================================================
# 示例：rst_n 接 ZYNQ 的 PS_SRST_B 或板上按键
# 如果 rst_n 来自 PS GPIO 则不需要下面这行
# set_input_delay -clock fclk0 -max 2.000 [get_ports rst_n]
# set_input_delay -clock fclk0 -min 0.000 [get_ports rst_n]

# ==============================================================
# 4. 跨时钟域 / 假路径设置
# ==============================================================
# PS 和 PL 之间的路径设为异步（防止跨域误报）
set_clock_groups -asynchronous \
    -group [get_clocks fclk0] \
    -group [get_clocks -of_objects \
        [get_pins system_i/processing_system7_0/inst/PS7_i/FCLKCLK[1]]]

# rst_n 复位信号设为假路径（复位路径不做时序检查）
set_false_path -from [get_ports rst_n]

# ILA 核内部路径设为假路径
set_false_path -to [get_debug_cores]

# ==============================================================
# 5. 多周期路径（可选）
#    你的 CPU 关键路径：
#    forward_mux → ALU → branch_cond → exmem 寄存器
#    当前设计已把 branch 打了一拍（exmem_take_branch），
#    时序压力已经减轻，通常不需要额外多周期约束
#    如果 report_timing 显示某条路径 slack 为负，再加
# ==============================================================
# 示例：如果 ALU 结果到 EX/MEM 寄存器仍然 slack 不足
set_multicycle_path -setup 2 \
    -from [get_cells -hierarchical {u_alu/*}] \
    -to   [get_cells {exmem_alu_result_reg[*]}]

# ==============================================================
# 6. Pblock 布局约束（可选，改善时序收敛）
#    把 CPU 核心约束在 PL 左侧区域，减少布线延迟
# ==============================================================
# create_pblock pblock_cpu
# add_cells_to_pblock [pblock_cpu] [get_cells system_i/cpu_top_0]
# resize_pblock [pblock_cpu] -add {SLICE_X0Y0:SLICE_X57Y99}