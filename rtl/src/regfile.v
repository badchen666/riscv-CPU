// ============================================================
// 寄存器堆 (32个 x 32位通用寄存器)
// x0 硬连线为 0
// 写操作在时钟下降沿，读操作组合逻辑 (后半周期可读到新值)
// ============================================================
`include "defines.v"

module regfile (
    input  wire        clk,
    input  wire        rst_n,
    // 读端口 A
    input  wire [4:0]  rs1,
    output wire [31:0] rdata1,
    // 读端口 B
    input  wire [4:0]  rs2,
    output wire [31:0] rdata2,
    // 写端口
    input  wire        we,
    input  wire [4:0]  rd,
    input  wire [31:0] wdata
);

    reg [31:0] regs [1:31];  // regs[0] 不需要存储，硬连线为 0

    // 下降沿写入：前半周期完成写操作，后半周期 ID 阶段读出新值
    // 这样无需写后读旁路，也不增加 wb_wdata 的组合扇出
    integer i;
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i < 32; i = i + 1)
                regs[i] <= 32'b0;
        end else if (we && rd != 5'b0) begin
            regs[rd] <= wdata;
        end
    end

    // 纯寄存器读取 (无写后读旁路)
    // 流水线 forward_unit 的 MEM-EX 前递已覆盖 WB→EX 数据冒险
    assign rdata1 = (rs1 == 5'b0) ? 32'b0 : regs[rs1];
    assign rdata2 = (rs2 == 5'b0) ? 32'b0 : regs[rs2];

endmodule
