module  instr_ram (
    input clk,
    input ena,
    input enb,
    input wea,
    input [31:0] addra,
    input [31:0] addrb,
    input [31:0] dina,
    output reg [31:0] doutb
);

 (* ram_style = "block" *)reg [31:0] ram [1023:0];

    // 仿真初始化：直接从 hex 文件预加载，避免 doutb 读出 X
    // xsim 工作目录为 cpu_test.sim/sim_1/behav/xsim/
    initial begin
        $readmemh("../../../../src/imem.hex", ram);
    end

always @(posedge clk)  //写
    if (ena) 
        if (wea) ram[addra] <= dina;

always @(posedge clk) 
    if (enb) doutb <= ram[addrb];  //读

endmodule