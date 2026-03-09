// ============================================================
// 前递单元 (Forwarding Unit)
// 解决 EX-EX 和 MEM-EX 数据冒险
// ============================================================
`include "defines.v"

module forward_unit (
    // EX 阶段源寄存器
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    // EX/MEM 流水线寄存器
    input  wire       mem_reg_write,
    input  wire [4:0] mem_rd,
    // MEM/WB 流水线寄存器
    input  wire       wb_reg_write,
    input  wire [4:0] wb_rd,
    // 前递选择信号
    // 00: 使用寄存器堆读出值
    // 01: 从 MEM/WB 前递 (MEM-EX)
    // 10: 从 EX/MEM 前递 (EX-EX)
    output reg  [1:0] forward_a,
    output reg  [1:0] forward_b
);

    always @(*) begin
        // Forward A
        if (mem_reg_write && (mem_rd != 5'b0) && (mem_rd == ex_rs1))
            forward_a = 2'b10;  // EX-EX 前递
        else if (wb_reg_write && (wb_rd != 5'b0) && (wb_rd == ex_rs1))
            forward_a = 2'b01;  // MEM-EX 前递
        else
            forward_a = 2'b00;  // 使用寄存器堆

        // Forward B
        if (mem_reg_write && (mem_rd != 5'b0) && (mem_rd == ex_rs2))
            forward_b = 2'b10;
        else if (wb_reg_write && (wb_rd != 5'b0) && (wb_rd == ex_rs2))
            forward_b = 2'b01;
        else
            forward_b = 2'b00;
    end

endmodule
