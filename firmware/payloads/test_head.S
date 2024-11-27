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

	.section .entry, "ax", %progbits
	.align 3
	.globl _start
_start:
#if defined(__CHERI_PURE_CAPABILITY__)
#if defined(__riscv_zcherihybrid)
	/* Run test in capability pointer mode */
	modesw.cap
#endif
	/* Save infinite capability */
	auipc 	PREG(a2), 0
	PC_PTR_L	PREG(a3), cheri_infinite_cap
	PREG_S	PREG(a2), 0(PREG(a3))
#endif

	/* Pick one hart to run the main boot sequence */
	PC_PTR_L	PREG(a3), _hart_lottery
	li	a2, 1
	amoadd.w a3, a2, (PREG(a3))
	bnez	a3, _start_hang

	/* Save a0 and a1 */
	PC_PTR_L	PREG(a3), _boot_a0
	REG_S		REG(a0), 0(PREG(a3))
	PC_PTR_L	PREG(a3), _boot_a1
	REG_S		REG(a1), 0(PREG(a3))


#if defined(__CHERI_PURE_CAPABILITY__)
#if defined(FW_PAYLOAD_OFFSET)
	li		t0, (FW_TEXT_START+FW_PAYLOAD_OFFSET)	/* link start */
#else
	mv		t0, zero
#endif
	PC_PTR_L	PREG(t1), _payload_start	/* load start */
	sub		t2, t1, t0	/* load offset */

	PC_PTR_L	PREG(a3), cheri_infinite_cap
	PREG_L		PREG(a3), 0(PREG(a3))

cheri_cap_init:
	PC_PTR_L	PREG(t0), __cap_relocs_start
	PC_PTR_L	PREG(t1), __cap_relocs_end
	beq		t0, t1, _cheri_cap_init_done

2:	XREG_L	t3, 0(PREG(t0))	/* t3 <-- capreloc:capability_location */
	add	t3, t3, t2
	scaddr	PREG(t3), PREG(a3), t3 	/* t3 <-- W permission capability points to capability */
	XREG_L	t4, SZXREG(PREG(t0))	/* t4 <-- capreloc:capability_base */
	bnez	t4, 3f		/* write cnull if capreloc:capability_base is zero */

	j	10f		/* Initialize next capability */

3:	/* Set address/base */
	add	t4, t4, t2
	scaddr	PREG(t5), PREG(a3), t4	/* t5 <-- Set base from a Infinite capability */

#if defined(__riscv_zcherihybrid)
	/* Set M-bit for all capability as purecap mode */
	scmode	PREG(t5), PREG(t5), zero
#endif /* defined(__riscv_zcherihybrid) */

	/* Do not set tight bounds for functions for default setting -cheri-cap-table-abi=pcrel  */
	XREG_L	t4, (SZXREG * 4)(PREG(t0))	/* t4 <-- capreloc:capability_flags */
	li	t6, CAP_RELOC_CR_FLAG_FUNC
	and	t6, t6, t4
	bnez	t6, 4f

	/* Set bounds */
	XREG_L	t4, (SZXREG * 3)(PREG(t0))	/* t4 <-- capreloc:capability_length */
	beqz	t4, 4f		/* unlimited bounds if the capability_length is zero */
	scbndsr	PREG(t5), PREG(t5), t4

4:	/* Set offset */
	XREG_L	t4, (SZXREG * 2)(PREG(t0))	/* t4 <-- capreloc:capability_offset */
	add	PREG(t5), PREG(t5), t4

5:	/* Set permission */
	XREG_L	t4, (SZXREG * 4)(PREG(t0))	/* t4 <-- capreloc:capability_flags */
	bnez	t4, 6f
	li t6,	CHERI_PERM_DATA		/* read-write data */
	acperm	PREG(t5), PREG(t5), t6
	j	9f
6:	li	t6, CAP_RELOC_CR_FLAG_CONST
	and	t6, t6, t4
	beqz	t6, 7f
	li t6,	CHERI_PERM_R_DATA	/* read only data */
	acperm	PREG(t5), PREG(t5), t6
	j	9f

7:	li	t6, CAP_RELOC_CR_FLAG_FUNC
	and	t6, t6, t4
	beqz	t6, 9f
	li t6,	CHERI_PERM_EXECUTABLE	/* function pointer */
	acperm	PREG(t5), PREG(t5), t6

	/* Seal entry */
	/* Only seal the function whcih is not used for exception handler */
	PC_PTR_L	PREG(t6), _start_hang
	beq		t5, t6, 9f
	sentry	PREG(t5), PREG(t5)
9:
	PREG_S	PREG(t5), 0(PREG(t3))
10:
	add	PREG(t0), PREG(t0), (SZXREG * 5)
	blt	t0, t1, 2b
_cheri_cap_init_done:
#endif /* !defined(__CHERI_PURE_CAPABILITY__) */

	/* Zero-out BSS */
	PC_PTR_L	PREG(a4), _bss_start
	PC_PTR_L	PREG(a5), _bss_end
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
	PC_PTR_L	PREG(a3), _payload_end
	li	a4, 0x2000
#if defined(__CHERI_PURE_CAPABILITY__)
	PC_PTR_L	PREG(a5), cheri_infinite_cap
	PREG_L	PREG(a5), 0(PREG(a5))

	scaddr	PREG(a3), PREG(a5), a3
	scbndsr	PREG(a3), PREG(a3), a4
	li a5,	CHERI_PERM_STACK
	acperm	PREG(a3), PREG(a3), a5
#endif
	add	PREG(sp), PREG(a3), a4

	/* Jump to C main */
	PC_PTR_L	PREG(a3), _boot_a0
	REG_L	REG(a0), 0(PREG(a3))
	PC_PTR_L	PREG(a3), _boot_a1
	REG_L	REG(a1), 0(PREG(a3))
#if defined(__CHERI_PURE_CAPABILITY__)
	PTR_L	PREG(ra), test_main
	jalr	PREG(ra)
#else
	call	test_main
#endif

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
	.align	3
_hart_lottery:
	RISCV_PTR	0
_boot_a0:
	RISCV_PTR	0
_boot_a1:
	RISCV_PTR	0

#if defined(__CHERI_PURE_CAPABILITY__)
	.section .data
	.align 4
	.globl cheri_infinite_cap
	.type  cheri_infinite_cap, @object
cheri_infinite_cap:
	RISCV_PTR 0x0
	.size cheri_infinite_cap, . - cheri_infinite_cap
#endif
