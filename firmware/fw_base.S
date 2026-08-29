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

#define BOOT_LOTTERY_ACQUIRED		1
#define BOOT_STATUS_BOOT_HART_DONE	1

.macro	MOV_3R __d0, __s0, __d1, __s1, __d2, __s2
	PREG_MV	\__d0, \__s0
	PREG_MV	\__d1, \__s1
	PREG_MV	\__d2, \__s2
.endm

.macro	MOV_5R __d0, __s0, __d1, __s1, __d2, __s2, __d3, __s3, __d4, __s4
	PREG_MV	\__d0, \__s0
	PREG_MV	\__d1, \__s1
	PREG_MV	\__d2, \__s2
	PREG_MV	\__d3, \__s3
	PREG_MV	\__d4, \__s4
.endm

.macro CLEAR_MDT tmp
#if __riscv_xlen == 32
	li 	\tmp, MSTATUSH_MDT
	csrc	CSR_MSTATUSH, \tmp
#else
	li 	\tmp, MSTATUS_MDT
	csrc	CSR_MSTATUS, \tmp
#endif
.endm

.macro set_cap_perm rd rs scratch perm
#if defined(__riscv_y)
	li	\scratch, ~(\perm)
	ypermc	\rd, \rs, \scratch
#else
	li	\scratch, \perm
	acperm	c\rd, c\rd, \scratch
#endif
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
#endif

#if defined(__CHERI__)
#if defined(__riscv_zyhybrid) || defined(__riscv_zcherihybrid)
	ymodeswy
#endif
	/* Initialize the ca3 as infinite capability */
	auipc 	a3, 0
	yaddrw	a3, a3, zero
#if defined(__riscv_zyhybrid) || defined(__riscv_zcherihybrid)
	/* Set default infinite capability in integer pointer mode */
	/* and the offset to zero.                                 */
	li	t0, 1
	ymodew	a3, a3, t0
#endif
	PC_PTR_L	t0, cheri_infinite_cap
	PREG_S		a3, 0(t0)

	/* Convert FDT pointer from integer to capability */
	yaddrw	a1, a3, a1
	yaddrw	a2, a3, a2
#endif

	/* Find preferred boot HART id */
	MOV_3R	s0, a0, s1, a1, s2, a2
	call	fw_boot_hart
	mv	a6, a0
	MOV_3R	a0, s0, a1, s1, a2, s2
	li	a7, -1
	beq	a6, a7, _try_lottery
	/* Jump to relocation wait loop if we are not boot hart */
	bne	a0, a6, _wait_for_boot_hart
_try_lottery:
	/* Jump to relocation wait loop if we don't get relocation lottery */
	PC_PTR_L	a6, _boot_lottery
	li	a7, BOOT_LOTTERY_ACQUIRED
#if defined(__riscv_atomic) || defined(__riscv_zaamo)
	amoswap.w a6, a7, (a6)
	bnez	a6, _wait_for_boot_hart
#elif defined(__riscv_zalrsc)
_sc_fail:
	lr.w	t0, (a6)
	sc.w	t1, a7, (a6)
	bnez	t1, _sc_fail
	bnez	t0, _wait_for_boot_hart
#else
#error "need a or zalrsc"
#endif

	/* relocate the global table content */
	li	t0, FW_TEXT_START	/* link start */
	PC_PTR_L	t1, _fw_start	/* load start */
	sub	t2, t1, t0		/* load offset */
#if defined(__CHERI__)
	/* initialize cap table before executing c functions */
cheri_cap_init:
	lly	t0, __cap_relocs_start
	lly	t1, __cap_relocs_end
	beq		t0, t1, _relocate_done

2:	XREG_L	t3, 0(t0)	/* t3 <-- capreloc:capability_location */
	add	t3, t3, t2
	yaddrw	t3, a3, t3 	/* t3 <-- W permission capability points to capability */
	XREG_L	t4, SZXREG(t0)	/* t4 <-- capreloc:capability_base */
	bnez	t4, 3f		/* write cnull if capreloc:capability_base is zero */
	j	10f		/* Initialize next capability */

3:	/* Set address/base */
	add	t4, t4, t2
	yaddrw	t5, a3, t4 	/* t5 <-- Set base from a Infinite capability */

#if defined(__riscv_zyhybrid) || defined(__riscv_zcherihybrid)
	/* Set M-bit for all capability as purecap mode */
	ymodew	t5, t5, zero
#endif

	/* Do not set tight bounds for functions for default setting -cheri-cap-table-abi=pcrel  */
	XREG_L	t4, (SZXREG * 4)(t0)	/* t4 <-- capreloc:capability_flags */
	li	t6, CAP_RELOC_CR_FLAG_FUNC
	and	t6, t6, t4
	bnez	t6, 4f

	/* Set bounds */
	XREG_L	t4, (SZXREG * 3)(t0)	/* t4 <-- capreloc:capability_length */
	beqz	t4,	4f		/* unlimited bounds if the capability_length is zero */
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

	li	t6, CAP_RELOC_CR_FLAG_DONT_SEAL
	and	t6, t6, t4
	bnez	t6, 9f
	ysentry t5, t5
9:
	sy	t5, 0(t3)
10:
	yaddi	t0, t0, (SZXREG * 5)
	blt	t0, t1, 2b
#else /* !defined(__CHERI__) */
	PC_PTR_L	t0, __rela_dyn_start
	PC_PTR_L	t1, __rela_dyn_end
	beq	t0, t1, _relocate_done
2:
	XREG_L	t5, SZXREG(t0)	/* t5 <-- relocation info:type */
	li	t3, R_RISCV_RELATIVE	/* reloc type R_RISCV_RELATIVE */
	bne	t5, t3, 3f
	PREG_L	t3, 0(t0)
	PREG_L	t5, (SZXREG * 2)(t0)	/* t5 <-- addend */
	PREG_ADD	t5, t5, t2
	PREG_ADD	t3, t3, t2
	PREG_S	t5, 0(t3)		/* store runtime address to the GOT entry */

3:
	PREG_ADDI	t0, t0, (SZXREG * 3)
	blt	t0, t1, 2b
#endif /* !defined(__CHERI__) */
_relocate_done:
	/* At this point we are running from link address */

	/* Reset all registers except ra, a0, a1, a2, a3 and a4 for boot HART */
	li	ra, 0
	call	_reset_regs

	/* Zero-out BSS */
	PC_PTR_L	s4, _bss_start
	PC_PTR_L	s5, _bss_end
_bss_zero:
	REG_S	zero, 0(s4)
	PREG_ADDI	s4, s4, SZREG
	blt	s4, s5, _bss_zero

	/* Setup temporary trap handler */
	PC_PTR_L	s4, _start_hang
	csrw	CSR_MTVEC, s4

	/*
	 * While at this point, trap handling is rudimentary, if a trap happens,
	 * it will end up in _start_hang which is enough to hook up a GDB. Clear
	 * MDT to avoid generating a double trap and thus entering a
	 * critical-error state.
	 */
	CLEAR_MDT t0

	/* Setup temporary stack */
	PC_PTR_L	s4, _fw_end
	li	s5, (SBI_SCRATCH_SIZE * 2)
#if defined(__CHERI__)
	yaddrw	s4, a3, s4
	ybndsrw	s4, s4, s5
	set_cap_perm s4, s4, t0, CHERI_PERM_STACK
#endif
	PREG_ADD	sp, s4, s5

	/* Allow main firmware to save info */
	MOV_5R	s0, a0, s1, a1, s2, a2, s3, a3, s4, a4
	call	fw_save_info
	MOV_5R	a0, s0, a1, s1, a2, s2, a3, s3, a4, s4

#ifdef FW_FDT_PATH
	/* Override previous arg1 */
	PTR_L	a1, fw_fdt_bin
#endif

	/*
	 * Initialize platform
	 * Note: The a0 to a4 registers passed to the
	 * firmware are parameters to this function.
	 */
	MOV_5R	s0, a0, s1, a1, s2, a2, s3, a3, s4, a4
	call	fw_platform_init
	PREG_MV	t0, a0
	MOV_5R	a0, s0, a1, s1, a2, s2, a3, s3, a4, s4
	PREG_MV	a1, t0

	/* Preload HART details
	 * s7 -> HART Count
	 * s8 -> HART Stack Size
	 * s9 -> Heap Size
	 * s10 -> Heap Offset
	 */
	PTR_L	a4, platform
#if __riscv_xlen > 32
	lwu	s7, SBI_PLATFORM_HART_COUNT_OFFSET(a4)
	lwu	s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(a4)
	lwu	s9, SBI_PLATFORM_HEAP_SIZE_OFFSET(a4)
#else
	lw	s7, SBI_PLATFORM_HART_COUNT_OFFSET(a4)
	lw	s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(a4)
	lw	s9, SBI_PLATFORM_HEAP_SIZE_OFFSET(a4)
#endif

	/* Setup scratch space for all the HARTs*/
	PC_PTR_L	tp, _fw_end
	mul	a5, s7, s8
	PREG_ADD	tp, tp, a5
	/* Setup heap base address */
	PC_PTR_L	s10, _fw_start
	sub	s10, tp, s10
	PREG_ADD	tp, tp, s9
	/* Keep a copy of tp */
	PREG_MV	t3, tp
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
	PREG_MV	tp, t3
	sub	tp, tp, s9
	mul	a5, s8, t1
	sub	tp, tp, a5
	li	a5, SBI_SCRATCH_SIZE
	sub	tp, tp, a5
#if defined(__CHERI__)
	yaddrw	tp, t3, tp	/* Initialize tp with the stored tp */
	ybndsrw tp, tp, a5	/* scratch bounds is SBI_SCRATCH_SIZE */
	set_cap_perm tp, tp, t0, CHERI_PERM_DATA	/* scratch is a read-write data */

	/*
	 * Setup per hart stack for CHERI. Since CHERI capability stack pointer
	 * is not same as scratch pad pointer as the bonds are different. It needs
	 * another scratch field to store the stack pointer for CHERI.
	 */
	sub	a4, s8, a5	/* a4 <-- stack size (HART_STACK_SIZE - SBI_SCRATCH_SIZE) */
	sub	a5, tp, a4	/* a5 <-- sp base */
	yaddrw	a5, a3, a5	/* Initialize a4 with infinite cap */
	ybndsrw a5, a5, a4	/* sp bounds is stack size */
	set_cap_perm	a5, a5, t0, CHERI_PERM_DATA	/* sp is a read-write data */
	yadd	a5, a5, a4	/* Set a5 to sp top */
	sy	a5, SBI_SCRATCH_STACK_OFFSET(tp)
#endif

	/* Initialize scratch space */
	/* Store fw_start and fw_size in scratch space */
	PC_PTR_L	a4, _fw_start
	sub	a5, t3, a4
	XREG_S	a4, SBI_SCRATCH_FW_START_OFFSET(tp)
	XREG_S	a5, SBI_SCRATCH_FW_SIZE_OFFSET(tp)

	/* Store R/W section's offset in scratch space */
	PC_PTR_L	a5, _fw_rw_start
	sub	a5, a5, a4
	XREG_S	a5, SBI_SCRATCH_FW_RW_OFFSET(tp)

	/* Store fw_heap_offset and fw_heap_size in scratch space */
	XREG_S	s10, SBI_SCRATCH_FW_HEAP_OFFSET(tp)
	XREG_S	s9, SBI_SCRATCH_FW_HEAP_SIZE_OFFSET(tp)

	/* Store next arg1 in scratch space */
	MOV_3R	s0, a0, s1, a1, s2, a2
	call	fw_next_arg1
	PREG_S	a0, SBI_SCRATCH_NEXT_ARG1_OFFSET(tp)
	MOV_3R	a0, s0, a1, s1, a2, s2
	/* Store next address in scratch space */
	MOV_3R	s0, a0, s1, a1, s2, a2
	call	fw_next_addr
	PREG_S	a0, SBI_SCRATCH_NEXT_ADDR_OFFSET(tp)
	MOV_3R	a0, s0, a1, s1, a2, s2
	/* Store next mode in scratch space */
	MOV_3R	s0, a0, s1, a1, s2, a2
	call	fw_next_mode
	XREG_S	a0, SBI_SCRATCH_NEXT_MODE_OFFSET(tp)
	MOV_3R	a0, s0, a1, s1, a2, s2
	/* Store warm_boot address in scratch space */
	PTR_L	a4, _start_warm
	PREG_S	a4, SBI_SCRATCH_WARMBOOT_ADDR_OFFSET(tp)
	/* Store platform address in scratch space */
	PTR_L	a4, platform
	PREG_S	a4, SBI_SCRATCH_PLATFORM_ADDR_OFFSET(tp)
	/* Store hartid-to-scratch function address in scratch space */
	PTR_L	a4, _hartid_to_scratch
	PREG_S	a4, SBI_SCRATCH_HARTID_TO_SCRATCH_OFFSET(tp)
	/* Clear trap_context and tmp0 in scratch space */
	PREG_S	zero, SBI_SCRATCH_TRAP_CONTEXT_OFFSET(tp)
	PREG_S	zero, SBI_SCRATCH_TMP0_OFFSET(tp)
	/* Store firmware options in scratch space */
	MOV_3R	s0, a0, s1, a1, s2, a2
#ifdef FW_OPTIONS
	li	a0, FW_OPTIONS
#else
	call	fw_options
#endif
	XREG_S	a0, SBI_SCRATCH_OPTIONS_OFFSET(tp)
	MOV_3R	a0, s0, a1, s1, a2, s2
	/* Store hart index in scratch space */
	XREG_S	t1, SBI_SCRATCH_HARTINDEX_OFFSET(tp)
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
	MOV_3R	s0, a0, s1, a1, s2, a2
	call	fw_next_arg1
	PREG_MV	t1, a0
	MOV_3R	a0, s0, a1, s1, a2, s2
	beqz	t1, _fdt_reloc_done
	beq	t1, a1, _fdt_reloc_done
	/* t0 = source FDT start address */
	PREG_MV	t0, a1
	/* t2 = source FDT size (convert from big-endian) */
	lbu	t2, 7(t0)
	lbu	t3, 6(t0)
	lbu	t4, 5(t0)
	lbu	t5, 4(t0)
	slli	t3, t3, 8
	slli	t4, t4, 16
	slli	t5, t5, 24
	or	t2, t2, t3
	or	t2, t2, t4
	or	t2, t2, t5
	/* t2 = destination FDT end address */
	add	t2, t1, t2
	/* FDT copy loop */
	ble	t2, t1, _fdt_reloc_done
_fdt_reloc_again:
	XREG_L	t3, 0(t0)
	XREG_S	t3, 0(t1)
	PREG_ADDI	t0, t0, SZXREG
	PREG_ADDI	t1, t1, SZXREG
	blt	t1, t2, _fdt_reloc_again
_fdt_reloc_done:

	/* mark boot hart done */
	li	t0, BOOT_STATUS_BOOT_HART_DONE
	PTR_L	t1, _boot_status
	fence	rw, rw
	XREG_S	t0, 0(t1)
	j	_start_warm

	/* waiting for boot hart to be done (_boot_status == BOOT_STATUS_BOOT_HART_DONE) */
_wait_for_boot_hart:
	li	t0, BOOT_STATUS_BOOT_HART_DONE
	PC_PTR_L	t1, _boot_status
	XREG_L	t1, 0(t1)
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
	PTR_L	a4, platform
#if __riscv_xlen > 32
	lwu	s7, SBI_PLATFORM_HART_COUNT_OFFSET(a4)
	lwu	s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(a4)
#else
	lw	s7, SBI_PLATFORM_HART_COUNT_OFFSET(a4)
	lw	s8, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(a4)
#endif
	REG_L	s9, SBI_PLATFORM_HART_INDEX2ID_OFFSET(a4)

	/* Find HART id */
	csrr	s6, CSR_MHARTID

	/* Find HART index */
	beqz	s9, 3f
	li	a4, 0
1:
#if __riscv_xlen > 32
	lwu	a5, (s9)
#else
	lw	a5, (s9)
#endif
	beq	a5, s6, 2f
	PREG_ADDI	s9, s9, 4
	add	a4, a4, 1
	blt	a4, s7, 1b
2:	add	s6, a4, zero
3:	bge	s6, s7, _start_hang

	/* Find the scratch space based on HART index */
	PC_PTR_L	tp, _fw_end
	mul	a5, s7, s8
	add	tp, tp, a5
	mul	a5, s8, s6
	sub	tp, tp, a5
	li	a5, SBI_SCRATCH_SIZE
	sub	tp, tp, a5
#if defined(__CHERI__)
	PC_PTR_L	t0, cheri_infinite_cap
	ly	t1, 0(t0)
	yaddrw	tp, t1, tp		/* Initialize tp with infinite cap */
	ybndsrw tp, tp, a5		/* scratch bounds is SBI_SCRATCH_SIZE */
	set_cap_perm tp, tp, t0, CHERI_PERM_DATA	/* scratch is a read-write data */
#endif
	/* update the mscratch */
	csrw	CSR_MSCRATCH, tp

	/* Setup stack */
#if defined(__CHERI__)
	sub	a5, s8, a5	/* a5 <-- stack size (HART_STACK_SIZE - SBI_SCRATCH_SIZE) */
	sub	sp, tp, a5	/* Get sp base */
	yaddrw	sp, t1, sp		/* Initialize sp with infinite cap */
	ybndsrw sp, sp, a5		/* sp bounds is stack size */
	set_cap_perm sp, sp, t0, CHERI_PERM_DATA	/* sp is a read-write data */
	yadd	sp, sp, a5		/* Set sp to sp top */
#else
	yadd	sp, tp, zero
#endif

	/* Setup trap handler */
	PC_PTR_L	a4, _trap_handler
	csrr	a5, CSR_MISA
	srli	a5, a5, ('H' - 'A')
	andi	a5, a5, 0x1
	beq	a5, zero, _skip_trap_handler_hyp
	PC_PTR_L	a4, _trap_handler_hyp
_skip_trap_handler_hyp:
	csrw	CSR_MTVEC, a4

	/* Clear MDT here again for all harts */
	CLEAR_MDT t0

	/* Initialize SBI runtime */
	csrr	a0, CSR_MSCRATCH
	call	sbi_init

	/* We don't expect to reach here hence just hang */
	j	_start_hang
	.size _start_warm, . - _start_warm

	.data
	.align 3
	.type  _boot_lottery, @object
_boot_lottery:
	RISCV_LONG	0
	.size _boot_lottery, . - _boot_lottery

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
	PTR_L	t2, platform
#if __riscv_xlen > 32
	lwu	t0, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(t2)
	lwu	t2, SBI_PLATFORM_HART_COUNT_OFFSET(t2)
#else
	lw	t0, SBI_PLATFORM_HART_STACK_SIZE_OFFSET(t2)
	lw	t2, SBI_PLATFORM_HART_COUNT_OFFSET(t2)
#endif
	sub	t2, t2, a1
	mul	t2, t2, t0
	PC_PTR_L	t1, _fw_end
	add	t1, t1, t2
	li	t2, SBI_SCRATCH_SIZE
	sub	a0, t1, t2
#if defined(__CHERI__)
	PC_PTR_L	t0, cheri_infinite_cap
	PREG_L	t1, 0(t0)
	yaddrw	a0, t1, a0
	ybndsrw a0, a0, t2	/* scratch bounds is SBI_SCRATCH_SIZE */
	set_cap_perm	a0, a0, t0, CHERI_PERM_DATA	/* scratch is a read-write data */
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
	PREG_MV	a0, a1
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
	csrrw	tp, CSR_MSCRATCH, tp

	/* Save T0 in scratch space */
	REG_S	t0, SBI_SCRATCH_TMP0_OFFSET(tp)

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
#if defined(__CHERI__)
	beqz	t0, 1f
	PREG_L	t0, SBI_SCRATCH_STACK_OFFSET(tp)
	j 2f
1:
	PREG_MV	t0, sp
2:
#else /* !defined(__CHERI__) */
	add	t0, t0, -1
	xor	sp, sp, tp
	and	t0, t0, sp
	xor	sp, sp, tp
	xor	t0, tp, t0
#endif /* !defined(__CHERI__) */

	/* Save original SP on exception stack */
	PREG_S	sp, (SBI_TRAP_REGS_OFFSET(sp) - SBI_TRAP_CONTEXT_SIZE)(t0)

	/* Set SP to exception stack and make room for trap context */
	PREG_ADDI	sp, t0, -(SBI_TRAP_CONTEXT_SIZE)

	/* Restore T0 from scratch space */
	REG_L	t0, SBI_SCRATCH_TMP0_OFFSET(tp)

	/* Save T0 on stack */
	REG_S	t0, SBI_TRAP_REGS_OFFSET(t0)(sp)

	/* Swap TP and MSCRATCH */
	csrrw	tp, CSR_MSCRATCH, tp
.endm

.macro	TRAP_SAVE_MEPC_MSTATUS have_mstatush
	/* Save MEPC and MSTATUS CSRs */
	csrr	t0, CSR_MEPC
	PREG_S	t0, SBI_TRAP_REGS_OFFSET(mepc)(sp)
	csrr	t0, CSR_MSTATUS
	REG_S	t0, SBI_TRAP_REGS_OFFSET(mstatus)(sp)
	.if \have_mstatush
	csrr	t0, CSR_MSTATUSH
	REG_S	t0, SBI_TRAP_REGS_OFFSET(mstatusH)(sp)
	.else
	REG_S	zero, SBI_TRAP_REGS_OFFSET(mstatusH)(sp)
	.endif
.endm

.macro	TRAP_SAVE_GENERAL_REGS_EXCEPT_SP_T0
	/* Save all general regisers except SP and T0 */
	REG_S	zero, SBI_TRAP_REGS_OFFSET(zero)(sp)
	REG_S	ra, SBI_TRAP_REGS_OFFSET(ra)(sp)
	REG_S	gp, SBI_TRAP_REGS_OFFSET(gp)(sp)
	REG_S	tp, SBI_TRAP_REGS_OFFSET(tp)(sp)
	REG_S	t1, SBI_TRAP_REGS_OFFSET(t1)(sp)
	REG_S	t2, SBI_TRAP_REGS_OFFSET(t2)(sp)
	REG_S	s0, SBI_TRAP_REGS_OFFSET(s0)(sp)
	REG_S	s1, SBI_TRAP_REGS_OFFSET(s1)(sp)
	REG_S	a0, SBI_TRAP_REGS_OFFSET(a0)(sp)
	REG_S	a1, SBI_TRAP_REGS_OFFSET(a1)(sp)
	REG_S	a2, SBI_TRAP_REGS_OFFSET(a2)(sp)
	REG_S	a3, SBI_TRAP_REGS_OFFSET(a3)(sp)
	REG_S	a4, SBI_TRAP_REGS_OFFSET(a4)(sp)
	REG_S	a5, SBI_TRAP_REGS_OFFSET(a5)(sp)
	REG_S	a6, SBI_TRAP_REGS_OFFSET(a6)(sp)
	REG_S	a7, SBI_TRAP_REGS_OFFSET(a7)(sp)
	REG_S	s2, SBI_TRAP_REGS_OFFSET(s2)(sp)
	REG_S	s3, SBI_TRAP_REGS_OFFSET(s3)(sp)
	REG_S	s4, SBI_TRAP_REGS_OFFSET(s4)(sp)
	REG_S	s5, SBI_TRAP_REGS_OFFSET(s5)(sp)
	REG_S	s6, SBI_TRAP_REGS_OFFSET(s6)(sp)
	REG_S	s7, SBI_TRAP_REGS_OFFSET(s7)(sp)
	REG_S	s8, SBI_TRAP_REGS_OFFSET(s8)(sp)
	REG_S	s9, SBI_TRAP_REGS_OFFSET(s9)(sp)
	REG_S	s10, SBI_TRAP_REGS_OFFSET(s10)(sp)
	REG_S	s11, SBI_TRAP_REGS_OFFSET(s11)(sp)
	REG_S	t3, SBI_TRAP_REGS_OFFSET(t3)(sp)
	REG_S	t4, SBI_TRAP_REGS_OFFSET(t4)(sp)
	REG_S	t5, SBI_TRAP_REGS_OFFSET(t5)(sp)
	REG_S	t6, SBI_TRAP_REGS_OFFSET(t6)(sp)
.endm

.macro	TRAP_SAVE_INFO have_mstatush have_h_extension
	csrr	t0, CSR_MCAUSE
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(cause))(sp)
	csrr	t0, CSR_MTVAL
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tval))(sp)
.if \have_h_extension
	csrr	t0, CSR_MTVAL2
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tval2))(sp)
	csrr	t0, CSR_MTINST
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tinst))(sp)
	.if \have_mstatush
	csrr	t0, CSR_MSTATUSH
	srli	t0, t0, MSTATUSH_GVA_SHIFT
	.else
	csrr	t0, CSR_MSTATUS
	srli	t0, t0, MSTATUS_GVA_SHIFT
	.endif
	and	t0, t0, 0x1
.else
#if defined(__CHERI__) && defined(__riscv_zcheripurecap)
	csrr	t0, CSR_MTVAL2
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tval2))(sp)
#else
	XREG_S	zero, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tval2))(sp)
#endif
	XREG_S	zero, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(tinst))(sp)
	li	t0, 0
.endif
	XREG_S	t0, (SBI_TRAP_REGS_SIZE + SBI_TRAP_INFO_OFFSET(gva))(sp)

	/* We are ready to take another trap, clear MDT */
	CLEAR_MDT t0
.endm

.macro	TRAP_CALL_C_ROUTINE
	/* Call C routine */
	PREG_MV	a0, sp
	call	sbi_trap_handler
.endm

.macro	TRAP_RESTORE_GENERAL_REGS_EXCEPT_A0_T0
	/* Restore all general regisers except A0 and T0 */
	REG_L	ra, SBI_TRAP_REGS_OFFSET(ra)(a0)
	REG_L	sp, SBI_TRAP_REGS_OFFSET(sp)(a0)
	REG_L	gp, SBI_TRAP_REGS_OFFSET(gp)(a0)
	REG_L	tp, SBI_TRAP_REGS_OFFSET(tp)(a0)
	REG_L	t1, SBI_TRAP_REGS_OFFSET(t1)(a0)
	REG_L	t2, SBI_TRAP_REGS_OFFSET(t2)(a0)
	REG_L	s0, SBI_TRAP_REGS_OFFSET(s0)(a0)
	REG_L	s1, SBI_TRAP_REGS_OFFSET(s1)(a0)
	REG_L	a1, SBI_TRAP_REGS_OFFSET(a1)(a0)
	REG_L	a2, SBI_TRAP_REGS_OFFSET(a2)(a0)
	REG_L	a3, SBI_TRAP_REGS_OFFSET(a3)(a0)
	REG_L	a4, SBI_TRAP_REGS_OFFSET(a4)(a0)
	REG_L	a5, SBI_TRAP_REGS_OFFSET(a5)(a0)
	REG_L	a6, SBI_TRAP_REGS_OFFSET(a6)(a0)
	REG_L	a7, SBI_TRAP_REGS_OFFSET(a7)(a0)
	REG_L	s2, SBI_TRAP_REGS_OFFSET(s2)(a0)
	REG_L	s3, SBI_TRAP_REGS_OFFSET(s3)(a0)
	REG_L	s4, SBI_TRAP_REGS_OFFSET(s4)(a0)
	REG_L	s5, SBI_TRAP_REGS_OFFSET(s5)(a0)
	REG_L	s6, SBI_TRAP_REGS_OFFSET(s6)(a0)
	REG_L	s7, SBI_TRAP_REGS_OFFSET(s7)(a0)
	REG_L	s8, SBI_TRAP_REGS_OFFSET(s8)(a0)
	REG_L	s9, SBI_TRAP_REGS_OFFSET(s9)(a0)
	REG_L	s10, SBI_TRAP_REGS_OFFSET(s10)(a0)
	REG_L	s11, SBI_TRAP_REGS_OFFSET(s11)(a0)
	REG_L	t3, SBI_TRAP_REGS_OFFSET(t3)(a0)
	REG_L	t4, SBI_TRAP_REGS_OFFSET(t4)(a0)
	REG_L	t5, SBI_TRAP_REGS_OFFSET(t5)(a0)
	REG_L	t6, SBI_TRAP_REGS_OFFSET(t6)(a0)
.endm

.macro	TRAP_RESTORE_MEPC_MSTATUS have_mstatush
	/*
	 * Restore MSTATUS and MEPC CSRs starting with MSTATUS/H to set MDT
	 * flags since we can not take a trap now or MEPC would be cloberred
	 */
	.if \have_mstatush
	REG_L	t0, SBI_TRAP_REGS_OFFSET(mstatusH)(a0)
	csrw	CSR_MSTATUSH, t0
	.endif
	REG_L	t0, SBI_TRAP_REGS_OFFSET(mstatus)(a0)
	csrw	CSR_MSTATUS, t0
	PREG_L	t0, SBI_TRAP_REGS_OFFSET(mepc)(a0)
	csrw	CSR_MEPC, t0
.endm

.macro TRAP_RESTORE_A0_T0
	/* Restore T0 */
	REG_L	t0, SBI_TRAP_REGS_OFFSET(t0)(a0)

	/* Restore A0 */
	REG_L	a0, SBI_TRAP_REGS_OFFSET(a0)(a0)
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

	.section .rodata
	.type Lstack_corrupt_msg, %object
.Lstack_corrupt_msg:
	.string "stack smashing detected\n"
	.size .Lstack_corrupt_msg, . - .Lstack_corrupt_msg

	/* This will be called when the stack corruption is detected */
	.section .text
	.align 3
	.globl __stack_chk_fail
	.type __stack_chk_fail, %function
__stack_chk_fail:
	PTR_L	a0, .Lstack_corrupt_msg
	call	sbi_panic

	/* Initial value of the stack guard variable */
	.section .data
	.align 4
	.globl __stack_chk_guard
	.type __stack_chk_guard, %object
__stack_chk_guard:
	RISCV_PTR	0x95B5FF5A

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

#if defined(__CHERI__)
	.section .data
	.align 4
	.globl cheri_infinite_cap
	.type  cheri_infinite_cap, %object
cheri_infinite_cap:
	RISCV_PTR 0x0
	.size cheri_infinite_cap, . - cheri_infinite_cap
#endif

