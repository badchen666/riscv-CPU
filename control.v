// ============================================================
// 控制单元
// 根据 opcode / funct3 / funct7 产生控制信号
// ============================================================
`include "defines.v"

module control (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,

    // EX 阶段
    output reg  [3:0] alu_op,      // ALU 操作
    output reg        alu_src_b,   // 0: reg  1: imm
    output reg        lui_auipc,   // LUI/AUIPC 特殊处理

    // MEM 阶段
    output reg        mem_read,    // 访存读
    output reg        mem_write,   // 访存写
    output reg  [2:0] mem_funct3,  // 传递给 MEM 阶段区分字节/半字/字

    // WB 阶段
    output reg        reg_write,   // 写寄存器使能
    output reg  [1:0] wb_sel,      // 0: ALU结果  1: MEM数据  2: PC+4

    // 分支/跳转
    output reg        branch,      // 条件分支
    output reg        jal,         // JAL
    output reg        jalr         // JALR
);

    always @(*) begin
        // 默认值
        alu_op     = `ALU_ADD;
        alu_src_b  = 1'b0;
        lui_auipc  = 1'b0;
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        mem_funct3 = funct3;
        reg_write  = 1'b0;
        wb_sel     = 2'd0;
        branch     = 1'b0;
        jal        = 1'b0;
        jalr       = 1'b0;

        case (opcode)
            // ---- R-type ----
            `OP_R: begin
                reg_write = 1'b1;
                alu_src_b = 1'b0;
                case (funct3)
                    3'b000: alu_op = (funct7 == `FUNCT7_ALT) ? `ALU_SUB : `ALU_ADD;
                    3'b001: alu_op = `ALU_SLL;
                    3'b010: alu_op = `ALU_SLT;
                    3'b011: alu_op = `ALU_SLTU;
                    3'b100: alu_op = `ALU_XOR;
                    3'b101: alu_op = (funct7 == `FUNCT7_ALT) ? `ALU_SRA : `ALU_SRL;
                    3'b110: alu_op = `ALU_OR;
                    3'b111: alu_op = `ALU_AND;
                    default: alu_op = `ALU_ADD;
                endcase
            end

            // ---- I-type ALU ----
            `OP_I_ALU: begin
                reg_write = 1'b1;
                alu_src_b = 1'b1;
                case (funct3)
                    3'b000: alu_op = `ALU_ADD;    // ADDI
                    3'b010: alu_op = `ALU_SLT;    // SLTI
                    3'b011: alu_op = `ALU_SLTU;   // SLTIU
                    3'b100: alu_op = `ALU_XOR;    // XORI
                    3'b110: alu_op = `ALU_OR;     // ORI
                    3'b111: alu_op = `ALU_AND;    // ANDI
                    3'b001: alu_op = `ALU_SLL;    // SLLI
                    3'b101: alu_op = (funct7 == `FUNCT7_ALT) ? `ALU_SRA : `ALU_SRL; // SRLI/SRAI
                    default: alu_op = `ALU_ADD;
                endcase
            end

            // ---- LOAD ----
            `OP_LOAD: begin
                reg_write  = 1'b1;
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                mem_read   = 1'b1;
                wb_sel     = 2'd1;
                mem_funct3 = funct3;
            end

            // ---- STORE ----
            `OP_STORE: begin
                alu_src_b  = 1'b1;
                alu_op     = `ALU_ADD;
                mem_write  = 1'b1;
                mem_funct3 = funct3;
            end

            // ---- BRANCH ----
            `OP_BRANCH: begin
                branch     = 1'b1;
                alu_src_b  = 1'b0;
                case (funct3)
                    `BEQ : alu_op = `ALU_SUB;
                    `BNE : alu_op = `ALU_SUB;
                    `BLT : alu_op = `ALU_SLT;
                    `BGE : alu_op = `ALU_SLT;
                    `BLTU: alu_op = `ALU_SLTU;
                    `BGEU: alu_op = `ALU_SLTU;
                    default: alu_op = `ALU_SUB;
                endcase
            end

            // ---- JAL ----
            `OP_JAL: begin
                jal       = 1'b1;
                reg_write = 1'b1;
                wb_sel    = 2'd2;   // 写入 PC+4
            end

            // ---- JALR ----
            `OP_JALR: begin
                jalr      = 1'b1;
                reg_write = 1'b1;
                alu_src_b = 1'b1;
                alu_op    = `ALU_ADD;
                wb_sel    = 2'd2;   // 写入 PC+4
            end

            // ---- LUI ----
            `OP_LUI: begin
                reg_write = 1'b1;
                alu_op    = `ALU_LUI;
                alu_src_b = 1'b1;
                lui_auipc = 1'b1;
            end

            // ---- AUIPC ----
            `OP_AUIPC: begin
                reg_write = 1'b1;
                alu_op    = `ALU_ADD;
                alu_src_b = 1'b1;
                lui_auipc = 1'b1;
            end

            default: begin
                // NOP 或未支持指令: 所有信号保持默认
            end
        endcase
    end

endmodule
