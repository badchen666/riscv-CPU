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
    input wire [31:0] instr_addra,
    input wire [31:0] instr_data,
    input wire        instr_ena,
    input wire        instr_wea
);
    wire [9:0] bram_addrb;
    wire bram_enb;
    wire [31:0] bram_doutb;
    
    // 地址转换：字节地址 → 字地址
    assign bram_addrb = addr[11:2];
    assign bram_enb = 1'b1;  // 始终使能 Port B 读取指令
    assign instr = bram_doutb;

    instr_ram instr_ram (
        .clk   (clk),
        .ena   (instr_ena),
        .enb   (bram_enb),
        .wea   (instr_wea),
        .addra (instr_addra),
        .addrb (bram_addrb),
        .dina  (instr_data),
        .doutb (bram_doutb)
    );

endmodule
