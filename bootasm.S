#include "asm.h"
#include "memlayout.h"
#include "mmu.h"

# Start the first CPU: switch to 32-bit protected mode, jump into C.
# The BIOS loads this code from the first sector of the hard disk into
# memory at physical address 0x7c00 and starts executing in real mode
# with %cs=0 %ip=7c00.

.code16                       # Assemble for 16-bit mode
.globl start
start:
  cli                         # BIOS enabled interrupts; disable

  # Zero data segment registers DS, ES, and SS.
  xorw    %ax,%ax             # Set %ax to zero
  movw    %ax,%ds             # -> Data Segment
  movw    %ax,%es             # -> Extra Segment
  movw    %ax,%ss             # -> Stack Segment

  # Physical address line A20 is tied to zero so that the first PCs 
  # with 2 MB would run software that assumed 1 MB.  Undo that.
  # ///////////////////////////////////////////////////////////////
  # 这里用了通过键盘控制器端口的方法打开 A20 地址
  # 打开 A20 地址线的方法有三种，具体可参考：
  #     http://kernelx.weebly.com/a20-address-line.html
  #
  # 下面都是针对 804x 键盘控制器端口的操作，这里只介绍用到的两个端口
  #     0x64  从该端口执行 in 读取操作时，读取状态寄存器，8 位，第二
  #           位标识输入缓冲是否有数据所以下面用 0x2 来 test 输入缓冲是否有数据
  #           向该端口执行 out 写操作时，代表向键盘控制器发送命令，发送 0xd1 代
  #           表要向键盘控制器的 P2 端口写入数据，要写入的数据通过 0x60 端口传入
  #
  #     P2    端口，8位，第二位就是 A20 开关，所以在 seta20.2 代码段将 0xdf 通过
  #           0x60 端口写入到 P2 时就会把 A20 置位，A20 打开后，进入保护模式
seta20.1:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.1                # 通过 0x64 状态寄存器的第二位判断键盘缓冲区里是否有数据，如果还有数据，则等待

  movb    $0xd1,%al               # 0xd1 -> port 0x64
  outb    %al,$0x64               # 0xd1 代表向 804x 控制器的 P2 写数据

seta20.2:
  inb     $0x64,%al               # Wait for not busy
  testb   $0x2,%al
  jnz     seta20.2                # 同上，继续判断键盘缓冲区是否有数据，如果有数据，则等待

  movb    $0xdf,%al               # 0xdf -> port 0x60
  outb    %al,$0x60               # 将 0xdf 11011111 写入键盘控制器的 P2 口，意味着 A20 打开，进入保护模式

  # Switch from real to protected mode.  Use a bootstrap GDT that makes
  # virtual addresses map directly to physical addresses so that the
  # effective memory map doesn't change during the transition.
  # 控制寄存器 CR0 为 32 位寄存器，和保护模式相关的控制位
  # **注意大小端**
  # 
  # |31|--------30~1--------| 0|
  # ----------------------------
  # |PG|--------------------|PE|
  # PG : 开启分页式
  # PE : 开启保护模式
  # CR0_PE 在 mmu.h 中定义的 32 位用于控制 CR0
  # CR0_PE : 0x00000001
  # | 0|-------都是0--------| 1|
  # CR0_PE 与 cr0 做或运算保证 PG = 0, PE = 1
  # 至此开启了保护模式，基于分段式，没有打开分页式
  lgdt    gdtdesc          # 先把 GDT 告诉 CPU
  movl    %cr0, %eax       # 把 CR0 寄存器的值复制给 eax 寄存器
  orl     $CR0_PE, %eax    # 与 CR0_PE 做或运算，打开保护模式
  movl    %eax, %cr0

//PAGEBREAK!
  # Complete transition to 32-bit protected mode by using long jmp
  # to reload %cs and %eip.  The segment descriptors are set up with no
  # translation, so that the mapping is still the identity mapping.
  # 
  # 到这里已经进入保护模式了，这里做代码跳转的时候就变成了基于分段式的跳转
  # 分段式跳转 ljmp  段选择子,  段内偏移量
  # 在 GDT 中我们的代码段下标是 1 ，所以这里段选择子是 1 << 3 = 0000 0000 0000 1000
  # 在 16 位的段选择子中前 13 位是 GDT 段表下标，这里前 13 位值是 1 代表选择代码段
  # 而我们的代码段是从 0 开始到 4GB 结尾的，所以这里偏移量不用做转换，还是原偏移即可
  ljmp    $(SEG_KCODE<<3), $start32

.code32  # Tell assembler to generate 32-bit code now.
start32:
  # Set up the protected-mode data segment registers
  # 像上面讲 ljmp 时所说的，这时候已经在保护模式下了
  # 数据段在 GDT 中的下标是 2，所以这里数据段的段选择子是 2 << 3 = 0000 0000 0001 0000
  # 这 16 位的段选择子中的前 13 位是 GDT 段表下标，这里前 13 位的值是 2 代表选择了数据段
  # 这里将 3 个数据段寄存器都赋值成数据段段选择子的值
  movw    $(SEG_KDATA<<3), %ax    # Our data segment selector  段选择子赋值给 ax 寄存器
  movw    %ax, %ds                # -> DS: Data Segment        初始化数据段寄存器
  movw    %ax, %es                # -> ES: Extra Segment       初始化扩展段寄存器
  movw    %ax, %ss                # -> SS: Stack Segment       初始化堆栈段寄存器
  movw    $0, %ax                 # Zero segments not ready for use  ax 寄存器清零
  movw    %ax, %fs                # -> FS                      辅助寄存器清零
  movw    %ax, %gs                # -> GS                      辅助寄存器清零

  # Set up the stack pointer and call into C.
  movl    $start, %esp
  call    bootmain

  # If bootmain returns (it shouldn't), trigger a Bochs
  # breakpoint if running under Bochs, then loop.
  movw    $0x8a00, %ax            # 0x8a00 -> port 0x8a00
  movw    %ax, %dx
  outw    %ax, %dx
  movw    $0x8ae0, %ax            # 0x8ae0 -> port 0x8a00
  outw    %ax, %dx
spin:
  jmp     spin

# **注意大小端**
# Bootstrap GDT
# 每个 GDT 项 8 字节
#
# |31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9|8|7|6|5|4|3|2|1|0|
# |--------------------------------------------------------------------------------------|
# |        基地址         | G|DB|XX|AA|   Limit   | P| DPL | S| E|ED|RW|A|   基地址      |
# |--------------------------------------------------------------------------------------|
# |               基地址                          |          Limit                       |
# |--------------------------------------------------------------------------------------|
#
# 标记位解释：
# P：    0 本段不在内存中
# DPL：  访问该段内存所需权限等级 00 -- 11，0为最大权限级别
# S：    1 代表数据段、代码段或堆栈段，0 代表系统段如中断门或调用门
# E:     1 代表代码段，可执行标记，0 代表数据段
# ED:    0 代表忽略特权级，1 代表遵守特权级
# RW:    如果是数据段（E=0）则1 代表可写入，0 代表只读
#        如果是代码段（E=1）则1 代表可读取，0 代表不可读取
# A:     1 表示该段内存访问过，0 表示没有被访问过
# G:     1 表示 20 位段界限单位是 4KB，最大长度 4GB，
#        0 表示 20 位段界限单位是 1 字节，最大长度 1MB
# DB:    1 表示地址和操作数是 32 位，0 表示地址和操作数是 16 位
# XX:    保留位永远是 0
# AA:    给系统提供的保留位
#
# |31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10| 9|8|7|6|5|4|3|2|1|0|
# |--------------------------------------------------------------------------------------|
# |        基地址         | G|DB|XX|AA|   Limit   | P| DPL | S| E|ED|RW|A|   基地址      |
# |--------------------------------------------------------------------------------------|
# |               基地址                          |          Limit                       |
# |--------------------------------------------------------------------------------------|
#
# 一共 3 个 GDT 项
# 第一个 GDT 项目置空不用
# 第二个 GDT 为代码段，可执行，只读（写好的程序指令是不允许更改的)
# 第三个 GDT 为数据段，可读，可写，不可执行
# 采用平坦内存布局，每个分段均从地址 0x0 开始到 0xffffffff 结束，涵盖整个 4GB 内存寻址空间
# SEG_ASM 宏在 asm.h 中，下面翻译一下最后两个 GDT 项目的数据值
# 代码段 GDT 的布局：
#   0xffff,0x0000,0x00,0x9a,0xcf,0x00
#
# |31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10|9|8|7|6|5|4|3|2|1|0|
# |-------------------------------------------------------------------------------------|
# |         0x00          | 1| 1| 0| 0|     f     | 1|0   0| 1| 1  0 1 0|     0x00      |
# |-------------------------------------------------------------------------------------|
# |               0x0000                          |          0xffff                     |
# |-------------------------------------------------------------------------------------|
#
# 数据段 GDT 的布局：
#   0xffff,0x0000,0x00,0x92,0xcf,0x00
#
# |31|30|29|28|27|26|25|24|23|22|21|20|19|18|17|16|15|14|13|12|11|10|9|8|7|6|5|4|3|2|1|0|
# |-------------------------------------------------------------------------------------|
# |         0x00          | 1| 1| 0| 0|     f     | 1|0   0| 1| 0  0 1 0|     0x00      |
# |-------------------------------------------------------------------------------------|
# |               0x0000                          |          0xffff                     |
# |-------------------------------------------------------------------------------------|
#
.p2align 2                                # force 4 byte alignment
gdt:
  SEG_NULLASM                             # null seg
  SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)   # code seg
  SEG_ASM(STA_W, 0x0, 0xffffffff)         # data seg

gdtdesc:
  .word   (gdtdesc - gdt - 1)             # 16 位的 gdt 大小sizeof(gdt) - 1
  .long   gdt                             # 32 位的 gdt 所在物理地址

