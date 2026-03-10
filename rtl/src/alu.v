// ============================================================
// ALU 模块
// 支持 RV32I 所有算术/逻辑运算
// ============================================================
`include "defines.v"

module alu (
    input  wire [3:0]              alu_op,    // ALU 操作类型
    input  wire [`DATA_WIDTH-1:0]  src_a,     // 操作数 A
    input  wire [`DATA_WIDTH-1:0]  src_b,     // 操作数 B
    output reg  [`DATA_WIDTH-1:0]  result,    // 运算结果
    output wire                    zero       // 结果是否为零
);

    assign zero = (result == 32'b0);

    always @(*) begin
        case (alu_op)
            `ALU_ADD  : result = src_a + src_b;
            `ALU_SUB  : result = src_a - src_b;
            `ALU_AND  : result = src_a & src_b;
            `ALU_OR   : result = src_a | src_b;
            `ALU_XOR  : result = src_a ^ src_b;
            `ALU_SLL  : result = src_a << src_b[4:0];
            `ALU_SRL  : result = src_a >> src_b[4:0];
            `ALU_SRA  : result = $signed(src_a) >>> src_b[4:0];
            `ALU_SLT  : result = ($signed(src_a) < $signed(src_b)) ? 32'd1 : 32'd0;
            `ALU_SLTU : result = (src_a < src_b) ? 32'd1 : 32'd0;
            `ALU_LUI  : result = src_b;
            default   : result = 32'b0;
        endcase
    end

endmodule
