// ============================================================
// RISC-V 32I 五级流水线 CPU 顶层模块
//
// 流水线结构:
//   IF  ->  ID  ->  EX  ->  MEM  ->  WB
//
// 冒险处理:
//   - Load-Use: 停顿 1 周期 (stall + flush ID/EX)
//   - 控制冒险: 分支/跳转在 EX 阶段计算，冲刷 IF/ID 和 ID/EX (2周期代价)
//   - 数据冒险: EX-EX / MEM-EX 前递
// ============================================================
`include "defines.v"

module cpu_top (
    input wire clk,
    input wire rst_n,

    // ---- BRAM Port B AXI-LITE ---- //
    input wire [31:0] instr_addra,
    input wire [31:0] instr_data,
    input wire        instr_ena,
    input wire        instr_wea,

    // ---- ILA 调试观测端口 (连接到 Block Design 中的 ILA IP 核) ----
    // IF 阶段
    output wire [31:0] dbg_pc,           // 当前 PC
    output wire [31:0] dbg_instr,        // 当前取到的指令
    // WB 阶段
    output wire        dbg_wb_reg_write, // 写寄存器使能
    output wire [4:0]  dbg_wb_rd,        // 写目标寄存器编号
    output wire [31:0] dbg_wb_wdata,     // 写入数据
    // EX 阶段
    output wire [31:0] dbg_ex_alu_result,// ALU 运算结果
    output wire        dbg_ex_branch,    // 分支/跳转发生
    output wire [31:0] dbg_ex_pc_target, // 跳转目标地址
    // 流水线控制
    output wire        dbg_stall,        // 流水线停顿
    output wire        dbg_flush,        // 流水线冲刷

    // 通用寄存器观测
    output wire [31:0] dbg_reg_x2,       // x2 = sum
    output wire [31:0] dbg_reg_x3,       // x3 = lw 读回
    output wire [31:0] dbg_reg_x4,       // x4 = MEM-EX 前递
    output wire [31:0] dbg_reg_x7        // x7 = 结束标志
);

// ============================================================
// ===============  IF 阶段  ==================================
// ============================================================
    reg  [31:0] pc_reg;
    wire [31:0] pc_next;
    wire [31:0] if_instr;
    wire [31:0] pc_plus4;

    // PC 下一值选择 (分支决策已寄存到 MEM 阶段)
    wire        mem_take_branch;   // MEM 阶段寄存后的跳转使能
    wire [31:0] mem_branch_target; // MEM 阶段寄存后的跳转目标

    assign pc_plus4 = pc_reg + 32'd4;
    assign pc_next  = (mem_take_branch) ? mem_branch_target : pc_plus4;

    // PC 寄存器 (stall 时保持, 但 branch 优先于 stall)
    wire stall;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_reg <= 32'b0;
        else if (mem_take_branch)
            pc_reg <= mem_branch_target;   // 跳转优先
        else if (!stall)
            pc_reg <= pc_next;
    end

    // BRAM 同步读补偿：pc_reg_d1 是上一拍送给 BRAM 的地址
    // BRAM 在当前拍输出的指令对应的正是 pc_reg_d1
    // 注意：stall 期间 pc_reg 保持不变，但 BRAM 仍然以 pc_reg 为地址在读取。
    //       因此 pc_reg_d1 必须始终跟踪 pc_reg（无论是否 stall），
    //       否则 stall 结束后 pc_reg_d1 会比 BRAM 输出落后一拍，导致 PC 与指令错位。
    reg [31:0] pc_reg_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc_reg_d1 <= 32'b0;
        else if (mem_take_branch)
            pc_reg_d1 <= mem_branch_target;  // 跳转时设为目标地址，下一拍 IF/ID 用它作为 PC
        else
            pc_reg_d1 <= pc_reg;  // 始终跟踪 pc_reg，与 BRAM 输出对齐（stall 时 pc_reg 不变，赋值等效 hold）
    end


    imem u_imem (
        .clk        (clk),
        .addr       (pc_reg),
        .instr      (if_instr),
        // BRAM Port B
        .instr_addra(instr_addra),
        .instr_data (instr_data),
        .instr_ena  (instr_ena),
        .instr_wea  (instr_wea)
    );

// ============================================================
// ===============  IF/ID 流水线寄存器  =======================
// ============================================================
    reg [31:0] ifid_pc;
    reg [31:0] ifid_instr;

    // BRAM 同步读延迟补偿：branch 后需要额外 flush 一拍 IF/ID
    // 因为 BRAM 输出比地址晚一拍，branch 后第一拍 BRAM 输出的仍是旧指令
    reg flush_ifid_d1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            flush_ifid_d1 <= 1'b0;
        else
            flush_ifid_d1 <= mem_take_branch;
    end

    wire flush_ifid = mem_take_branch || flush_ifid_d1;  // 延长 flush 一拍

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_ifid) begin
            ifid_pc    <= 32'b0;
            ifid_instr <= `NOP;
        end else if (!stall) begin
            ifid_pc    <= pc_reg_d1;   // 使用延迟一拍的PC，与BRAM输出的指令对齐
            ifid_instr <= if_instr;    // BRAM 此拍输出 = pc_reg_d1 对应的指令
        end
    end

// ============================================================
// ===============  ID 阶段  ==================================
// ============================================================
    // 指令字段解码
    wire [6:0] id_opcode = ifid_instr[6:0];
    wire [4:0] id_rd     = ifid_instr[11:7];
    wire [2:0] id_funct3 = ifid_instr[14:12];
    wire [4:0] id_rs1    = ifid_instr[19:15];
    wire [4:0] id_rs2    = ifid_instr[24:20];
    wire [6:0] id_funct7 = ifid_instr[31:25];

    // 立即数扩展
    wire [31:0] id_imm;
    imm_gen u_imm_gen (
        .instr (ifid_instr),
        .imm   (id_imm)
    );

    // 控制单元
    wire [3:0] id_alu_op;       // ALU 操作码，供 ALU 使用，具体定义在 defines.v 中
    wire       id_alu_src_b;    // ALU 第二操作数选择：0=寄存器, 1=立即数
    wire       id_lui_auipc;    // LUI/AUIPC 标志，供 EX 阶段选择 ALU 输入
    wire       id_mem_read;     // 访存读使能
    wire       id_mem_write;    // 访存写使能
    wire [2:0] id_mem_funct3;   // 访存功能码，传递给 MEM 阶段区分字节/半字/字
    wire       id_reg_write;    // 写寄存器使能
    wire [1:0] id_wb_sel;       // 写回数据选择：0=ALU结果, 1=访存数据, 2=PC+4 (JAL/JALR)
    wire       id_branch;       // 条件分支指令标志，供 EX 阶段判断是否分支
    wire       id_jal;          // JAL 指令标志，供 EX 阶段判断是否跳转
    wire       id_jalr;         // JALR 指令标志，供 EX 阶段判断是否跳转

    control u_ctrl (
        .opcode      (id_opcode),   // 指令 opcode 字段
        .funct3      (id_funct3),   // 指令 funct3 字段
        .funct7      (id_funct7),   // 指令 funct7 字段
        .alu_op      (id_alu_op),   // ALU 操作码，供 ALU 使用，具体定义在 defines.v 中
        .alu_src_b   (id_alu_src_b), // ALU 第二操作数选择：0=寄存器, 1=立即数
        .lui_auipc   (id_lui_auipc), // LUI/AUIPC 标志，供 EX 阶段选择 ALU 输入
        .mem_read    (id_mem_read),  // 访存读使能
        .mem_write   (id_mem_write), // 访存写使能
        .mem_funct3  (id_mem_funct3), // 访存功能码，传递给 MEM 阶段区分字节/半字/字
        .reg_write   (id_reg_write), // 写寄存器使能
        .wb_sel      (id_wb_sel),    // 写回数据选择
        .branch      (id_branch),    // 条件分支指令标志
        .jal         (id_jal),       // JAL 指令标志
        .jalr        (id_jalr)       // JALR 指令标志
    );

    // 寄存器堆 (写端口来自 WB 阶段)
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_wdata;

    wire [31:0] id_rdata1, id_rdata2;
    regfile u_regfile (
        .clk    (clk),
        .rst_n  (rst_n),
        .rs1    (id_rs1),  // 读寄存器编号 1
        .rdata1 (id_rdata1),    // 读寄存器数据 1
        .rs2    (id_rs2),  // 读寄存器编号 2
        .rdata2 (id_rdata2),    // 读寄存器数据 2
        .we     (wb_reg_write), // 写寄存器使能
        .rd     (wb_rd),  // 写寄存器编号
        .wdata  (wb_wdata)  // 写寄存器数据
    );

    // 冒险检测
    wire       flush_idex_hazard;   // Load-Use 冒险时冲刷 ID/EX
    wire [4:0] ex_rd_wire;          // EX 阶段目标寄存器编号，用于冒险检测
    wire       ex_mem_read_wire;    // EX 阶段是否是 LOAD 指令，用于冒险检测

    hazard_unit u_hazard (
        .id_rs1       (id_rs1),
        .id_rs2       (id_rs2),
        .ex_mem_read  (ex_mem_read_wire),
        .ex_rd        (ex_rd_wire),
        .stall        (stall),
        .flush_idex   (flush_idex_hazard)
    );

// ============================================================
// ===============  ID/EX 流水线寄存器  =======================
// ============================================================
    reg [31:0] idex_pc;         // 用于分支计算
    reg [31:0] idex_rdata1;     // 注意：idex_rdata1 需要前递到 EX 阶段用于 ALU 操作
    reg [31:0] idex_rdata2;     // 注意：idex_rdata2 需要前递到 EX 阶段用于 store 指令的写数据
    reg [31:0] idex_imm;        // 注意：idex_imm 需要前递到 EX 阶段用于 ALU 操作
    reg [4:0]  idex_rs1;        // 注意：idex_rs1 需要前递到 EX 阶段用于 ALU 操作
    reg [4:0]  idex_rs2;        // 注意：idex_rs2 需要前递到 EX 阶段用于 ALU 操作
    reg [4:0]  idex_rd;         // 注意：idex_rd 需要前递到 EX/MEM 和 MEM/WB 用于写回寄存器编号
    reg [2:0]  idex_funct3;     // 注意：idex_funct3 需要前递到 EX 阶段用于分支条件判断，和前递到 MEM 阶段用于访存字节/半字/字区分
    // 控制信号
    reg [3:0]  idex_alu_op;     // 注意：idex_alu_op 需要前递到 EX 阶段用于 ALU 操作
    reg        idex_alu_src_b;  // 注意：idex_alu_src_b 需要前递到 EX 阶段用于 ALU 操作
    reg        idex_lui_auipc;  // 注意：idex_lui_auipc 需要前递到 EX 阶段用于 ALU 操作
    reg        idex_mem_read;   // 注意：idex_mem_read 需要前递到 MEM 阶段用于访存操作
    reg        idex_mem_write;  // 注意：idex_mem_write 需要前递到 MEM 阶段用于访存操作
    reg [2:0]  idex_mem_funct3; // 注意：idex_mem_funct3 需要前递到 MEM 阶段用于访存字节/半字/字区分
    reg        idex_reg_write;  // 注意：idex_reg_write 需要前递到 EX/MEM 和 MEM/WB 用于写回寄存器使能
    reg [1:0]  idex_wb_sel;     // 注意：idex_wb_sel 需要前递到 EX/MEM 和 MEM/WB 用于写回数据选择
    reg        idex_branch;     // 注意：idex_branch 需要前递到 EX 阶段用于分支判断
    reg        idex_jal;        // 注意：idex_jal 需要前递到 EX 阶段用于跳转判断
    reg        idex_jalr;       // 注意：idex_jalr 需要前递到 EX 阶段用于跳转判断
    wire flush_idex = flush_idex_hazard || mem_take_branch;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_idex) begin
            idex_pc         <= 32'b0;
            idex_rdata1     <= 32'b0;
            idex_rdata2     <= 32'b0;
            idex_imm        <= 32'b0;
            idex_rs1        <= 5'b0;
            idex_rs2        <= 5'b0;
            idex_rd         <= 5'b0;
            idex_funct3     <= 3'b0;
            idex_alu_op     <= `ALU_ADD;
            idex_alu_src_b  <= 1'b0;
            idex_lui_auipc  <= 1'b0;
            idex_mem_read   <= 1'b0;
            idex_mem_write  <= 1'b0;
            idex_mem_funct3 <= 3'b0;
            idex_reg_write  <= 1'b0;
            idex_wb_sel     <= 2'b0;
            idex_branch     <= 1'b0;
            idex_jal        <= 1'b0;
            idex_jalr       <= 1'b0;
        end else begin
            idex_pc         <= ifid_pc;
            idex_rdata1     <= id_rdata1;
            idex_rdata2     <= id_rdata2;
            idex_imm        <= id_imm;
            idex_rs1        <= id_rs1;
            idex_rs2        <= id_rs2;
            idex_rd         <= id_rd;
            idex_funct3     <= id_funct3;
            idex_alu_op     <= id_alu_op;
            idex_alu_src_b  <= id_alu_src_b;
            idex_lui_auipc  <= id_lui_auipc;
            idex_mem_read   <= id_mem_read;
            idex_mem_write  <= id_mem_write;
            idex_mem_funct3 <= id_mem_funct3;
            idex_reg_write  <= id_reg_write;
            idex_wb_sel     <= id_wb_sel;
            idex_branch     <= id_branch;
            idex_jal        <= id_jal;
            idex_jalr       <= id_jalr;
        end
    end

    assign ex_rd_wire       = idex_rd;
    assign ex_mem_read_wire = idex_mem_read;

// ============================================================
// ===============  EX 阶段  ==================================
// ============================================================
    // 前递单元
    wire [1:0] forward_a, forward_b;
    wire       mem_reg_write_wire;
    wire [4:0] mem_rd_wire;

    forward_unit u_forward (
        .ex_rs1        (idex_rs1),
        .ex_rs2        (idex_rs2),
        .mem_reg_write (mem_reg_write_wire),
        .mem_rd        (mem_rd_wire),
        .wb_reg_write  (wb_reg_write),
        .wb_rd         (wb_rd),
        .forward_a     (forward_a),
        .forward_b     (forward_b)
    );

    // EX/MEM ALU 结果 (用于 MEM-EX 前递)
    wire [31:0] exmem_alu_result_wire;
    // MEM/WB 结果已由 wb_wdata 提供

    // 前递后的操作数
    wire [31:0] ex_op_a_pre, ex_op_b_pre;
    assign ex_op_a_pre = (forward_a == 2'b10) ? exmem_alu_result_wire :
                         (forward_a == 2'b01) ? wb_wdata :
                                                idex_rdata1;

    assign ex_op_b_pre = (forward_b == 2'b10) ? exmem_alu_result_wire :
                         (forward_b == 2'b01) ? wb_wdata :
                                                idex_rdata2;

    // LUI/AUIPC: src_a 选择 PC 或 0
    wire [31:0] ex_src_a = idex_lui_auipc ?
                           ((idex_alu_op == `ALU_LUI) ? 32'b0 : idex_pc) :
                           ex_op_a_pre;

    // ALU src_b 选择: imm 或寄存器
    wire [31:0] ex_src_b = idex_alu_src_b ? idex_imm : ex_op_b_pre;

    wire [31:0] ex_alu_result;
    wire        ex_alu_zero;

    alu u_alu (
        .alu_op (idex_alu_op),
        .src_a  (ex_src_a),
        .src_b  (ex_src_b),
        .result (ex_alu_result),
        .zero   (ex_alu_zero)
    );

    // 分支条件判断
    wire ex_branch_taken;
    wire        ex_take_branch;
    wire [31:0] ex_branch_target;
    wire [31:0] ex_op_a_cmp = ex_op_a_pre;
    wire [31:0] ex_op_b_cmp = ex_op_b_pre;

    reg ex_branch_cond;
    always @(*) begin
        case (idex_funct3)
            `BEQ : ex_branch_cond = (ex_op_a_cmp == ex_op_b_cmp);
            `BNE : ex_branch_cond = (ex_op_a_cmp != ex_op_b_cmp);
            `BLT : ex_branch_cond = ($signed(ex_op_a_cmp) <  $signed(ex_op_b_cmp));
            `BGE : ex_branch_cond = ($signed(ex_op_a_cmp) >= $signed(ex_op_b_cmp));
            `BLTU: ex_branch_cond = (ex_op_a_cmp <  ex_op_b_cmp);
            `BGEU: ex_branch_cond = (ex_op_a_cmp >= ex_op_b_cmp);
            default: ex_branch_cond = 1'b0;
        endcase
    end

    assign ex_branch_taken = idex_branch && ex_branch_cond;

    // 跳转目标地址
    wire [31:0] ex_jal_target  = idex_pc + idex_imm;
    wire [31:0] ex_jalr_target = (ex_op_a_pre + idex_imm) & 32'hFFFFFFFE;

    assign ex_take_branch   = ex_branch_taken || idex_jal || idex_jalr;
    assign ex_branch_target = idex_jal    ? ex_jal_target  :
                              idex_jalr   ? ex_jalr_target :
                                            ex_jal_target;   // branch

    // PC+4 用于 JAL/JALR 的链接地址
    wire [31:0] ex_pc_plus4 = idex_pc + 32'd4;

// ============================================================
// ===============  EX/MEM 流水线寄存器  ======================
// ============================================================
    // ---- 分支决策寄存 (关键时序优化) ----
    // 将分支/跳转判断结果打一拍，用 MEM 阶段的寄存信号驱动 PC/flush
    // 代价: branch penalty 从 2 周期变为 3 周期 (多 flush EX/MEM 一级)
    // 收益: 彻底切断 forward MUX → 比较器 → PC 的超长组合路径
    reg         exmem_take_branch;
    reg  [31:0] exmem_branch_target;

    assign mem_take_branch   = exmem_take_branch;
    assign mem_branch_target = exmem_branch_target;

    reg [31:0] exmem_alu_result;
    reg [31:0] exmem_rdata2;
    reg [4:0]  exmem_rd;
    reg        exmem_reg_write;
    reg [1:0]  exmem_wb_sel;  // 写回数据选择：0=ALU结果, 1=访存数据, 2=PC+4 (JAL/JALR)
    reg        exmem_mem_read;
    reg        exmem_mem_write;
    reg [2:0]  exmem_mem_funct3;
    reg [31:0] exmem_pc_plus4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exmem_take_branch <= 1'b0;
            exmem_branch_target <= 32'b0;
            exmem_alu_result  <= 32'b0;
            exmem_rdata2      <= 32'b0;
            exmem_rd          <= 5'b0;
            exmem_reg_write   <= 1'b0;
            exmem_wb_sel      <= 2'b0;
            exmem_mem_read    <= 1'b0;
            exmem_mem_write   <= 1'b0;
            exmem_mem_funct3  <= 3'b0;
            exmem_pc_plus4    <= 32'b0;
        end else if (mem_take_branch) begin
            // MEM 阶段检测到跳转 → 冲刷 EX/MEM (把自己清空，防止连续触发)
            exmem_take_branch <= 1'b0;
            exmem_branch_target <= 32'b0;
            exmem_alu_result  <= 32'b0;
            exmem_rdata2      <= 32'b0;
            exmem_rd          <= 5'b0;
            exmem_reg_write   <= 1'b0;
            exmem_wb_sel      <= 2'b0;
            exmem_mem_read    <= 1'b0;
            exmem_mem_write   <= 1'b0;
            exmem_mem_funct3  <= 3'b0;
            exmem_pc_plus4    <= 32'b0;
        end else begin
            exmem_take_branch <= ex_take_branch;
            exmem_branch_target <= ex_branch_target;
            exmem_alu_result  <= ex_alu_result;
            exmem_rdata2      <= ex_op_b_pre;  // 用于 store，需要原始寄存器值
            exmem_rd          <= idex_rd;
            exmem_reg_write   <= idex_reg_write;
            exmem_wb_sel      <= idex_wb_sel;
            exmem_mem_read    <= idex_mem_read;
            exmem_mem_write   <= idex_mem_write;
            exmem_mem_funct3  <= idex_mem_funct3;
            exmem_pc_plus4    <= ex_pc_plus4;
        end
    end

    assign exmem_alu_result_wire = exmem_alu_result;
    assign mem_reg_write_wire    = exmem_reg_write;
    assign mem_rd_wire           = exmem_rd;

// ============================================================
// ===============  MEM 阶段  =================================
// ============================================================
    wire [31:0] mem_rdata;

    dmem u_dmem (
        .clk        (clk),
        // 读端口 — 使用 EX 阶段信号 (提前一拍送地址，BRAM 下一拍输出)
        .rd_en      (idex_mem_read),
        .rd_addr    (ex_alu_result),
        .rd_funct3  (idex_mem_funct3),
        .rdata      (mem_rdata),
        // 写端口 — 使用 EX/MEM 寄存器信号 (MEM 阶段写入)
        .wr_en      (exmem_mem_write),
        .wr_funct3  (exmem_mem_funct3),
        .wr_addr    (exmem_alu_result),
        .wr_data    (exmem_rdata2)
    );

// ============================================================
// ===============  Store-to-Load Forwarding  =================
// ============================================================
    // 场景：sw 在 MEM 阶段写 BRAM, lw 在同一拍 EX 阶段送读地址给 BRAM。
    //       由于 BRAM READ_FIRST，下一拍 lw 读出的是旧值。
    // 解法：寄存 MEM 阶段的写信息（地址/数据/使能），下一拍与 BRAM 读出结果比较。
    //       如果地址匹配，用寄存的写数据替换 BRAM 读出值。
    //
    // 时序对齐：
    //   Cycle N  : sw 在 MEM 写入 → 寄存写信息; lw 在 EX 送读地址
    //   Cycle N+1: BRAM 输出旧值(mem_rdata) → 检测到地址匹配 → 用寄存的写数据替换
    reg [31:0] prev_wr_addr;
    reg [31:0] prev_wr_data;
    reg        prev_wr_en;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_wr_addr <= 32'b0;
            prev_wr_data <= 32'b0;
            prev_wr_en   <= 1'b0;
        end else begin
            prev_wr_addr <= exmem_alu_result;  // MEM 阶段的写地址
            prev_wr_data <= exmem_rdata2;      // MEM 阶段的写数据
            prev_wr_en   <= exmem_mem_write;   // MEM 阶段是否在写
        end
    end

    // 当前拍 BRAM 读出的结果对应的读地址也需要寄存（来自上一拍 EX 的 dmem 读请求）
    reg [31:0] mem_rd_addr_r;
    reg        mem_rd_en_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_rd_addr_r <= 32'b0;
            mem_rd_en_r   <= 1'b0;
        end else begin
            mem_rd_addr_r <= ex_alu_result;
            mem_rd_en_r   <= idex_mem_read;
        end
    end

    wire mem_st2ld_fwd = prev_wr_en && mem_rd_en_r &&
                         (prev_wr_addr[31:2] == mem_rd_addr_r[31:2]);
    wire [31:0] mem_rdata_fwd = mem_st2ld_fwd ? prev_wr_data : mem_rdata;

// ============================================================
// ===============  MEM/WB 流水线寄存器  ======================
// ============================================================
    reg [31:0] memwb_alu_result;
    reg [31:0] memwb_mem_rdata;   // MEM/WB 寄存器锁存 dmem 读出数据
    reg [31:0] memwb_pc_plus4;
    reg [4:0]  memwb_rd;
    reg        memwb_reg_write;
    reg [1:0]  memwb_wb_sel;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memwb_alu_result <= 32'b0;
            memwb_mem_rdata  <= 32'b0;
            memwb_pc_plus4   <= 32'b0;
            memwb_rd         <= 5'b0;
            memwb_reg_write  <= 1'b0;
            memwb_wb_sel     <= 2'b0;
        end else begin
            memwb_alu_result <= exmem_alu_result;
            memwb_mem_rdata  <= mem_rdata_fwd;  // 使用 store-to-load 前递后的数据
            memwb_pc_plus4   <= exmem_pc_plus4;
            memwb_rd         <= exmem_rd;
            memwb_reg_write  <= exmem_reg_write;
            memwb_wb_sel     <= exmem_wb_sel;
        end
    end

// ============================================================
// ===============  WB 阶段  ==================================
// ============================================================
    assign wb_reg_write = memwb_reg_write;
    assign wb_rd        = memwb_rd;
    assign wb_wdata     = (memwb_wb_sel == 2'd1) ? memwb_mem_rdata  :
                          (memwb_wb_sel == 2'd2) ? memwb_pc_plus4   :
                                                   memwb_alu_result;

// ============================================================
// ===============  ILA 调试信号引出  =========================
// dbg_pc   → ifid_pc   (对齐后的PC，与指令真正对应)
// dbg_instr → ifid_instr (IF/ID 锁存的指令，与 ifid_pc 一一对应)
// ============================================================
    (* mark_debug = "true" *) wire [31:0] _dbg_pc           = ifid_pc;       // 对齐后的PC
    (* mark_debug = "true" *) wire [31:0] _dbg_instr        = ifid_instr;    // 对应指令
    (* mark_debug = "true" *) wire        _dbg_wb_reg_write = wb_reg_write;
    (* mark_debug = "true" *) wire [4:0]  _dbg_wb_rd        = wb_rd;
    (* mark_debug = "true" *) wire [31:0] _dbg_wb_wdata     = wb_wdata;
    (* mark_debug = "true" *) wire [31:0] _dbg_ex_alu_result= exmem_alu_result; // 使用寄存后的值,减少组合扇出
    (* mark_debug = "true" *) wire        _dbg_ex_branch    = mem_take_branch;
    (* mark_debug = "true" *) wire [31:0] _dbg_ex_pc_target = mem_branch_target;
    (* mark_debug = "true" *) wire        _dbg_stall        = stall;
    (* mark_debug = "true" *) wire        _dbg_flush        = flush_ifid;

    assign dbg_pc            = _dbg_pc;
    assign dbg_instr         = _dbg_instr;
    assign dbg_wb_reg_write  = _dbg_wb_reg_write;
    assign dbg_wb_rd         = _dbg_wb_rd;
    assign dbg_wb_wdata      = _dbg_wb_wdata;
    assign dbg_ex_alu_result = _dbg_ex_alu_result;
    assign dbg_ex_branch     = _dbg_ex_branch;
    assign dbg_ex_pc_target  = _dbg_ex_pc_target;
    assign dbg_stall         = _dbg_stall;
    assign dbg_flush         = _dbg_flush;

    // ---- 通用寄存器直接引出 (层次路径读取寄存器堆) ----
    (* mark_debug = "true" *) wire [31:0] _dbg_reg_x2 = u_regfile.regs[2];
    (* mark_debug = "true" *) wire [31:0] _dbg_reg_x3 = u_regfile.regs[3];
    (* mark_debug = "true" *) wire [31:0] _dbg_reg_x4 = u_regfile.regs[4];
    (* mark_debug = "true" *) wire [31:0] _dbg_reg_x7 = u_regfile.regs[7];

    assign dbg_reg_x2 = _dbg_reg_x2;
    assign dbg_reg_x3 = _dbg_reg_x3;
    assign dbg_reg_x4 = _dbg_reg_x4;
    assign dbg_reg_x7 = _dbg_reg_x7;

endmodule
