// ============================================================
// Testbench for RISC-V 32I 五级流水线 CPU
//
// 测试程序 (imem.hex): 计算 1+2+3+...+10 = 55
//   addi  x1, x0, 11     # x1 = 11 (循环哨兵)
//   addi  x2, x0, 0      # x2 = 0  (累加器 sum)
//   addi  x5, x0, 1      # x5 = 1  (步长)
//   addi  x6, x0, 1      # x6 = 1  (循环变量 i)
// loop:
//   add   x2, x2, x6     # sum += i   [EX-EX 前递]
//   addi  x6, x6, 1      # i++
//   bne   x1, x6, loop   # i!=11 则继续  [控制冒险]
//   sw    x2, 0(x0)      # mem[0] = 55
//   lw    x3, 0(x0)      # x3 = 55  [Load-Use 冒险]
//   add   x4, x3, x0     # x4 = 55  [MEM-EX 前递]
//   lui   x7, 0xDEAD     # x7 = 0x0DEAD000 (结束标志)
//   jal   x0, 0          # 原地死循环
// ============================================================
`include "defines.v"
`timescale 1ns/1ps

module tb_cpu;

    reg clk;
    reg rst_n;

    // 时钟: 10ns 周期
    initial clk = 0;
    always #5 clk = ~clk;

    // ILA 调试观测信号 (仿真时直接打印查看)
    wire [31:0] dbg_pc;
    wire [31:0] dbg_instr;
    wire        dbg_wb_reg_write;
    wire [4:0]  dbg_wb_rd;
    wire [31:0] dbg_wb_wdata;
    wire [31:0] dbg_ex_alu_result;
    wire        dbg_ex_branch;
    wire [31:0] dbg_ex_pc_target;
    wire        dbg_stall;
    wire        dbg_flush;

    // ---- 指令加载接口 (模拟 PS 通过 AXI BRAM Controller 写入) ----
    reg  [31:0] instr_addra;
    reg  [31:0] instr_data;
    reg         instr_ena;
    reg         instr_wea;

    cpu_top dut (
        .clk              (clk),
        .rst_n            (rst_n),
        // BRAM Port A (写入指令)
        .instr_addra      (instr_addra),
        .instr_data       (instr_data),
        .instr_ena        (instr_ena),
        .instr_wea        (instr_wea),
        // ILA 调试端口
        .dbg_pc           (dbg_pc),
        .dbg_instr        (dbg_instr),
        .dbg_wb_reg_write (dbg_wb_reg_write),
        .dbg_wb_rd        (dbg_wb_rd),
        .dbg_wb_wdata     (dbg_wb_wdata),
        .dbg_ex_alu_result(dbg_ex_alu_result),
        .dbg_ex_branch    (dbg_ex_branch),
        .dbg_ex_pc_target (dbg_ex_pc_target),
        .dbg_stall        (dbg_stall),
        .dbg_flush        (dbg_flush)
    );

    // ---- 指令ROM：硬编码，避免 $readmemh 路径问题 ----
    // 地址 0x00~0x2C 共 12 条指令 (字地址 0~11)
    reg [31:0] instr_rom [0:11];
    integer i;

    initial begin
        instr_rom[0]  = 32'h00B00093; // addi x1,  x0, 11
        instr_rom[1]  = 32'h00000113; // addi x2,  x0, 0
        instr_rom[2]  = 32'h00100293; // addi x5,  x0, 1
        instr_rom[3]  = 32'h00100313; // addi x6,  x0, 1
        instr_rom[4]  = 32'h00610133; // add  x2,  x2, x6   (loop)
        instr_rom[5]  = 32'h00130313; // addi x6,  x6, 1
        instr_rom[6]  = 32'hFE609CE3; // bne  x1,  x6, loop  (offset=-8, target=0x10)
        instr_rom[7]  = 32'h00202023; // sw   x2,  0(x0)
        instr_rom[8]  = 32'h00002183; // lw   x3,  0(x0)
        instr_rom[9]  = 32'h00018233; // add  x4,  x3, x0
        instr_rom[10] = 32'h0DEAD3B7; // lui  x7,  0xDEAD
        instr_rom[11] = 32'h0000006F; // jal  x0,  0
        // 尝试从 hex 文件覆盖 (xsim 工作目录: cpu_test.sim/sim_1/behav/xsim/)
        $readmemh("../../../../src/imem.hex", instr_rom);
        $display("[TB] instr_rom[0]=0x%08X (expect 0x00B00093)", instr_rom[0]);
        $display("[TB] instr_rom[6]=0x%08X (expect 0xFE609CE3)", instr_rom[6]);
        // 直接通过层次路径将指令写入 instr_ram.ram——完全绕过 $readmemh 路径不确定性
        // 这保证即使 $readmemh 加载失败， ram 里也已有正确指令而不是 X
        // #0 延迟保证在所有 initial 块（包括 instr_ram 内部的 $readmemh）执行后再覆盖
        #0;
        dut.u_imem.instr_ram.ram[0]  = instr_rom[0];
        dut.u_imem.instr_ram.ram[1]  = instr_rom[1];
        dut.u_imem.instr_ram.ram[2]  = instr_rom[2];
        dut.u_imem.instr_ram.ram[3]  = instr_rom[3];
        dut.u_imem.instr_ram.ram[4]  = instr_rom[4];
        dut.u_imem.instr_ram.ram[5]  = instr_rom[5];
        dut.u_imem.instr_ram.ram[6]  = instr_rom[6];
        dut.u_imem.instr_ram.ram[7]  = instr_rom[7];
        dut.u_imem.instr_ram.ram[8]  = instr_rom[8];
        dut.u_imem.instr_ram.ram[9]  = instr_rom[9];
        dut.u_imem.instr_ram.ram[10] = instr_rom[10];
        dut.u_imem.instr_ram.ram[11] = instr_rom[11];
    end

    task load_instructions;
        integer j;
    begin
        $display("加载 12 条指令到 instr_ram...");
        instr_ena = 1'b1;
        instr_wea = 1'b1;
        for (j = 0; j < 12; j = j + 1) begin
            @(negedge clk);
            instr_addra = j;
            instr_data  = instr_rom[j];
            @(posedge clk);
            $display("  写入 ram[%0d] = 0x%08X", j, instr_rom[j]);
        end
        @(negedge clk);
        instr_ena   = 1'b0;
        instr_wea   = 1'b0;
        instr_addra = 32'b0;
        instr_data  = 32'b0;
    end
    endtask

    // ---- 主测试流程 ----
    initial begin
        // 初始状态: 保持复位
        rst_n       = 0;
        instr_addra = 32'b0;
        instr_data  = 32'b0;
        instr_ena   = 1'b0;
        instr_wea   = 1'b0;

        repeat(2) @(posedge clk);

        // 在复位期间加载指令到 instr_ram
        load_instructions;

        // 多等几拍确保写入完成，再释放复位
        repeat(3) @(posedge clk);
        rst_n = 1;
        $display("复位释放，CPU 开始运行...");

        // 每拍打印流水线状态 (足够运行完整个测试程序)
        repeat(150) begin
            @(posedge clk);
            #1; // 等待组合逻辑稳定
            $display("T=%0t | PC=%08X INSTR=%08X | WB: wr=%b rd=x%0d data=%08X | ALU=%08X | br=%b tgt=%08X | stall=%b flush=%b",
                $time, dbg_pc, dbg_instr,
                dbg_wb_reg_write, dbg_wb_rd, dbg_wb_wdata,
                dbg_ex_alu_result,
                dbg_ex_branch, dbg_ex_pc_target,
                dbg_stall, dbg_flush);
        end

        // ---- 结果验证 (通过内部层次路径读取寄存器) ----
        $display("");
        $display("=== 仿真结果 ===");
        $display("x1 = %0d  (期望 11)",           dut.u_regfile.regs[1]);
        $display("x2 = %0d  (期望 55, sum)",       dut.u_regfile.regs[2]);
        $display("x3 = %0d  (期望 55, lw读回)",    dut.u_regfile.regs[3]);
        $display("x4 = %0d  (期望 55, MEM前递)",   dut.u_regfile.regs[4]);
        $display("x5 = %0d  (期望  1, 步长)",      dut.u_regfile.regs[5]);
        $display("x6 = %0d  (期望 11, i最终值)",   dut.u_regfile.regs[6]);
        $display("x7 = 0x%08X  (期望 0x0DEAD000)", dut.u_regfile.regs[7]);
        $display("mem[0] = %0d  (期望 55)", dut.u_dmem.mem[0]);

        // ---- ILA 调试端口最终状态 ----
        $display("--- ILA 端口快照 ---");
        $display("dbg_pc            = 0x%08X", dbg_pc);
        $display("dbg_instr         = 0x%08X", dbg_instr);
        $display("dbg_wb_reg_write  = %b",     dbg_wb_reg_write);
        $display("dbg_wb_rd         = x%0d",   dbg_wb_rd);
        $display("dbg_wb_wdata      = %0d",    dbg_wb_wdata);
        $display("dbg_ex_alu_result = %0d",    dbg_ex_alu_result);
        $display("dbg_ex_branch     = %b",     dbg_ex_branch);
        $display("dbg_ex_pc_target  = 0x%08X", dbg_ex_pc_target);
        $display("dbg_stall         = %b",     dbg_stall);
        $display("dbg_flush         = %b",     dbg_flush);

        // 检查是否通过
        if (dut.u_regfile.regs[1] == 32'd11       &&
            dut.u_regfile.regs[2] == 32'd55        &&
            dut.u_regfile.regs[3] == 32'd55        &&
            dut.u_regfile.regs[4] == 32'd55        &&
            dut.u_regfile.regs[5] == 32'd1         &&
            dut.u_regfile.regs[6] == 32'd11        &&
            dut.u_regfile.regs[7] == 32'h0DEAD000) begin
            $display(">>> 所有测试通过! <<<");
        end else begin
            $display(">>> 测试失败! <<<");
        end

        $finish;
    end

    // 波形文件
    initial begin
        $dumpfile("cpu_wave.vcd");
        $dumpvars(0, tb_cpu);
    end

endmodule