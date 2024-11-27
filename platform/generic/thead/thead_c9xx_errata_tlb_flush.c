/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Authors:
 *   Inochi Amaoto <inochiama@outlook.com>
 *
 */

#include <sbi/riscv_encoding.h>
#include <sbi/riscv_asm.h>
#include <sbi/sbi_types.h>

void _thead_tlb_flush_fixup_trap_handler(void);

void thead_register_tlb_flush_trap_handler(void)
{
	ptr_csr_write(CSR_MTVEC, (uintptr_t)&_thead_tlb_flush_fixup_trap_handler);
}
