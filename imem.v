// ============================================================
// 指令存储器 — BRAM Port B 接口全部引出
// 在 Block Design 中直接将本模块的 bram_* 端口连接到 BRAM IP 核
//
// BRAM IP 核配置 (Block Memory Generator):
//   - Memory Type      : Simple Dual Port RAM
//   - Port B Width     : 32 bit, Depth : 1024
//   - Port B Output Registers : 关闭 (No Registers)
// ============================================================
`include "defines.v"

module imem (
    input  wire        clk,           // CPU 时钟，同时驱动 BRAM Port B
    input  wire [31:0] addr,          // 字节地址 (来自 PC)
    output wire [31:0] instr,         // 读出的指令

    // ---- BRAM Port B Native 接口 (全部引出，在 Block Design 中连线) ----
    output wire [9:0]  bram_addrb,    // → BRAM addrb
    output wire        bram_clkb,     // → BRAM clkb
    output wire        bram_enb,      // → BRAM enb   (常高)
    output wire        bram_rstb,     // → BRAM rstb  (常低)
    output wire [3:0]  bram_web,      // → BRAM web   (常0, 只读)
    output wire [31:0] bram_dinb,     // → BRAM dinb  (常0, 只读)
    input  wire [31:0] bram_doutb     // ← BRAM doutb
);

    // 地址转换：字节地址 → 字地址
    assign bram_addrb = addr[9:0];
    assign bram_clkb  = clk;
    assign bram_enb   = 1'b1;
    assign bram_rstb  = 1'b0;
    assign bram_web   = 4'b0000;
    assign bram_dinb  = 32'b0;

    // 指令输出
    assign instr = bram_doutb;

endmodule
