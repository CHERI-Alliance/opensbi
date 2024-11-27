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
#include <sbi/riscv_encoding.h>
#include <sbi/riscv_elf.h>
#include <sbi/sbi_platform.h>
#include <sbi/sbi_scratch.h>
#include <sbi/sbi_trap.h>

#define BOOT_STATUS_LOTTERY_DONE	1
#define BOOT_STATUS_BOOT_HART_DONE	2

.macro	MOV_3R __d0, __s0, __d1, __s1, __d2, __s2
	mv	\__d0, \__s0
	mv	\__d1, \__s1
	mv	\__d2, \__s2
.endm

.macro	MOV_5R __d0, __s0, __d1, __s1, __d2, __s2, __d3, __s3, __d4, __s4
	mv	\__d0, \__s0
	mv	\__d1, \__s1
	mv	\__d2, \__s2
	mv	\__d3, \__s3
	mv	\__d4, \__s4
.endm

	.section .entry, "ax", %progbits
	.align 3
	.globl _start
	.globl _start_warm
	.type  _start_warm, @function
_start:
#if defined(__riscv_zcherihybrid)
	/* Enable the capability instruction even it's not in purecap mode */
	/* as the compiler may use the capability instruction to optimize  */
	/* the code when -march=zcherihybrid.                              */
	csrs CSR_MSECCFG, MSECCFG_CRE

#if defined(__CHERI_PURE_CAPABILITY__)
	modesw.cap
#endif /* defined(__CHERI_PURE_CAPABILITY__) */
#endif /* defined(__riscv_zcherihybrid) */

#if defined(__CHERI_PURE_CAPABILITY__)
	/* Initialize the ca3 as infinite capability */
	auipc 	PREG(a3), 0
#if defined(__riscv_zcherihybrid)
	/* Set default infinite capability in integer pointer mode */
	/* and the offset to zero.                                 */
	scaddr	PREG(a3), PREG(a3), zero
	li	t0, 1
	scmode	PREG(a3), PREG(a3), t0
#endif
	PC_PTR_L	PREG(t0), cheri_infinite_cap
	PREG_S		PREG(a3), 0(PREG(t0))

	/* Convert FDT pointer from integer to capability */
	scaddr	PREG(a1), PREG(a3), a1
	scaddr	PREG(a2), PREG(a3), a2
#endif

	/* Find preferred boot HART id */
	MOV_3R	REG(s0), REG(a0), REG(s1), REG(a1), REG(s2), REG(a2)
	call	fw_boot_hart
	mv	a6, a0
	MOV_3R	REG(a0), REG(s0), REG(a1), REG(s1), REG(a2), REG(s2)
	li	a7, -1
	beq	a6, a7, _try_lottery
	/* Jump to relocation wait loop if we are not boot hart */
	bne	a0, a6, _wait_for_boot_hart
_try_lottery:
	/* Jump to relocation wait loop if we don't get relocation lottery */
	PC_PTR_L	PREG(a6), _boot_status
	li	a7, BOOT_STATUS_LOTTERY_DONE
	amoswap.w a6, a7, (PREG(a6))
	bnez	a6, _wait_for_boot_hart

	/* relocate the global table content */
	li	t0, FW_TEXT_START	/* link start */
	PC_PTR_L	PREG(t1), _fw_start	/* load start */
	sub	t2, t1, t0		/* load offset */
#if defined(__CHERI_PURE_CAPABILITY__)
	/* initialize cap table before executing c functions */
cheri_cap_init:
	PC_PTR_L	PREG(t0), __cap_relocs_start
	PC_PTR_L	PREG(t1), __cap_relocs_end
	beq		t0, t1, _relocate_done

2:	XREG_L	t3, 0(PREG(t0))	/* t3 <-- capreloc:capability_location */
	add	t3, t3, t2
	scaddr	PREG(t3), PREG(a3), t3 	/* t3 <-- W permission capability points to capability */
	XREG_L	t4, SZXREG(PREG(t0))	/* t4 <-- capreloc:capability_base */
	bnez	t4, 3f		/* write cnull if capreloc:capability_base is zero */
	j	10f		/* Initialize next capability */

3:	/* Set address/base */
	add	t4, t4, t2
	scaddr	PREG(t5), PREG(a3), t4 	/* t5 <-- Set base from a Infinite capability */

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
	beqz	t4,	4f		/* unlimited bounds if the capability_length is zero */
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
	PC_PTR_L	PREG(t6), __sbi_expected_trap
	beq		t5, t6, 9f
	PC_PTR_L	PREG(t6), __sbi_expected_trap_hext
	beq		t5, t6, 9f
	PC_PTR_L	PREG(t6), _trap_handler
	beq		t5, t6, 9f
	PC_PTR_L	PREG(t6), _trap_handler_hyp
	beq		t5, t6, 9f
	sentry	PREG(t5), PREG(t5)
9:
	PREG_S	PREG(t5), 0(PREG(t3))
10:
	add	PREG(t0), PREG(t0), (SZXREG * 5)
	blt	t0, t1, 2b
#else /* !defined(__CHERI_PURE_CAPABILITY__) */
	PC_PTR_L	PREG(t0), __rel_dyn_start
	PC_PTR_L	PREG(t1), __rel_dyn_end
	beq	t0, t1, _relocate_done
2:
	XREG_L	t5, SZXREG(PREG(t0))	/* t5 <-- relocation info:type */
	li	t3, R_RISCV_RELATIVE	/* reloc type R_RISCV_RELATIVE */
	bne	t5, t3, 3f
	PREG_L	PREG(t3), 0(PREG(t0))
	PREG_L	PREG(t5), (SZXREG * 2)(PREG(t0))	/* t5 <-- addend */
	add	PREG(t5), PREG(t5), t2
	add	PREG(t3), PREG(t3), t2
	PREG_S	PREG(t5), 0(PREG(t3))		/* store runtime address to the GOT entry */

3:
	add	PREG(t0), PREG(t0), (REGBYTES * 3)
	blt	t0, t1, 2b
#endif /* !defined(__CHERI_PURE_CAPABILITY__) */
_relocate_done:
	/* At this point we are running from link address */

	/* Reset all registers except ra, a0, a1, a2, a3 and a4 for boot HART */
	li	ra, 0
	call	_reset_regs

	/* Zero-out BSS */
	PC_PTR_L	PREG(s4), _bss_start
	PC_PTR_L	PREG(s5), _bss_end
_bss_zero:
	REG_S	REG_ZERO, (PREG(s4))
	add	PREG(s4), PREG(s4), SZREG
	blt	s4, s5, _bss_zero

	/* Setup temporary trap handler */
	PC_PTR_L	PREG(s4), _start_hang
	csrw	CSR_MTVEC, PREG(s4)

	/* Setup temporary stack */
	PC_PTR_L	PREG(s4), _fw_end
	li	s5, (SBI_SCRATCH_SIZE * 2)
#if defined(__CHERI_PURE_CAPABILITY__)
	scaddr	PREG(s4), PREG(a3), s4
	scbndsr	PREG(s4), PREG(s4), s5
	li t0,	CHERI_PERM_STACK
	acperm	PREG(s4), PREG(s4), t0
#endif
	add	PREG(sp), PREG(s4), s5

	/* Allow main firmware to save info */
	MOV_5R	REG(s0), REG(a0), REG(s1), REG(a1), REG(s2), REG(a2), REG(s3), REG(a3), REG(s4), REG(a4)
	call	fw_save_info
	MOV_5R	REG(a0), REG(s0), REG(a1), REG(s1), REG(a2), REG(s2), REG(a3), REG(s3), REG(a4), REG(s4)

#ifdef FW_FDT_PATH
	/* Override previous arg1 */
	PTR_L	PREG(a1), fw_fdt_bin
#endif

	/*
	 * Initialize platform
	 * Note: The a0 to a4 registers passed to the
	 * firmware are parameters to this function.
	 */
	MOV_5R	REG(s0), REG(a0), REG(s1), REG(a1), REG(s2), REG(a2), REG(s3), REG(a3), REG(s4), REG(a4)
	call	fw_platform_init
	mv	REG(t0), REG(a0)
	MOV_5R	REG(a0), REG(s0), REG(a1), REG(s1), REG(a2), REG(s2), REG(a3), REG(s3), REG(a4), REG(s4)
	mv	REG(a1), REG(t0)

	/* Preload HART details
	 * s7 -> HART Count
	 * s8 -> HART Stack Size
	 * s9 -> Heap Size
	 * s10 -> Heap Offset
	 */
	PTR_L	PREG(a4), platform
#if __riscv_xlen > 32
	lwu	s7, SBI_PLATFORM_HART_COUNT_OFFSET(PREG(a4))
	lwu	s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(PREG(a4))
	lwu	s9, SBI_PLATFORM_HEAP_SIZE_OFFSET(PREG(a4))
#else
	lw	s7, SBI_PLATFORM_HART_COUNT_OFFSET(PREG(a4))
	lw	s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(PREG(a4))
	lw	s9, SBI_PLATFORM_HEAP_SIZE_OFFSET(PREG(a4))
#endif

	/* Setup scratch space for all the HARTs*/
	PC_PTR_L	PREG(tp), _fw_end
	mul	a5, s7, s8
	add	PREG(tp), PREG(tp), a5
	/* Setup heap base address */
	PC_PTR_L	PREG(s10), _fw_start
	sub	s10, tp, s10
	add	PREG(tp), PREG(tp), s9
	/* Keep a copy of tp */
	mv	PREG(t3), PREG(tp)
	/* Counter */
	li	t2, 1
	/* hartid 0 is mandated by ISA */
	li	t1, 0
_scratch_init:
	/*
	 * The following registers hold values that are computed before
	 * entering this block, and should remain unchanged.
	 *
	 * t3 -> the firmware end address
	 * s7 -> HART count
	 * s8 -> HART stack size
	 * s9 -> Heap Size
	 * s10 -> Heap Offset
	 */
	mv	PREG(tp), PREG(t3)
	sub	tp, tp, s9
	mul	a5, s8, t1
	sub	tp, tp, a5
	li	a5, SBI_SCRATCH_SIZE
	sub	tp, tp, a5
#if defined(__CHERI_PURE_CAPABILITY__)
	scaddr	PREG(tp), PREG(t3), tp	/* Initialize tp with the stored tp */
	scbndsr PREG(tp), PREG(tp), a5	/* scratch bounds is SBI_SCRATCH_SIZE */
	li t0,	CHERI_PERM_DATA	/* scratch is a read-write data */
	acperm	PREG(tp), PREG(tp), t0

	/*
	 * Setup per hart stack for CHERI. Since CHERI capability stack pointer
	 * is not same as scratch pad pointer as the bonds are different. It needs
	 * another scratch field to store the stack pointer for CHERI.
	 */
	sub	a4, s8, a5	/* a4 <-- stack size (HART_STACK_SIZE - SBI_SCRATCH_SIZE) */
	sub	a5, tp, a4	/* a5 <-- sp base */
	scaddr	PREG(a5), PREG(a3), a5	/* Initialize a4 with infinite cap */
	scbndsr PREG(a5), PREG(a5), a4	/* sp bounds is stack size */
	acperm	PREG(a5), PREG(a5), t0	/* sp is a read-write data */
	add	PREG(a5), PREG(a5), a4	/* Set a5 to sp top */
	PREG_S	PREG(a5), SBI_SCRATCH_STACK_OFFSET(PREG(tp))
#endif

	/* Initialize scratch space */
	/* Store fw_start and fw_size in scratch space */
	PC_PTR_L	PREG(a4), _fw_start
	sub	a5, t3, a4
	XREG_S	a4, SBI_SCRATCH_FW_START_OFFSET(PREG(tp))
	XREG_S	a5, SBI_SCRATCH_FW_SIZE_OFFSET(PREG(tp))

	/* Store R/W section's offset in scratch space */
	PC_PTR_L	PREG(a5), _fw_rw_start
	sub	a5, a5, a4
	XREG_S	a5, SBI_SCRATCH_FW_RW_OFFSET(PREG(tp))

	/* Store fw_heap_offset and fw_heap_size in scratch space */
	XREG_S	s10, SBI_SCRATCH_FW_HEAP_OFFSET(PREG(tp))
	XREG_S	s9, SBI_SCRATCH_FW_HEAP_SIZE_OFFSET(PREG(tp))

	/* Store next arg1 in scratch space */
	MOV_3R	REG(s0), REG(a0), REG(s1), REG(a1), REG(s2), REG(a2)
	call	fw_next_arg1
	PREG_S	PREG(a0), SBI_SCRATCH_NEXT_ARG1_OFFSET(PREG(tp))
	MOV_3R	REG(a0), REG(s0), REG(a1), REG(s1), REG(a2), REG(s2)
	/* Store next address in scratch space */
	MOV_3R	REG(s0), REG(a0), REG(s1), REG(a1), REG(s2), REG(a2)
	call	fw_next_addr
	PREG_S	PREG(a0), SBI_SCRATCH_NEXT_ADDR_OFFSET(PREG(tp))
	MOV_3R	REG(a0), REG(s0), REG(a1), REG(s1), REG(a2), REG(s2)
	/* Store next mode in scratch space */
	MOV_3R	REG(s0), REG(a0), REG(s1), REG(a1), REG(s2), REG(a2)
	call	fw_next_mode
	XREG_S	a0, SBI_SCRATCH_NEXT_MODE_OFFSET(PREG(tp))
	MOV_3R	REG(a0), REG(s0), REG(a1), REG(s1), REG(a2), REG(s2)
	/* Store warm_boot address in scratch space */
	PTR_L	PREG(a4), _start_warm
	PREG_S	PREG(a4), SBI_SCRATCH_WARMBOOT_ADDR_OFFSET(PREG(tp))
	/* Store platform address in scratch space */
	PTR_L	PREG(a4), platform
	PREG_S	PREG(a4), SBI_SCRATCH_PLATFORM_ADDR_OFFSET(PREG(tp))
	/* Store hartid-to-scratch function address in scratch space */
	PTR_L	PREG(a4), _hartid_to_scratch
	PREG_S	PREG(a4), SBI_SCRATCH_HARTID_TO_SCRATCH_OFFSET(PREG(tp))
	/* Clear trap_context and tmp0 in scratch space */
	PREG_S	PREG_NULL, SBI_SCRATCH_TRAP_CONTEXT_OFFSET(PREG(tp))
	PREG_S	PREG_NULL, SBI_SCRATCH_TMP0_OFFSET(PREG(tp))
	/* Store firmware options in scratch space */
	MOV_3R	REG(s0), REG(a0), REG(s1), REG(a1), REG(s2), REG(a2)
#ifdef FW_OPTIONS
	li	a0, FW_OPTIONS
#else
	call	fw_options
#endif
	XREG_S	a0, SBI_SCRATCH_OPTIONS_OFFSET(PREG(tp))
	MOV_3R	REG(a0), REG(s0), REG(a1), REG(s1), REG(a2), REG(s2)
	/* Move to next scratch space */
	add	t1, t1, t2
	blt	t1, s7, _scratch_init

	/*
	 * Relocate Flatened Device Tree (FDT)
	 * source FDT address = previous arg1
	 * destination FDT address = next arg1
	 *
	 * Note: We will preserve a0 and a1 passed by
	 * previous booting stage.
	 */
	beqz	a1, _fdt_reloc_done
	/* Mask values in a4 */
	li	a4, 0xff
	/* t1 = destination FDT start address */
	MOV_3R	REG(s0), REG(a0), REG(s1), REG(a1), REG(s2), REG(a2)
	call	fw_next_arg1
	mv	PREG(t1), PREG(a0)
	MOV_3R	REG(a0), REG(s0), REG(a1), REG(s1), REG(a2), REG(s2)
	beqz	t1, _fdt_reloc_done
	beq	t1, a1, _fdt_reloc_done
	/* t0 = source FDT start address */
	mv	PREG(t0), PREG(a1)
	/* t2 = source FDT size in big-endian */
#if __riscv_xlen > 32
	lwu	t2, 4(PREG(t0))
#else
	lw	t2, 4(PREG(t0))
#endif
	/* t3 = bit[15:8] of FDT size */
	mv	t3, t2
	srli	t3, t3, 16
	and	t3, t3, a4
	slli	t3, t3, 8
	/* t4 = bit[23:16] of FDT size */
	mv	t4, t2
	srli	t4, t4, 8
	and	t4, t4, a4
	slli	t4, t4, 16
	/* t5 = bit[31:24] of FDT size */
	mv	t5, t2
	and	t5, t5, a4
	slli	t5, t5, 24
	/* t2 = bit[7:0] of FDT size */
	srli	t2, t2, 24
	and	t2, t2, a4
	/* t2 = FDT size in little-endian */
	or	t2, t2, t3
	or	t2, t2, t4
	or	t2, t2, t5
	/* t2 = destination FDT end address */
	add	t2, t1, t2
	/* FDT copy loop */
	ble	t2, t1, _fdt_reloc_done
_fdt_reloc_again:
	XREG_L	t3, 0(PREG(t0))
	XREG_S	t3, 0(PREG(t1))
	add	PREG(t0), PREG(t0), SZXREG
	add	PREG(t1), PREG(t1), SZXREG
	blt	t1, t2, _fdt_reloc_again
_fdt_reloc_done:

	/* mark boot hart done */
	li	t0, BOOT_STATUS_BOOT_HART_DONE
	PTR_L	PREG(t1), _boot_status
	fence	rw, rw
	XREG_S	t0, 0(PREG(t1))
	j	_start_warm

	/* waiting for boot hart to be done (_boot_status == 2) */
_wait_for_boot_hart:
	li	t0, BOOT_STATUS_BOOT_HART_DONE
	PC_PTR_L	PREG(t1), _boot_status
	XREG_L	t1, 0(PREG(t1))
	/* Reduce the bus traffic so that boot hart may proceed faster */
	div	t2, t2, zero
	div	t2, t2, zero
	div	t2, t2, zero
	bne	t0, t1, _wait_for_boot_hart

_start_warm:
	/* Reset all registers except ra, a0, a1, a2, a3 and a4 for non-boot HART */
	li	ra, 0
	call	_reset_regs

	/* Disable all interrupts */
	csrw	CSR_MIE, zero

	/* Find HART count and HART stack size */
	PTR_L	PREG(a4), platform
#if __riscv_xlen > 32
	lwu	s7, SBI_PLATFORM_HART_COUNT_OFFSET(PREG(a4))
	lwu	s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(PREG(a4))
#else
	lw	s7, SBI_PLATFORM_HART_COUNT_OFFSET(PREG(a4))
	lw	s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(PREG(a4))
#endif
	REG_L	PREG(s9), SBI_PLATFORM_HART_INDEX2ID_OFFSET(PREG(a4))

	/* Find HART id */
	csrr	s6, CSR_MHARTID

	/* Find HART index */
	beqz	s9, 3f
	li	a4, 0
1:
#if __riscv_xlen > 32
	lwu	a5, (PREG(s9))
#else
	lw	a5, (PREG(s9))
#endif
	beq	a5, s6, 2f
	add	PREG(s9), PREG(s9), 4
	add	a4, a4, 1
	blt	a4, s7, 1b
2:	add	s6, a4, zero
3:	bge	s6, s7, _start_hang

	/* Find the scratch space based on HART index */
	PC_PTR_L	PREG(tp), _fw_end
	mul	a5, s7, s8
	add	tp, tp, a5
	mul	a5, s8, s6
	sub	tp, tp, a5
	li	a5, SBI_SCRATCH_SIZE
	sub	tp, tp, a5
#if defined(__CHERI_PURE_CAPABILITY__)
	PC_PTR_L	PREG(t0), cheri_infinite_cap
	PREG_L	PREG(t1), 0(PREG(t0))
	scaddr	PREG(tp), PREG(t1), tp		/* Initialize tp with infinite cap */
	scbndsr PREG(tp), PREG(tp), a5		/* scratch bounds is SBI_SCRATCH_SIZE */
	li t0,	CHERI_PERM_DATA		/* scratch is a read-write data */
	acperm	PREG(tp), PREG(tp), t0
#endif
	/* update the mscratch */
	csrw	CSR_MSCRATCH, PREG(tp)

	/* Setup stack */
#if defined(__CHERI_PURE_CAPABILITY__)
	sub	a5, s8, a5	/* a5 <-- stack size (HART_STACK_SIZE - SBI_SCRATCH_SIZE) */
	sub	sp, tp, a5	/* Get sp base */
	scaddr	PREG(sp), PREG(t1), sp		/* Initialize sp with infinite cap */
	scbndsr PREG(sp), PREG(sp), a5		/* sp bounds is stack size */
	acperm	PREG(sp), PREG(sp), t0		/* sp is a read-write data */
	add	PREG(sp), PREG(sp), a5		/* Set sp to sp top */
#else
	add	PREG(sp), PREG(tp), zero
#endif

	/* Setup trap handler */
	PTR_L	PREG(a4), _trap_handler
	csrr	a5, CSR_MISA
	srli	a5, a5, ('H' - 'A')
	andi	a5, a5, 0x1
	beq	a5, zero, _skip_trap_handler_hyp
	PTR_L	PREG(a4), _trap_handler_hyp
_skip_trap_handler_hyp:
	csrw	CSR_MTVEC, PREG(a4)

	/* Initialize SBI runtime */
	csrr	PREG(a0), CSR_MSCRATCH
#if defined(__CHERI_PURE_CAPABILITY__)
	PTR_L	PREG(ra), sbi_init
	jalr	PREG(ra)
#else
	call	sbi_init
#endif

	/* We don't expect to reach here hence just hang */
	j	_start_hang
	.size _start_warm, . - _start_warm

	.data
	.align 3
	.type  _boot_status, @object
_boot_status:
	RISCV_LONG	0
	.size _boot_status, . - _boot_status

	.section .entry, "ax", %progbits
	.align 3
	.globl _hartid_to_scratch
	.type  _hartid_to_scratch, @function
_hartid_to_scratch:
	/*
	 * a0 -> HART ID (passed by caller)
	 * a1 -> HART Index (passed by caller)
	 * t0 -> HART Stack Size
	 * t1 -> HART Stack End
	 * t2 -> Temporary
	 */
	PTR_L	PREG(t2), platform
#if __riscv_xlen > 32
	lwu	t0, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(PREG(t2))
	lwu	t2, SBI_PLATFORM_HART_COUNT_OFFSET(PREG(t2))
#else
	lw	t0, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(PREG(t2))
	lw	t2, SBI_PLATFORM_HART_COUNT_OFFSET(PREG(t2))
#endif
	sub	t2, t2, a1
	mul	t2, t2, t0
	PC_PTR_L	PREG(t1), _fw_end
	add	t1, t1, t2
	li	t2, SBI_SCRATCH_SIZE
	sub	a0, t1, t2
#if defined(__CHERI_PURE_CAPABILITY__)
	PC_PTR_L	PREG(t0), cheri_infinite_cap
	PREG_L	PREG(t1), 0(PREG(t0))
	scaddr	PREG(a0), PREG(t1), a0
	scbndsr PREG(a0), PREG(a0), t2	/* scratch bounds is SBI_SCRATCH_SIZE */
	li t0,	CHERI_PERM_DATA		/* scratch is a read-write data */
	acperm	PREG(a0), PREG(a0), t0
#endif
	ret
	.size _hartid_to_scratch, . - _hartid_to_scratch

	.section .entry, "ax", %progbits
	.align 3
	.globl _start_hang
_start_hang:
	wfi
	j	_start_hang

	.section .entry, "ax", %progbits
	.align 3
	.weak fw_platform_init
fw_platform_init:
	mv	PREG(a0), PREG(a1)
	ret

	/* Map implicit memcpy() added by compiler to sbi_memcpy() */
	.section .text
	.align 3
	.globl memcpy
memcpy:
	tail	sbi_memcpy

	/* Map implicit memset() added by compiler to sbi_memset() */
	.section .text
	.align 3
	.globl memset
memset:
	tail	sbi_memset

	/* Map implicit memmove() added by compiler to sbi_memmove() */
	.section .text
	.align 3
	.globl memmove
memmove:
	tail	sbi_memmove

	/* Map implicit memcmp() added by compiler to sbi_memcmp() */
	.section .text
	.align 3
	.globl memcmp
memcmp:
	tail	sbi_memcmp

.macro	TRAP_SAVE_AND_SETUP_SP_T0
	/* Swap TP and MSCRATCH */
	csrrw	PREG(tp), CSR_MSCRATCH, PREG(tp)

	/* Save T0 in scratch space */
	REG_S	REG(t0), SBI_SCRATCH_TMP0_OFFSET(PREG(tp))

	/*
	 * Set T0 to appropriate exception stack
	 *
	 * Came_From_M_Mode = ((MSTATUS.MPP < PRV_M) ? 1 : 0) - 1;
	 * Exception_Stack = TP ^ (Came_From_M_Mode & (SP ^ TP))
	 *
	 * Came_From_M_Mode = 0    ==>    Exception_Stack = TP
	 * Came_From_M_Mode = -1   ==>    Exception_Stack = SP
	 */
	csrr	t0, CSR_MSTATUS
	srl	t0, t0, MSTATUS_MPP_SHIFT
	and	t0, t0, PRV_M
	slti	t0, t0, PRV_M
#if defined(__CHERI_PURE_CAPABILITY__)
	beqz	t0, 1f
	PREG_L	PREG(t0), SBI_SCRATCH_STACK_OFFSET(PREG(tp))
	j 2f
1:
	mv	PREG(t0), PREG(sp)
2:
#else /* !defined(__CHERI_PURE_CAPABILITY__) */
	add	t0, t0, -1
	xor	sp, sp, tp
	and	t0, t0, sp
	xor	sp, sp, tp
	xor	t0, tp, t0
#endif /* !defined(__CHERI_PURE_CAPABILITY__) */

	/* Save original SP on exception stack */
	PREG_S	PREG(sp), (SBI_TRAP_REGS_OFFSET(sp) - SBI_TRAP_CONTEXT_SIZE)(PREG(t0))

	/* Set SP to exception stack and make room for trap context */
	add	PREG(sp), PREG(t0), -(SBI_TRAP_CONTEXT_SIZE)

	/* Restore T0 from scratch space */
	REG_L	REG(t0), SBI_SCRATCH_TMP0_OFFSET(PREG(tp))

	/* Save T0 on stack */
	REG_S	REG(t0), SBI_TRAP_REGS_OFFSET(t0)(PREG(sp))

	/* Swap TP and MSCRATCH */
	csrrw	PREG(tp), CSR_MSCRATCH, PREG(tp)
.endm

.macro	TRAP_SAVE_MEPC_MSTATUS have_mstatush
	/* Save MEPC and MSTATUS CSRs */
	csrr	PREG(t0), CSR_MEPC
	PREG_S	PREG(t0), SBI_TRAP_REGS_OFFSET(mepc)(PREG(sp))
	csrr	t0, CSR_MSTATUS
	REG_S	REG(t0), SBI_TRAP_REGS_OFFSET(mstatus)(PREG(sp))
	.if \have_mstatush
	csrr	t0, CSR_MSTATUSH
	REG_S	REG(t0), SBI_TRAP_REGS_OFFSET(mstatusH)(PREG(sp))
	.else
	REG_S	REG_ZERO, SBI_TRAP_REGS_OFFSET(mstatusH)(PREG(sp))
	.endif
.endm

.macro	TRAP_SAVE_GENERAL_REGS_EXCEPT_SP_T0
	/* Save all general regisers except SP and T0 */
	REG_S	REG_ZERO, SBI_TRAP_REGS_OFFSET(zero)(PREG(sp))
	REG_S	REG(ra), SBI_TRAP_REGS_OFFSET(ra)(PREG(sp))
	REG_S	REG(gp), SBI_TRAP_REGS_OFFSET(gp)(PREG(sp))
	REG_S	REG(tp), SBI_TRAP_REGS_OFFSET(tp)(PREG(sp))
	REG_S	REG(t1), SBI_TRAP_REGS_OFFSET(t1)(PREG(sp))
	REG_S	REG(t2), SBI_TRAP_REGS_OFFSET(t2)(PREG(sp))
	REG_S	REG(s0), SBI_TRAP_REGS_OFFSET(s0)(PREG(sp))
	REG_S	REG(s1), SBI_TRAP_REGS_OFFSET(s1)(PREG(sp))
	REG_S	REG(a0), SBI_TRAP_REGS_OFFSET(a0)(PREG(sp))
	REG_S	REG(a1), SBI_TRAP_REGS_OFFSET(a1)(PREG(sp))
	REG_S	REG(a2), SBI_TRAP_REGS_OFFSET(a2)(PREG(sp))
	REG_S	REG(a3), SBI_TRAP_REGS_OFFSET(a3)(PREG(sp))
	REG_S	REG(a4), SBI_TRAP_REGS_OFFSET(a4)(PREG(sp))
	REG_S	REG(a5), SBI_TRAP_REGS_OFFSET(a5)(PREG(sp))
	REG_S	REG(a6), SBI_TRAP_REGS_OFFSET(a6)(PREG(sp))
	REG_S	REG(a7), SBI_TRAP_REGS_OFFSET(a7)(PREG(sp))
	REG_S	REG(s2), SBI_TRAP_REGS_OFFSET(s2)(PREG(sp))
	REG_S	REG(s3), SBI_TRAP_REGS_OFFSET(s3)(PREG(sp))
	REG_S	REG(s4), SBI_TRAP_REGS_OFFSET(s4)(PREG(sp))
	REG_S	REG(s5), SBI_TRAP_REGS_OFFSET(s5)(PREG(sp))
	REG_S	REG(s6), SBI_TRAP_REGS_OFFSET(s6)(PREG(sp))
	REG_S	REG(s7), SBI_TRAP_REGS_OFFSET(s7)(PREG(sp))
	REG_S	REG(s8), SBI_TRAP_REGS_OFFSET(s8)(PREG(sp))
	REG_S	REG(s9), SBI_TRAP_REGS_OFFSET(s9)(PREG(sp))
	REG_S	REG(s10), SBI_TRAP_REGS_OFFSET(s10)(PREG(sp))
	REG_S	REG(s11), SBI_TRAP_REGS_OFFSET(s11)(PREG(sp))
	REG_S	REG(t3), SBI_TRAP_REGS_OFFSET(t3)(PREG(sp))
	REG_S	REG(t4), SBI_TRAP_REGS_OFFSET(t4)(PREG(sp))
	REG_S	REG(t5), SBI_TRAP_REGS_OFFSET(t5)(PREG(sp))
	REG_S	REG(t6), SBI_TRAP_REGS_OFFSET(t6)(PREG(sp))
.endm

.macro	TRAP_SAVE_INFO have_mstatush have_h_extension
	csrr	t0, CSR_MCAUSE
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(cause))(PREG(sp))
	csrr	t0, CSR_MTVAL
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tval))(PREG(sp))
.if \have_h_extension
	csrr	t0, CSR_MTVAL2
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tval2))(PREG(sp))
	csrr	t0, CSR_MTINST
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tinst))(PREG(sp))
	.if \have_mstatush
	csrr	t0, CSR_MSTATUSH
	srli	t0, t0, MSTATUSH_GVA_SHIFT
	.else
	csrr	t0, CSR_MSTATUS
	srli	t0, t0, MSTATUS_GVA_SHIFT
	.endif
	and	t0, t0, 0x1
.else
#if defined(__CHERI_PURE_CAPABILITY__)
	csrr	t0, CSR_MTVAL2
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tval2))(PREG(sp))
#else
	XREG_S	zero, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tval2))(PREG(sp))
#endif
	XREG_S	zero, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tinst))(PREG(sp))
	li	t0, 0
.endif
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(gva))(PREG(sp))
.endm

.macro	TRAP_CALL_C_ROUTINE
	/* Call C routine */
	mv	PREG(a0), PREG(sp)
#if defined(__CHERI_PURE_CAPABILITY__)
	PTR_L	PREG(ra), sbi_trap_handler
	jalr	PREG(ra)
#else
	call	sbi_trap_handler
#endif
.endm

.macro	TRAP_RESTORE_GENERAL_REGS_EXCEPT_A0_T0
	/* Restore all general regisers except A0 and T0 */
	REG_L	REG(ra), SBI_TRAP_REGS_OFFSET(ra)(PREG(a0))
	REG_L	REG(sp), SBI_TRAP_REGS_OFFSET(sp)(PREG(a0))
	REG_L	REG(gp), SBI_TRAP_REGS_OFFSET(gp)(PREG(a0))
	REG_L	REG(tp), SBI_TRAP_REGS_OFFSET(tp)(PREG(a0))
	REG_L	REG(t1), SBI_TRAP_REGS_OFFSET(t1)(PREG(a0))
	REG_L	REG(t2), SBI_TRAP_REGS_OFFSET(t2)(PREG(a0))
	REG_L	REG(s0), SBI_TRAP_REGS_OFFSET(s0)(PREG(a0))
	REG_L	REG(s1), SBI_TRAP_REGS_OFFSET(s1)(PREG(a0))
	REG_L	REG(a1), SBI_TRAP_REGS_OFFSET(a1)(PREG(a0))
	REG_L	REG(a2), SBI_TRAP_REGS_OFFSET(a2)(PREG(a0))
	REG_L	REG(a3), SBI_TRAP_REGS_OFFSET(a3)(PREG(a0))
	REG_L	REG(a4), SBI_TRAP_REGS_OFFSET(a4)(PREG(a0))
	REG_L	REG(a5), SBI_TRAP_REGS_OFFSET(a5)(PREG(a0))
	REG_L	REG(a6), SBI_TRAP_REGS_OFFSET(a6)(PREG(a0))
	REG_L	REG(a7), SBI_TRAP_REGS_OFFSET(a7)(PREG(a0))
	REG_L	REG(s2), SBI_TRAP_REGS_OFFSET(s2)(PREG(a0))
	REG_L	REG(s3), SBI_TRAP_REGS_OFFSET(s3)(PREG(a0))
	REG_L	REG(s4), SBI_TRAP_REGS_OFFSET(s4)(PREG(a0))
	REG_L	REG(s5), SBI_TRAP_REGS_OFFSET(s5)(PREG(a0))
	REG_L	REG(s6), SBI_TRAP_REGS_OFFSET(s6)(PREG(a0))
	REG_L	REG(s7), SBI_TRAP_REGS_OFFSET(s7)(PREG(a0))
	REG_L	REG(s8), SBI_TRAP_REGS_OFFSET(s8)(PREG(a0))
	REG_L	REG(s9), SBI_TRAP_REGS_OFFSET(s9)(PREG(a0))
	REG_L	REG(s10), SBI_TRAP_REGS_OFFSET(s10)(PREG(a0))
	REG_L	REG(s11), SBI_TRAP_REGS_OFFSET(s11)(PREG(a0))
	REG_L	REG(t3), SBI_TRAP_REGS_OFFSET(t3)(PREG(a0))
	REG_L	REG(t4), SBI_TRAP_REGS_OFFSET(t4)(PREG(a0))
	REG_L	REG(t5), SBI_TRAP_REGS_OFFSET(t5)(PREG(a0))
	REG_L	REG(t6), SBI_TRAP_REGS_OFFSET(t6)(PREG(a0))
.endm

.macro	TRAP_RESTORE_MEPC_MSTATUS have_mstatush
	/* Restore MEPC and MSTATUS CSRs */
	PREG_L	PREG(t0), SBI_TRAP_REGS_OFFSET(mepc)(PREG(a0))
	csrw	CSR_MEPC, PREG(t0)
	REG_L	REG(t0), SBI_TRAP_REGS_OFFSET(mstatus)(PREG(a0))
	csrw	CSR_MSTATUS, t0
	.if \have_mstatush
	REG_L	REG(t0), SBI_TRAP_REGS_OFFSET(mstatusH)(PREG(a0))
	csrw	CSR_MSTATUSH, t0
	.endif
.endm

.macro TRAP_RESTORE_A0_T0
	/* Restore T0 */
	REG_L	REG(t0), SBI_TRAP_REGS_OFFSET(t0)(PREG(a0))

	/* Restore A0 */
	REG_L	REG(a0), SBI_TRAP_REGS_OFFSET(a0)(PREG(a0))
.endm

	.section .entry, "ax", %progbits
	.align 3
	.globl _trap_handler
	.type  _trap_handler, @function
_trap_handler:
	TRAP_SAVE_AND_SETUP_SP_T0

	TRAP_SAVE_MEPC_MSTATUS 0

	TRAP_SAVE_GENERAL_REGS_EXCEPT_SP_T0

	TRAP_SAVE_INFO 0 0

	TRAP_CALL_C_ROUTINE

	TRAP_RESTORE_GENERAL_REGS_EXCEPT_A0_T0

	TRAP_RESTORE_MEPC_MSTATUS 0

	TRAP_RESTORE_A0_T0

	mret
	.size _trap_handler, . - _trap_handler

	.section .entry, "ax", %progbits
	.align 3
	.globl _trap_handler_hyp
	.type  _trap_handler_hyp, @function
_trap_handler_hyp:
	TRAP_SAVE_AND_SETUP_SP_T0

#if __riscv_xlen == 32
	TRAP_SAVE_MEPC_MSTATUS 1
#else
	TRAP_SAVE_MEPC_MSTATUS 0
#endif

	TRAP_SAVE_GENERAL_REGS_EXCEPT_SP_T0

#if __riscv_xlen == 32
	TRAP_SAVE_INFO 1 1
#else
	TRAP_SAVE_INFO 0 1
#endif

	TRAP_CALL_C_ROUTINE

	TRAP_RESTORE_GENERAL_REGS_EXCEPT_A0_T0

#if __riscv_xlen == 32
	TRAP_RESTORE_MEPC_MSTATUS 1
#else
	TRAP_RESTORE_MEPC_MSTATUS 0
#endif

	TRAP_RESTORE_A0_T0

	mret
	.size _trap_handler_hyp, . - _trap_handler_hyp

	.section .entry, "ax", %progbits
	.align 3
	.globl _reset_regs
_reset_regs:

	/* flush the instruction cache */
	fence.i
	/* Reset all registers except ra, a0, a1, a2, a3 and a4 */
	li sp, 0
	li gp, 0
	li tp, 0
	li t0, 0
	li t1, 0
	li t2, 0
	li s0, 0
	li s1, 0
	li a5, 0
	li a6, 0
	li a7, 0
	li s2, 0
	li s3, 0
	li s4, 0
	li s5, 0
	li s6, 0
	li s7, 0
	li s8, 0
	li s9, 0
	li s10, 0
	li s11, 0
	li t3, 0
	li t4, 0
	li t5, 0
	li t6, 0
	csrw CSR_MSCRATCH, 0

	ret

#ifdef FW_FDT_PATH
	.section .rodata
	.align 4
	.globl fw_fdt_bin
fw_fdt_bin:
	.incbin FW_FDT_PATH
#ifdef FW_FDT_PADDING
	.fill FW_FDT_PADDING, 1, 0
#endif
#endif

#if defined(__CHERI_PURE_CAPABILITY__)
	.section .data
	.align 4
	.globl cheri_infinite_cap
	.type  cheri_infinite_cap, @object
cheri_infinite_cap:
	RISCV_PTR 0x0
	.size cheri_infinite_cap, . - cheri_infinite_cap
#endif

