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
  lgdt    gdtdesc
  movl    %cr0, %eax
  orl     $CR0_PE, %eax
  movl    %eax, %cr0

//PAGEBREAK!
  # Complete transition to 32-bit protected mode by using long jmp
  # to reload %cs and %eip.  The segment descriptors are set up with no
  # translation, so that the mapping is still the identity mapping.
  ljmp    $(SEG_KCODE<<3), $start32

.code32  # Tell assembler to generate 32-bit code now.
start32:
  # Set up the protected-mode data segment registers
  movw    $(SEG_KDATA<<3), %ax    # Our data segment selector
  movw    %ax, %ds                # -> DS: Data Segment
  movw    %ax, %es                # -> ES: Extra Segment
  movw    %ax, %ss                # -> SS: Stack Segment
  movw    $0, %ax                 # Zero segments not ready for use
  movw    %ax, %fs                # -> FS
  movw    %ax, %gs                # -> GS

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

# Bootstrap GDT
# 每个 GDT 项 8 字节
.p2align 2                                # force 4 byte alignment
gdt:
  SEG_NULLASM                             # null seg
  SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)   # code seg
  SEG_ASM(STA_W, 0x0, 0xffffffff)         # data seg

gdtdesc:
  .word   (gdtdesc - gdt - 1)             # 16 位的 gdt 大小sizeof(gdt) - 1
  .long   gdt                             # 32 位的 gdt 所在物理地址

