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

    // BRAM 接口 (仿真时用内部 reg 模拟)
    reg  [31:0] sim_bram [0:1023];
    wire [9:0]  imem_bram_addrb;
    wire [31:0] imem_bram_doutb;
    assign imem_bram_doutb = sim_bram[imem_bram_addrb];

    cpu_top dut (
        .clk              (clk),
        .rst_n            (rst_n),
        // BRAM Port B
        .imem_bram_addrb  (imem_bram_addrb),
        .imem_bram_clkb   (),
        .imem_bram_enb    (),
        .imem_bram_rstb   (),
        .imem_bram_web    (),
        .imem_bram_dinb   (),
        .imem_bram_doutb  (imem_bram_doutb),
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

    initial begin
        // 初始化仿真 BRAM (替代原 imem 内部 $readmemh)
        $readmemh("../../../../src/imem.hex", sim_bram);

        // 复位
        rst_n = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;

        // 运行足够周期 (10次循环 × 最多4周期/次 + 流水线深度 + 余量)
        repeat(100) @(posedge clk);

        // ---- 结果验证 (通过内部层次路径读取寄存器) ----
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