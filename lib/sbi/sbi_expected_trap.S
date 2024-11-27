/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2020 Western Digital Corporation or its affiliates.
 *
 * Authors:
 *   Anup Patel <anup.patel@wdc.com>
 */

#include <sbi/riscv_asm.h>
#include <sbi/sbi_trap.h>

	/*
	 * We assume that faulting instruction is 4-byte long and blindly
	 * increment SEPC by 4.
	 *
	 * The trap info will be saved as follows:
	 * A3 <- pointer struct sbi_trap_info
	 * A4 <- temporary
	 */

	.align 3
	.global __sbi_expected_trap
	.type 	__sbi_expected_trap, @function
__sbi_expected_trap:
	/* Without H-extension so, MTVAL2 and MTINST CSRs and GVA not available */
	csrr	a4, CSR_MCAUSE
	XREG_S	a4, SBI_TRAP_INFO_OFFSET(cause)(PREG(a3))
	csrr	a4, CSR_MTVAL
	XREG_S	a4, SBI_TRAP_INFO_OFFSET(tval)(PREG(a3))
	XREG_S	zero, SBI_TRAP_INFO_OFFSET(tval2)(PREG(a3))
	XREG_S	zero, SBI_TRAP_INFO_OFFSET(tinst)(PREG(a3))
	XREG_S	zero, SBI_TRAP_INFO_OFFSET(gva)(PREG(a3))
	csrr	PREG(a4), CSR_MEPC
	add	PREG(a4), PREG(a4), 4
	csrw	CSR_MEPC, PREG(a4)
	mret
	.size __sbi_expected_trap, . - __sbi_expected_trap

	.align 3
	.global __sbi_expected_trap_hext
	.type 	__sbi_expected_trap_hext, @function
__sbi_expected_trap_hext:
	/* With H-extension so, MTVAL2 and MTINST CSRs and GVA available */
	csrr	a4, CSR_MCAUSE
	XREG_S	a4, SBI_TRAP_INFO_OFFSET(cause)(PREG(a3))
	csrr	a4, CSR_MTVAL
	XREG_S	a4, SBI_TRAP_INFO_OFFSET(tval)(PREG(a3))
	csrr	a4, CSR_MTVAL2
	XREG_S	a4, SBI_TRAP_INFO_OFFSET(tval2)(PREG(a3))
	csrr	a4, CSR_MTINST
	XREG_S	a4, SBI_TRAP_INFO_OFFSET(tinst)(PREG(a3))

	/* Extract GVA bit from MSTATUS or MSTATUSH */
#if __riscv_xlen == 32
	csrr	a4, CSR_MSTATUSH
	srli	a4, a4, MSTATUSH_GVA_SHIFT
#else
	csrr	a4, CSR_MSTATUS
	srli	a4, a4, MSTATUS_GVA_SHIFT
#endif
	andi	a4, a4, 1
	XREG_S	a4, SBI_TRAP_INFO_OFFSET(gva)(PREG(a3))

	csrr	PREG(a4), CSR_MEPC
	add	PREG(a4), PREG(a4), 4
	csrw	CSR_MEPC, PREG(a4)
	mret
	.size __sbi_expected_trap_hext, . - __sbi_expected_trap_hext
