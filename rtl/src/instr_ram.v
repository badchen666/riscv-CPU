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

integer i;
initial begin
        for (i = 0; i < 1024; i = i + 1) begin
            ram[i] = 32'h00000000;
        end
    end

always @(posedge clk)  //Ğ´
    if (ena) 
        if (wea) ram[addra] <= dina;

always @(posedge clk) 
    if (enb) doutb <= ram[addrb];  //¶Á

endmodule