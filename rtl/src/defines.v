// ============================================================
// RISC-V 32I 五级流水线 CPU - 全局宏定义
// ============================================================

// ALU 操作码
`define ALU_ADD   4'd0
`define ALU_SUB   4'd1
`define ALU_AND   4'd2
`define ALU_OR    4'd3
`define ALU_XOR   4'd4
`define ALU_SLL   4'd5
`define ALU_SRL   4'd6
`define ALU_SRA   4'd7
`define ALU_SLT   4'd8
`define ALU_SLTU  4'd9
`define ALU_LUI   4'd10  // pass src_b directly

// RISC-V 指令 opcode (低7位)
`define OP_R       7'b0110011   // R-type: ADD SUB AND OR XOR SLL SRL SRA SLT SLTU
`define OP_I_ALU   7'b0010011   // I-type ALU: ADDI ANDI ORI XORI SLTI SLTIU SLLI SRLI SRAI
`define OP_LOAD    7'b0000011   // LOAD: LB LH LW LBU LHU
`define OP_STORE   7'b0100011   // STORE: SB SH SW
`define OP_BRANCH  7'b1100011   // BRANCH: BEQ BNE BLT BGE BLTU BGEU
`define OP_JAL     7'b1101111   // JAL
`define OP_JALR    7'b1100111   // JALR
`define OP_LUI     7'b0110111   // LUI
`define OP_AUIPC   7'b0010111   // AUIPC

// funct3 for branch
`define BEQ   3'b000
`define BNE   3'b001
`define BLT   3'b100
`define BGE   3'b101
`define BLTU  3'b110
`define BGEU  3'b111

// funct3 for load
`define LB   3'b000
`define LH   3'b001
`define LW   3'b010
`define LBU  3'b100
`define LHU  3'b101

// funct3 for store
`define SB   3'b000
`define SH   3'b001
`define SW   3'b010

// funct3 for I-type ALU
`define ADDI  3'b000
`define SLTI  3'b010
`define SLTIU 3'b011
`define XORI  3'b100
`define ORI   3'b110
`define ANDI  3'b111
`define SLLI  3'b001
`define SRLI_SRAI 3'b101

// funct7
`define FUNCT7_NORMAL 7'b0000000
`define FUNCT7_ALT    7'b0100000   // SUB / SRA

// 数据宽度
`define DATA_WIDTH 32
`define ADDR_WIDTH 32
`define REG_WIDTH  5

// NOP 指令 (ADDI x0, x0, 0)
`define NOP 32'h00000013
