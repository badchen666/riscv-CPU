// ============================================================
// 冒险检测单元
// 检测 Load-Use 数据冒险，产生 stall 信号
// ============================================================
`include "defines.v"

module hazard_unit (
    // ID 阶段读取的源寄存器
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    // EX 阶段流水线寄存器
    input  wire       ex_mem_read,   // EX 阶段是 LOAD 指令
    input  wire [4:0] ex_rd,
    // 输出
    output wire       stall,         // 流水线停顿 (IF/ID 保持, ID/EX 插泡)
    output wire       flush_idex     // 插入 NOP 到 ID/EX
);

    // Load-Use 冒险: EX 阶段是 LOAD 且目标寄存器与 ID 阶段源寄存器相同
    assign stall      = ex_mem_read &&
                        ((ex_rd == id_rs1) || (ex_rd == id_rs2)) &&
                        (ex_rd != 5'b0);
    assign flush_idex = stall;

endmodule
