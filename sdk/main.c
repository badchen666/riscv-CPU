#include "xparameters.h"
#include "xil_printf.h"
#include "ff.h"
#include "xdevcfg.h"
#include "xil_io.h"
#include <stdlib.h>

#define FILE_NAME       "imem.hex"          //定义文件名
#define RAM_DEPTH       1024                //RAM深度（最多存放多少个32bit数据）

// 请根据 xparameters.h 中的实际宏名称修改此处
#define CPU_AXI_BASEADDR    XPAR_RISCV_CPU_0_S00_AXI_BASEADDR

// AXI寄存器偏移地址
#define REG_INSTR_ADDR      0x00    // slv_reg0: RAM写地址
#define REG_INSTR_DATA      0x04    // slv_reg1: 写入的指令数据
#define REG_INSTR_CTRL      0x08    // slv_reg2: [0]=ena, [1]=wea
#define REG_CPU_RST         0x0C    // slv_reg3: [0]=CPU复位控制

// 控制位定义
#define INSTR_ENA           (1 << 0)    // instr_ena
#define INSTR_WEA           (1 << 1)    // instr_wea
#define CPU_RST_ASSERT      0           // CPU复位（低电平有效）
#define CPU_RST_DEASSERT    1           // CPU运行

static FATFS fatfs;                     //文件系统
//初始化文件系统
int platform_init_fs()
{
	FRESULT status;
	TCHAR *Path = "0:/";
	BYTE work[FF_MAX_SS];

    //注册一个工作区(挂载分区文件系统)
    //在使用任何其它文件函数之前，必须使用f_mount函数为每个使用卷注册一个工作区
	status = f_mount(&fatfs, Path, 1);  //挂载SD卡
	if (status != FR_OK) {
		xil_printf("Volume is not FAT formated; formating FAT\r\n");
		//格式化SD卡
		status = f_mkfs(Path, FM_FAT32, 0, work, sizeof work);
		if (status != FR_OK) {
			xil_printf("Unable to format FATfs\r\n");
			return -1;
		}
		//格式化之后，重新挂载SD卡
		status = f_mount(&fatfs, Path, 1);
		if (status != FR_OK) {
			xil_printf("Unable to mount FATfs\r\n");
			return -1;
		}
		xil_printf("Unable to mount FATfs\r\n");
	}
	return 0;
}

//挂载SD(TF)卡
int sd_mount()
{
    FRESULT status;
    //初始化文件系统（挂载SD卡，如果挂载不成功，则格式化SD卡）
    status = platform_init_fs();
    if(status){
        xil_printf("ERROR: f_mount returned %d!\r\n",status);
        return XST_FAILURE;
    }
    return XST_SUCCESS;
}

//SD卡写数据
int sd_write_data(char *file_name,u32 src_addr,u32 byte_len)
{
    FIL fil;         //文件对象
    UINT bw;         //f_write函数返回已写入的字节数

    //打开一个文件,如果不存在，则创建一个文件
    f_open(&fil,file_name,FA_CREATE_ALWAYS | FA_WRITE);
    //移动打开的文件对象的文件读/写指针     0:指向文件开头
    f_lseek(&fil, 0);
    //向文件中写入数据
    f_write(&fil,(void*) src_addr,byte_len,&bw);
    //关闭文件
    f_close(&fil);
    return 0;
}

//SD卡读数据
int sd_read_data(char *file_name,u32 src_addr,u32 byte_len)
{
	FIL fil;         //文件对象
    UINT br;         //f_read函数返回已读出的字节数

    //打开一个只读的文件
    f_open(&fil,file_name,FA_READ);
    //移动打开的文件对象的文件读/写指针     0:指向文件开头
    f_lseek(&fil,0);
    //从SD卡中读出数据
    f_read(&fil,(void*)src_addr,byte_len,&br);
    //关闭文件
    f_close(&fil);
    return 0;
}

int main()
{
    int status;
    UINT len;
    FILINFO fno;
    static char read_buffer[8192];

    // =============================================
    // Step1: 将CPU置于复位状态，等待指令加载完成
    // =============================================
    Xil_Out32(CPU_AXI_BASEADDR + REG_CPU_RST, CPU_RST_ASSERT);
    // 先禁用RAM写使能
    Xil_Out32(CPU_AXI_BASEADDR + REG_INSTR_CTRL, 0);
    xil_printf("CPU is held in reset.\r\n");

    // =============================================
    // Step2: 挂载SD卡
    // =============================================
    status = sd_mount();
    if(status != XST_SUCCESS){
        xil_printf("Failed to open SD card!\r\n");
        return 0;
    }
    else {
        xil_printf("Success to open SD card!\r\n");
    }

    // =============================================
    // Step3: 获取文件大小并读取hex文件
    // =============================================
    status = f_stat(FILE_NAME, &fno);
    if (status != FR_OK) {
        xil_printf("Failed to stat file %s\r\n", FILE_NAME);
        return 0;
    }

    len = fno.fsize;
    xil_printf("File %s size: %d bytes\r\n", FILE_NAME, len);

    if (len >= sizeof(read_buffer)) {
        xil_printf("File too large for buffer!\r\n");
        return 0;
    }

    sd_read_data(FILE_NAME, (u32)read_buffer, len);
    read_buffer[len] = '\0';

    // =============================================
    // Step4: 解析hex文件，通过AXI寄存器逐字写入RAM
    // 写入流程：
    //   1. 写地址到 slv_reg0 (REG_INSTR_ADDR)
    //   2. 写数据到 slv_reg1 (REG_INSTR_DATA)
    //   3. 拉高 ena 和 wea（slv_reg2）触发写入
    //   4. 拉低 ena 和 wea，准备下一次写入
    // =============================================
    xil_printf("--- Start writing instructions to RAM ---\r\n");

    char *ptr = read_buffer;
    char *endptr;
    u32 word_addr = 0;      // RAM字地址（每次+1，对应RAM的地址输入）
    u32 write_count = 0;

    while (*ptr != '\0' && write_count < RAM_DEPTH) {
        // 跳过空格、换行符和回车符
        while (*ptr == ' ' || *ptr == '\n' || *ptr == '\r') {
            ptr++;
        }
        if (*ptr == '\0') break;

        // 将当前行的16进制字符串转换为32位无符号整数
        u32 val = (u32)strtoul(ptr, &endptr, 16);
        if (ptr == endptr) break;
        ptr = endptr;

        // 1. 写RAM地址
        Xil_Out32(CPU_AXI_BASEADDR + REG_INSTR_ADDR, word_addr);
        // 2. 写指令数据
        Xil_Out32(CPU_AXI_BASEADDR + REG_INSTR_DATA, val);
        // 3. 拉高 ena 和 wea，触发RAM写入
        Xil_Out32(CPU_AXI_BASEADDR + REG_INSTR_CTRL, INSTR_ENA | INSTR_WEA);
        // 4. 拉低 ena 和 wea
        Xil_Out32(CPU_AXI_BASEADDR + REG_INSTR_CTRL, 0);

        xil_printf("RAM[%4d] addr=0x%04X  val=0x%08X\r\n", write_count, word_addr, val);

        word_addr++;
        write_count++;
    }

    xil_printf("--- Done! Wrote %d instructions to RAM ---\r\n", write_count);

    // =============================================
    // Step5: 释放CPU复位，CPU开始从地址0取指运行
    // =============================================
    Xil_Out32(CPU_AXI_BASEADDR + REG_CPU_RST, CPU_RST_DEASSERT);
    xil_printf("CPU reset released, CPU is now running!\r\n");

    return 0;
}
