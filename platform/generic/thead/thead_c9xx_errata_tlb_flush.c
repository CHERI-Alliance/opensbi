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
#include <sbi/riscv_cheri.h>

void _thead_tlb_flush_fixup_trap_handler(void);

void thead_register_tlb_flush_trap_handler(void)
{
	uintptr_t mtvec = (uintptr_t)&_thead_tlb_flush_fixup_trap_handler;
#if defined(__CHERI_PURE_CAPABILITY__)
	mtvec = (uintptr_t)cheri_address_set(cheri_pcc_get(), mtvec);
#endif
	ptr_csr_write(CSR_MTVEC, mtvec);
}
