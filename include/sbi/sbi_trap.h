/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2019 Western Digital Corporation or its affiliates.
 *
 * Authors:
 *   Anup Patel <anup.patel@wdc.com>
 */

#ifndef __SBI_TRAP_H__
#define __SBI_TRAP_H__

#include <sbi/riscv_encoding.h>

/* clang-format off */

/** Index of zero member in sbi_trap_regs */
#define SBI_TRAP_REGS_zero			0
/** Index of ra member in sbi_trap_regs */
#define SBI_TRAP_REGS_ra			1
/** Index of sp member in sbi_trap_regs */
#define SBI_TRAP_REGS_sp			2
/** Index of gp member in sbi_trap_regs */
#define SBI_TRAP_REGS_gp			3
/** Index of tp member in sbi_trap_regs */
#define SBI_TRAP_REGS_tp			4
/** Index of t0 member in sbi_trap_regs */
#define SBI_TRAP_REGS_t0			5
/** Index of t1 member in sbi_trap_regs */
#define SBI_TRAP_REGS_t1			6
/** Index of t2 member in sbi_trap_regs */
#define SBI_TRAP_REGS_t2			7
/** Index of s0 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s0			8
/** Index of s1 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s1			9
/** Index of a0 member in sbi_trap_regs */
#define SBI_TRAP_REGS_a0			10
/** Index of a1 member in sbi_trap_regs */
#define SBI_TRAP_REGS_a1			11
/** Index of a2 member in sbi_trap_regs */
#define SBI_TRAP_REGS_a2			12
/** Index of a3 member in sbi_trap_regs */
#define SBI_TRAP_REGS_a3			13
/** Index of a4 member in sbi_trap_regs */
#define SBI_TRAP_REGS_a4			14
/** Index of a5 member in sbi_trap_regs */
#define SBI_TRAP_REGS_a5			15
/** Index of a6 member in sbi_trap_regs */
#define SBI_TRAP_REGS_a6			16
/** Index of a7 member in sbi_trap_regs */
#define SBI_TRAP_REGS_a7			17
/** Index of s2 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s2			18
/** Index of s3 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s3			19
/** Index of s4 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s4			20
/** Index of s5 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s5			21
/** Index of s6 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s6			22
/** Index of s7 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s7			23
/** Index of s8 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s8			24
/** Index of s9 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s9			25
/** Index of s10 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s10			26
/** Index of s11 member in sbi_trap_regs */
#define SBI_TRAP_REGS_s11			27
/** Index of t3 member in sbi_trap_regs */
#define SBI_TRAP_REGS_t3			28
/** Index of t4 member in sbi_trap_regs */
#define SBI_TRAP_REGS_t4			29
/** Index of t5 member in sbi_trap_regs */
#define SBI_TRAP_REGS_t5			30
/** Index of t6 member in sbi_trap_regs */
#define SBI_TRAP_REGS_t6			31
/** Index of mepc member in sbi_trap_regs */
#define SBI_TRAP_REGS_mepc			32
/** Index of mstatus member in sbi_trap_regs */
#define SBI_TRAP_REGS_mstatus			33
/** Index of mstatusH member in sbi_trap_regs */
#define SBI_TRAP_REGS_mstatusH			34
/** Last member index in sbi_trap_regs */
#define SBI_TRAP_REGS_last			35

/** Index of cause member in sbi_trap_info */
#define SBI_TRAP_INFO_cause			0
/** Index of tval member in sbi_trap_info */
#define SBI_TRAP_INFO_tval			1
/** Index of tval2 member in sbi_trap_info */
#define SBI_TRAP_INFO_tval2			2
/** Index of tinst member in sbi_trap_info */
#define SBI_TRAP_INFO_tinst			3
/** Index of gva member in sbi_trap_info */
#define SBI_TRAP_INFO_gva			4
/** Index of reseved member in sbi_trap_info */
#define SBI_TRAP_INFO_reseved			5
/** Last member index in sbi_trap_info */
#define SBI_TRAP_INFO_last			6

/* clang-format on */

/** Get offset of member with name 'x' in sbi_trap_regs */
#define SBI_TRAP_REGS_OFFSET(x) ((SBI_TRAP_REGS_##x) * __SIZEOF_POINTER__)
/** Size (in bytes) of sbi_trap_regs */
#define SBI_TRAP_REGS_SIZE SBI_TRAP_REGS_OFFSET(last)

/** Get offset of member with name 'x' in sbi_trap_info */
#define SBI_TRAP_INFO_OFFSET(x) ((SBI_TRAP_INFO_##x) * __SIZEOF_LONG__)
/** Size (in bytes) of sbi_trap_info */
#define SBI_TRAP_INFO_SIZE SBI_TRAP_INFO_OFFSET(last)

/** Size (in bytes) of sbi_trap_context */
#define SBI_TRAP_CONTEXT_SIZE (SBI_TRAP_REGS_SIZE + \
			       SBI_TRAP_INFO_SIZE + \
			       __SIZEOF_POINTER__)

#ifndef __ASSEMBLER__

#include <sbi/sbi_types.h>
#include <sbi/sbi_scratch.h>

/** Representation of register state at time of trap/interrupt */
struct sbi_trap_regs {
	/** zero register state */
	uintptr_t zero;
	/** ra register state */
	uintptr_t ra;
	/** sp register state */
	uintptr_t sp;
	/** gp register state */
	uintptr_t gp;
	/** tp register state */
	uintptr_t tp;
	/** t0 register state */
	uintptr_t t0;
	/** t1 register state */
	uintptr_t t1;
	/** t2 register state */
	uintptr_t t2;
	/** s0 register state */
	uintptr_t s0;
	/** s1 register state */
	uintptr_t s1;
	/** a0 register state */
	uintptr_t a0;
	/** a1 register state */
	uintptr_t a1;
	/** a2 register state */
	uintptr_t a2;
	/** a3 register state */
	uintptr_t a3;
	/** a4 register state */
	uintptr_t a4;
	/** a5 register state */
	uintptr_t a5;
	/** a6 register state */
	uintptr_t a6;
	/** a7 register state */
	uintptr_t a7;
	/** s2 register state */
	uintptr_t s2;
	/** s3 register state */
	uintptr_t s3;
	/** s4 register state */
	uintptr_t s4;
	/** s5 register state */
	uintptr_t s5;
	/** s6 register state */
	uintptr_t s6;
	/** s7 register state */
	uintptr_t s7;
	/** s8 register state */
	uintptr_t s8;
	/** s9 register state */
	uintptr_t s9;
	/** s10 register state */
	uintptr_t s10;
	/** s11 register state */
	uintptr_t s11;
	/** t3 register state */
	uintptr_t t3;
	/** t4 register state */
	uintptr_t t4;
	/** t5 register state */
	uintptr_t t5;
	/** t6 register state */
	uintptr_t t6;
	/** mepc register state */
	uintptr_t mepc;
	/** mstatus register state */
	uintptr_t mstatus;
	/** mstatusH register state (only for 32-bit) */
	uintptr_t mstatusH;
};

/** Representation of trap details */
struct sbi_trap_info {
	/** cause Trap exception cause */
	unsigned long cause;
	/** tval Trap value */
	unsigned long tval;
	/** tval2 Trap value 2 */
	unsigned long tval2;
	/** tinst Trap instruction */
	unsigned long tinst;
	/** gva Guest virtual address in tval flag */
	unsigned long gva;
	/** reseved for CHERI capability aligned */
	/*
	 * Make sure the stack pointer is aligned to 16 bytes to as
	 * SBI_TRAP_CONTEXT_SIZE is used to shift the stack pointer in trap
	 * exception. In integer mode on zcherihybird would use sc/lc instruction
	 * to initial the structe aligned to 16 bytes. It would have alignement
	 * isseue if the stack is not aligned to 16 bytes.
	 *
	 * TODO: May need to remove it if the size of struct sbi_trap_context
	 * changes in future
	 */
	unsigned long reseved;
};

/** Representation of trap context saved on stack */
struct sbi_trap_context {
	/** Register state */
	struct sbi_trap_regs regs;
	/** Trap details */
	struct sbi_trap_info trap;
	/** Pointer to previous trap context */
	struct sbi_trap_context *prev_context;
};

static inline unsigned long sbi_regs_gva(const struct sbi_trap_regs *regs)
{
	/*
	 * If the hypervisor extension is not implemented, mstatus[h].GVA is a
	 * WPRI field, which is guaranteed to read as zero. In addition, in this
	 * case we don't read mstatush and instead pretend it is zero, which
	 * handles privileged spec version < 1.12.
	 */

#if __riscv_xlen == 32
	return (regs->mstatusH & MSTATUSH_GVA) ? 1 : 0;
#else
	return (regs->mstatus & MSTATUS_GVA) ? 1 : 0;
#endif
}

int sbi_trap_redirect(struct sbi_trap_regs *regs,
		      const struct sbi_trap_info *trap);

static inline struct sbi_trap_context *sbi_trap_get_context(struct sbi_scratch *scratch)
{
	return (scratch) ? (void *)scratch->trap_context : NULL;
}

static inline void sbi_trap_set_context(struct sbi_scratch *scratch,
					struct sbi_trap_context *tcntx)
{
	scratch->trap_context = (uintptr_t)tcntx;
}

struct sbi_trap_context *sbi_trap_handler(struct sbi_trap_context *tcntx);

#endif

#endif
