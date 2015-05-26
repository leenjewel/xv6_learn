// Boot loader.
// 
// Part of the boot sector, along with bootasm.S, which calls bootmain().
// bootasm.S has put the processor into protected 32-bit mode.
// bootmain() loads an ELF kernel image from the disk starting at
// sector 1 and then jumps to the kernel entry routine.

#include "types.h"
#include "elf.h"
#include "x86.h"
#include "memlayout.h"

#define SECTSIZE  512  // 硬盘扇区大小 512 字节

void readseg(uchar*, uint, uint);

void
bootmain(void)
{
  struct elfhdr *elf;
  struct proghdr *ph, *eph;
  void (*entry)(void);
  uchar* pa;

  elf = (struct elfhdr*)0x10000;  // scratch space

  // 从内核所在硬盘位置读取一内存页 4kb 数据
  readseg((uchar*)elf, 4096, 0);

  // 判断是否为 ELF 文件格式
  if(elf->magic != ELF_MAGIC)
    return;  // let bootasm.S handle error

  // 加载 ELF 文件中的程序段 (ignores ph flags).
  // 找到内核 ELF 文件的程序头表
  ph = (struct proghdr*)((uchar*)elf + elf->phoff);
  // 内核 ELF 文件程序头表的结束位置
  eph = ph + elf->phnum;
  // 开始将内核 ELF 文件程序头表载入内存
  for(; ph < eph; ph++){
    pa = (uchar*)ph->paddr;
    readseg(pa, ph->filesz, ph->off);
    // 如果内存大小大于文件大小，用 0 补齐内存空位
    if(ph->memsz > ph->filesz)
      stosb(pa + ph->filesz, 0, ph->memsz - ph->filesz);
  }

  // Call the entry point from the ELF header.
  // Does not return!
  // 从内核 ELF 文件入口点开始执行内核
  entry = (void(*)(void))(elf->entry);
  entry();
}

void
waitdisk(void)
{
  // Wait for disk ready.
  // xxxxxxxx & 11000000 != 01000000
  // 0x1F7 状态位
  //     bit 7 = 1  控制器忙
  //     bit 6 = 1  驱动器就绪
  //     bit 5 = 1  设备错误
  //     bit 4        N/A
  //     bit 3 = 1  扇区缓冲区错误
  //     bit 2 = 1  磁盘已被读校验
  //     bit 1        N/A
  //     bit 0 = 1  上一次命令执行失败
  while((inb(0x1F7) & 0xC0) != 0x40)
    ;
}

// Read a single sector at offset into dst.
// 这里使用的是 LBA 磁盘寻址模式
// LBA是非常单纯的一种寻址模式﹔从0开始编号来定位区块，
// 第一区块LBA=0，第二区块LBA=1，依此类推
void
readsect(void *dst, uint offset)      // 0x10000, 1
{
  // Issue command.
  waitdisk();
  outb(0x1F2, 1);                     // 要读取的扇区数量 count = 1
  outb(0x1F3, offset);                // 扇区 LBA 地址的 0-7 位
  outb(0x1F4, offset >> 8);           // 扇区 LBA 地址的 8-15 位
  outb(0x1F5, offset >> 16);          // 扇区 LBA 地址的 16-23 位
  outb(0x1F6, (offset >> 24) | 0xE0); // offset | 11100000 保证高三位恒为 1
                                      //         第7位     恒为1
                                      //         第6位     LBA模式的开关，置1为LBA模式
                                      //         第5位     恒为1
                                      //         第4位     为0代表主硬盘、为1代表从硬盘
                                      //         第3~0位   扇区 LBA 地址的 24-27 位
  outb(0x1F7, 0x20);                  // 20h为读，30h为写

  // Read data.
  waitdisk();
  insl(0x1F0, dst, SECTSIZE/4);
}

// Read 'count' bytes at 'offset' from kernel into physical address 'pa'.
// Might copy more than asked.
void
readseg(uchar* pa, uint count, uint offset)  // 0x10000, 4096(0x1000), 0
{
  uchar* epa;

  epa = pa + count;  // 0x11000

  // 根据扇区大小 512 字节做对齐
  pa -= offset % SECTSIZE;

  // bootblock 引导区在第一扇区（下标为 0），内核在第二个扇区（下标为 1）
  // 这里做 +1 操作是统一略过引导区
  offset = (offset / SECTSIZE) + 1;

  // If this is too slow, we could read lots of sectors at a time.
  // We'd write more to memory than asked, but it doesn't matter --
  // we load in increasing order.
  // 一次读取一个扇区 512 字节的数据
  for(; pa < epa; pa += SECTSIZE, offset++)
    readsect(pa, offset);
}
