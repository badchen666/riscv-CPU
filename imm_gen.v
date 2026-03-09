// ============================================================
// 立即数扩展单元
// 根据指令类型将 12/20/21 位立即数符号扩展为 32 位
// ============================================================
`include "defines.v"

module imm_gen (
    input  wire [31:0] instr,
    output reg  [31:0] imm
);

    wire [6:0] opcode = instr[6:0];

    always @(*) begin
        case (opcode)
            // I-type (LOAD / JALR / ALU-immediate)
            `OP_LOAD,
            `OP_JALR,
            `OP_I_ALU : imm = {{20{instr[31]}}, instr[31:20]};

            // S-type (STORE)
            `OP_STORE  : imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            // B-type (BRANCH)
            `OP_BRANCH : imm = {{19{instr[31]}}, instr[31], instr[7],
                                 instr[30:25], instr[11:8], 1'b0};

            // U-type (LUI / AUIPC)
            `OP_LUI,
            `OP_AUIPC  : imm = {instr[31:12], 12'b0};

            // J-type (JAL)
            `OP_JAL    : imm = {{11{instr[31]}}, instr[31], instr[19:12],
                                 instr[20], instr[30:21], 1'b0};

            default    : imm = 32'b0;
        endcase
    end

endmodule
