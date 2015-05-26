// Format of an ELF executable file

#define ELF_MAGIC 0x464C457FU  // "\x7FELF" in little endian

// File header
struct elfhdr {
  uint magic;       // 4 字节，始终为 0x7felf 表名该文件是个 ELF 格式文件

  uchar elf[12];    // 12 字节，每字节对应意义如下：
                    //     0 : 1 = 32 位程序；2 = 64 位程序
                    //     1 : 数据编码方式，0 = 无效；1 = 小端模式；2 = 大端模式
                    //     2 : 只是版本，固定为 0x1
                    //     3 : 目标操作系统架构
                    //     4 : 目标操作系统版本
                    //     5 ~ 11 : 固定为 0
                    
  ushort type;      // 2 字节，表明该文件类型，意义如下：
                    //     0x0 : 未知目标文件格式
                    //     0x1 : 可重定位文件
                    //     0x2 : 可执行文件
                    //     0x3 : 共享目标文件
                    //     0x4 : 转储文件
                    //     0xff00 : 特定处理器文件
                    //     0xffff : 特定处理器文件

  ushort machine;   // 2 字节，表明运行该程序需要的计算机体系架构，这里我们只需要知道 0x0 为未指定；0x3 为 x86 架构

  uint version;     // 4 字节，表示该文件的版本号

  uint entry;       // 4 字节，该文件的入口地址，没有入口（非可执行文件）则为 0

  uint phoff;       // 4 字节，表示该文件的“程序头部表”相对于文件的位置，单位是字节

  uint shoff;       // 4 字节，表示该文件的“节区头部表”相对于文件的位置，单位是字节

  uint flags;       // 4 字节，特定处理器标志

  ushort ehsize;    // 2 字节，ELF文件头部的大小，单位是字节

  ushort phentsize; // 2 字节，表示程序头部表中一个入口的大小，单位是字节

  ushort phnum;     // 2 字节，表示程序头部表的入口个数，phnum * phentsize = 程序头部表大小（单位是字节）

  ushort shentsize; // 2 字节，节区头部表入口大小，单位是字节

  ushort shnum;     // 2 字节，节区头部表入口个数，shnum * shentsize = 节区头部表大小（单位是字节）

  ushort shstrndx;  // 2 字节，表示字符表相关入口的节区头部表索引
};

// Program section header
struct proghdr {
  uint type;        // 4 字节， 段类型
                    //         1 PT_LOAD : 可载入的段
                    //         2 PT_DYNAMIC : 动态链接信息
                    //         3 PT_INTERP : 指定要作为解释程序调用的以空字符结尾的路径名的位置和大小
                    //         4 PT_NOTE : 指定辅助信息的位置和大小
                    //         5 PT_SHLIB : 保留类型，但具有未指定的语义
                    //         6 PT_PHDR : 指定程序头表在文件及程序内存映像中的位置和大小
                    //         7 PT_TLS : 指定线程局部存储模板
  uint off;         // 4 字节， 段的第一个字节在文件中的偏移
  uint vaddr;       // 4 字节， 段的第一个字节在内存中的虚拟地址
  uint paddr;       // 4 字节， 段的第一个字节在内存中的物理地址(适用于物理内存定位型的系统)
  uint filesz;      // 4 字节， 段在文件中的长度
  uint memsz;       // 4 字节， 段在内存中的长度
  uint flags;       // 4 字节， 段标志
                    //         1 : 可执行
                    //         2 : 可写入
                    //         4 : 可读取
  uint align;       // 4 字节， 段在文件及内存中如何对齐
};

// Values for Proghdr type
#define ELF_PROG_LOAD           1

// Flag bits for Proghdr flags
#define ELF_PROG_FLAG_EXEC      1
#define ELF_PROG_FLAG_WRITE     2
#define ELF_PROG_FLAG_READ      4
