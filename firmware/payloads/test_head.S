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
#if defined(__riscv_atomic) || defined(__riscv_zaamo)
	amoadd.w a3, a2, (PREG(a3))
#elif defined(__riscv_zalrsc)
_sc_fail:
	lr.w	t0, (PREG(a3))
	addw	t1, t0, a2
	sc.w	t1, t1, (PREG(a3))
	bnez	t1, _sc_fail
	move	a3, t0
#else
#error "need a or zalrsc"
#endif
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

	/* This will be called when the stack corruption is detected */
	.section .text
	.align 3
	.globl __stack_chk_fail
	.type __stack_chk_fail, %function
	.equ  __stack_chk_fail, _start_hang

	/* Initial value of the stack guard variable */
	.section .data
	.align 3
	.globl __stack_chk_guard
	.type __stack_chk_guard, %object
__stack_chk_guard:
	RISCV_PTR	0x95B5FF5A
