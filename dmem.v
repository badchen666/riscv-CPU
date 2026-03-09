// ============================================================
// 数据存储器 — 32位宽 × 1024深度，综合为 Block RAM
//
// BRAM 推断要点:
//   1. (* ram_style = "block" *) 属性强制映射到 BRAM
//   2. 32位宽 + 字节写使能 (wea[3:0]) 匹配 BRAM 原语结构
//   3. 读写均为同步 (posedge clk)，符合 BRAM 时序要求
//   4. 读写同地址时采用 READ_FIRST 模式 (先输出旧值再写入)
// ============================================================
`include "defines.v"

module dmem (
    input  wire        clk,
    // 读端口 — 地址和使能提前一拍送入，BRAM 同步读输出
    input  wire        rd_en,       // 读使能 (来自 EX 阶段的 idex_mem_read)
    input  wire [31:0] rd_addr,     // 读地址 (来自 EX 阶段的 alu_result)
    input  wire [2:0]  rd_funct3,   // 读类型 (来自 EX 阶段的 idex_mem_funct3)
    output reg  [31:0] rdata,       // 读数据 (MEM 阶段组合输出，MEM/WB 寄存器锁存)
    // 写端口 — MEM 阶段写入
    input  wire        wr_en,       // 写使能 (来自 EX/MEM 寄存器)
    input  wire [2:0]  wr_funct3,   // 写类型 (来自 EX/MEM 寄存器)
    input  wire [31:0] wr_addr,     // 写地址 (来自 EX/MEM 寄存器)
    input  wire [31:0] wr_data      // 写数据 (来自 EX/MEM 寄存器)
);
    // 32位宽 × 1024深度 = 4096字节
    // ram_style = "block" 强制 Vivado 推断为 BRAM
    (* ram_style = "block" *) reg [31:0] mem [0:1023];

    // ----------------------------------------------------------------
    // 地址解码
    // ----------------------------------------------------------------
    // 读端口地址
    wire [1:0]  rd_byte_off  = rd_addr[1:0];
    wire [9:0]  rd_word_addr = rd_addr[11:2];
    // 写端口地址
    wire [1:0]  wr_byte_off  = wr_addr[1:0];
    wire [9:0]  wr_word_addr = wr_addr[11:2];

    // ----------------------------------------------------------------
    // 字节写使能：根据 wr_funct3 和地址低2位生成 4-bit 写使能
    // ----------------------------------------------------------------
    reg  [3:0]  wea;
    always @(*) begin
        wea = 4'b0000;
        if (wr_en) begin
            case (wr_funct3)
                `SB: wea = 4'b0001 << wr_byte_off;
                `SH: wea = 4'b0011 << wr_byte_off;
                `SW: wea = 4'b1111;
                default: wea = 4'b0000;
            endcase
        end
    end

    // 写数据按字节偏移对齐到 32-bit 字内
    wire [31:0] wdata_shifted = wr_data << (wr_byte_off * 8);

    // ----------------------------------------------------------------
    // 同步写 (字节使能)
    // ----------------------------------------------------------------
    integer j;
    always @(posedge clk) begin
        for (j = 0; j < 4; j = j + 1) begin
            if (wea[j])
                mem[wr_word_addr][8*j +: 8] <= wdata_shifted[8*j +: 8];
        end
    end

    // ----------------------------------------------------------------
    // 同步读 (READ_FIRST 模式，与 BRAM 原语一致)
    // 读地址和使能来自 EX 阶段，BRAM 在下一拍输出 → MEM 阶段可用
    // ----------------------------------------------------------------
    reg [31:0] raw_read;
    always @(posedge clk) begin
        if (rd_en)
            raw_read <= mem[rd_word_addr];
    end

    // 寄存读端口的 funct3 和 byte_off（与 raw_read 同步对齐）
    reg [2:0] funct3_r;
    reg [1:0] byte_off_r;
    always @(posedge clk) begin
        funct3_r   <= rd_funct3;
        byte_off_r <= rd_byte_off;
    end

    // ----------------------------------------------------------------
    // 字节/半字提取 — 纯组合逻辑（MEM 阶段内完成）
    // raw_read / funct3_r / byte_off_r 都是寄存器输出，组合延迟很短
    // ----------------------------------------------------------------
    wire [7:0]  rd_byte = raw_read[byte_off_r*8 +: 8];
    wire [15:0] rd_half = raw_read[byte_off_r*8 +: 16];

    always @(*) begin
        case (funct3_r)
            `LB : rdata = {{24{rd_byte[7]}}, rd_byte};
            `LH : rdata = {{16{rd_half[15]}}, rd_half};
            `LW : rdata = raw_read;
            `LBU: rdata = {24'b0, rd_byte};
            `LHU: rdata = {16'b0, rd_half};
            default: rdata = 32'b0;
        endcase
    end

endmodule
