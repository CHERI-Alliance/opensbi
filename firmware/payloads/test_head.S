/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2019 Western Digital Corporation or its affiliates.
 *
 * Authors:
 *   Anup Patel <anup.patel@wdc.com>
 */

#include <sbi/riscv_asm.h>
#include <sbi/riscv_cheri.h>
#include <sbi/riscv_elf.h>
#include <sbi/riscv_encoding.h>

.macro set_cap_perm rd rs scratch perm
#if defined(__riscv_y)
	li	\scratch, ~(\perm)
	ypermc	\rd, \rs, \scratch
#else
	li	\scratch, \perm
	acperm	REG(\rd), REG(\rd), \scratch
#endif
.endm

	.section .entry, "ax", %progbits
	.align 3
	.globl _start
_start:
#if defined(__CHERI__)
	/* Run test in capability pointer mode */
#if defined(__riscv_zyhybrid) || defined(__riscv_zcherihybrid)
	ymodeswy
#endif
	/* Save infinite capability */
	auipc 	a2, 0
	PC_PTR_L	a3, cheri_infinite_cap
	PREG_S	a2, 0(a3)
#endif

	/* Pick one hart to run the main boot sequence */
	PC_PTR_L	a3, _hart_lottery
	li	a2, 1
#if defined(__riscv_atomic) || defined(__riscv_zaamo)
	amoadd.w a3, a2, (a3)
#elif defined(__riscv_zalrsc)
_sc_fail:
	lr.w	t0, (a3)
	addw	t1, t0, a2
	sc.w	t1, t1, (a3)
	bnez	t1, _sc_fail
	move	a3, t0
#else
#error "need a or zalrsc"
#endif
	bnez	a3, _start_hang

	/* Save a0 and a1 */
	PC_PTR_L	a3, _boot_a0
	REG_S		a0, 0(a3)
	PC_PTR_L	a3, _boot_a1
	REG_S		a1, 0(a3)


#if defined(__CHERI__)
#if defined(FW_PAYLOAD_OFFSET)
	li		t0, (FW_TEXT_START+FW_PAYLOAD_OFFSET)	/* link start */
#else
	mv		t0, zero
#endif
	lly		t1, _payload_start	/* load start */
	sub		t2, t1, t0	/* load offset */

	lly		a3, cheri_infinite_cap
	ly		a3, 0(a3)

cheri_cap_init:
	lly		t0, __cap_relocs_start
	lly		t1, __cap_relocs_end
	beq		t0, t1, _cheri_cap_init_done

2:	XREG_L	t3, 0(t0)	/* t3 <-- capreloc:capability_location */
	add	t3, t3, t2
	yaddrw	t3, a3, t3 	/* t3 <-- W permission capability points to capability */
	XREG_L	t4, SZXREG(t0)	/* t4 <-- capreloc:capability_base */
	bnez	t4, 3f		/* write cnull if capreloc:capability_base is zero */

	j	10f		/* Initialize next capability */

3:	/* Set address/base */
	add	t4, t4, t2
	yaddrw	t5, a3, t4	/* t5 <-- Set base from a Infinite capability */

	/* Set M-bit for all capability as purecap mode */
#if defined(__riscv_zyhybrid) || defined(__riscv_zcherihybrid)
	ymodew	t5, t5, zero
#endif

	/* Do not set tight bounds for functions for default setting -cheri-cap-table-abi=pcrel  */
	XREG_L	t4, (SZXREG * 4)(t0)	/* t4 <-- capreloc:capability_flags */
	li	t6, CAP_RELOC_CR_FLAG_FUNC
	and	t6, t6, t4
	bnez	t6, 4f

	/* Set bounds */
	XREG_L	t4, (SZXREG * 3)(t0)	/* t4 <-- capreloc:capability_length */
	beqz	t4, 4f		/* unlimited bounds if the capability_length is zero */
	ybndsrw	t5, t5, t4

4:	/* Set offset */
	XREG_L	t4, (SZXREG * 2)(t0)	/* t4 <-- capreloc:capability_offset */
	yadd	t5, t5, t4

5:	/* Set permission */
	XREG_L	t4, (SZXREG * 4)(t0)	/* t4 <-- capreloc:capability_flags */
	bnez	t4, 6f
	set_cap_perm	t5, t5, t6, CHERI_PERM_DATA	/* read-write data */
	j	9f
6:	li	t6, CAP_RELOC_CR_FLAG_CONST
	and	t6, t6, t4
	beqz	t6, 7f
	set_cap_perm	t5, t5, t6, CHERI_PERM_R_DATA	/* read only data */
	j	9f

7:	li	t6, CAP_RELOC_CR_FLAG_FUNC
	and	t6, t6, t4
	beqz	t6, 9f
	set_cap_perm	t5, t5, t6, CHERI_PERM_EXECUTABLE	/* function pointer */

	/* Seal entry */
	/* Only seal the function whcih is not used for exception handler */
	lly	t6, _start_hang
	beq		t5, t6, 9f
	ysentry	t5, t5
9:
	sy	t5, 0(t3)
10:
	yaddi	t0, t0, (SZXREG * 5)
	blt	t0, t1, 2b
_cheri_cap_init_done:
#endif /* defined(__CHERI__) */

	/* Zero-out BSS */
	PC_PTR_L	a4, _bss_start
	PC_PTR_L	a5, _bss_end
_bss_zero:
	PREG_S	zero, 0(a4)
	PREG_ADD	a4, a4, __SIZEOF_POINTER__
	blt	a4, a5, _bss_zero

_start_warm:
	/* Disable and clear all interrupts */
	csrw	CSR_SIE, zero
	csrw	CSR_SIP, zero

	/* Setup exception vectors */
	PTR_L	a3, _start_hang
	csrw	CSR_STVEC, a3

	/* Setup stack */
	PC_PTR_L	a3, _payload_end
	li	a4, 0x2000
#if defined(__CHERI__)
	PC_PTR_L	a5, cheri_infinite_cap
	PREG_L	a5, 0(a5)

	yaddrw	a3, a5, a3
	ybndsrw	a3, a3, a4
	set_cap_perm	a3, a3, a5, CHERI_PERM_STACK
#endif
	PREG_ADD	sp, a3, a4

	/* Jump to C main */
	PC_PTR_L	a3, _boot_a0
	REG_L	a0, 0(a3)
	PC_PTR_L	a3, _boot_a1
	REG_L	a1, 0(a3)
	call	test_main

	/* We don't expect to reach here hence just hang */
	j	_start_hang

	.section .entry, "ax", %progbits
	.align 3
	.globl _start_hang
	.type  _start_hang, @function
_start_hang:
	wfi
	j	_start_hang
	.size _start_hang, . - _start_hang

	.section .data
	.align	4
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
	.align 4
	.globl __stack_chk_guard
	.type __stack_chk_guard, %object
__stack_chk_guard:
	RISCV_PTR	0x95B5FF5A

#if defined(__CHERI__)
	.section .data
	.align 4
	.globl cheri_infinite_cap
	.type  cheri_infinite_cap, %object
cheri_infinite_cap:
	RISCV_PTR 0x0
	.size cheri_infinite_cap, . - cheri_infinite_cap
#endif
