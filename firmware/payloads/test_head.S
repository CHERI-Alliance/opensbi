/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2019 Western Digital Corporation or its affiliates.
 *
 * Authors:
 *   Anup Patel <anup.patel@wdc.com>
 */

#include <sbi/riscv_asm.h>
#include <sbi/riscv_encoding.h>

	.section .entry, "ax", %progbits
	.align 3
	.globl _start
_start:
	/* Pick one hart to run the main boot sequence */
	PTR_L	PREG(a3), _hart_lottery
	li	a2, 1
	amoadd.w a3, a2, (PREG(a3))
	bnez	a3, _start_hang

	/* Save a0 and a1 */
	PTR_L	PREG(a3), _boot_a0
	REG_S	REG(a0), 0(PREG(a3))
	PTR_L	PREG(a3), _boot_a1
	REG_S	REG(a1), 0(PREG(a3))

	/* Zero-out BSS */
	PTR_L	PREG(a4), _bss_start
	PTR_L	PREG(a5), _bss_end
_bss_zero:
	REG_S	REG_ZERO, (PREG(a4))
	add	PREG(a4), PREG(a4), __SIZEOF_POINTER__
	blt	a4, a5, _bss_zero

_start_warm:
	/* Disable and clear all interrupts */
	csrw	CSR_SIE, zero
	csrw	CSR_SIP, zero

	/* Setup exception vectors */
	PTR_L	PREG(a3), _start_hang
	csrw	CSR_STVEC, PREG(a3)

	/* Setup stack */
	PTR_L	PREG(a3), _payload_end
	li	a4, 0x2000
	add	PREG(sp), PREG(a3), a4

	/* Jump to C main */
	PTR_L	PREG(a3), _boot_a0
	REG_L	REG(a0), 0(PREG(a3))
	PTR_L	PREG(a3), _boot_a1
	REG_L	REG(a1), 0(PREG(a3))
	call	test_main

	/* We don't expect to reach here hence just hang */
	j	_start_hang

	.section .entry, "ax", %progbits
	.align 3
	.globl _start_hang
_start_hang:
	wfi
	j	_start_hang

	.section .data
	.align	3
_hart_lottery:
	RISCV_PTR	0
_boot_a0:
	RISCV_PTR	0
_boot_a1:
	RISCV_PTR	0
