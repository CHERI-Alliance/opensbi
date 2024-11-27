/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2019 Western Digital Corporation or its affiliates.
 *
 * Authors:
 *   Anup Patel <anup.patel@wdc.com>
 */

#include <sbi/riscv_asm.h>
#include <sbi/sbi_ecall_interface.h>
#include <sbi/sbi_string.h>

struct sbiret {
	unsigned long error;
	unsigned long value;
};

struct sbiret sbi_ecall(int ext, int fid, uintptr_t arg0,
			uintptr_t arg1, uintptr_t arg2,
			uintptr_t arg3, uintptr_t arg4,
			uintptr_t arg5)
{
	struct sbiret ret;

	register uintptr_t a0 asm (REG(a0)) = (uintptr_t)(arg0);
	register uintptr_t a1 asm (REG(a1)) = (uintptr_t)(arg1);
	register uintptr_t a2 asm (REG(a2)) = (uintptr_t)(arg2);
	register uintptr_t a3 asm (REG(a3)) = (uintptr_t)(arg3);
	register uintptr_t a4 asm (REG(a4)) = (uintptr_t)(arg4);
	register uintptr_t a5 asm (REG(a5)) = (uintptr_t)(arg5);
	register uintptr_t a6 asm (REG(a6)) = (uintptr_t)(fid);
	register uintptr_t a7 asm (REG(a7)) = (uintptr_t)(ext);
	asm volatile ("ecall"
		      : "+" PTR_REG (a0), "+" PTR_REG (a1)
		      : PTR_REG (a2), PTR_REG (a3), PTR_REG (a4), PTR_REG (a5), PTR_REG (a6), PTR_REG (a7)
		      : "memory");
	ret.error = (unsigned long)a0;
	ret.value = (unsigned long)a1;

	return ret;
}

static inline void sbi_ecall_console_puts(const char *str)
{
	sbi_ecall(SBI_EXT_DBCN, SBI_EXT_DBCN_CONSOLE_WRITE,
		  sbi_strlen(str), (unsigned long)str, 0, 0, 0, 0);
}

#define wfi()                                             \
	do {                                              \
		__asm__ __volatile__("wfi" ::: "memory"); \
	} while (0)

void test_main(uintptr_t a0, uintptr_t a1)
{
	sbi_ecall_console_puts("\nTest payload running\n");

	while (1)
		wfi();
}
