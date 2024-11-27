/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2019 Western Digital Corporation or its affiliates.
 *
 * Authors:
 *   Anup Patel <anup.patel@wdc.com>
 */

#include <sbi/fw_dynamic.h>

#include "fw_base.S"

	.section .entry, "ax", %progbits
	.align 3
	.global fw_boot_hart
	/*
	 * This function is called very early even before
	 * fw_save_info() is called.
	 * We can only use a0, a1, and a2 registers here.
	 * The boot HART id should be returned in 'a0'.
	 */
fw_boot_hart:
	/* Sanity checks */
	li	a1, FW_DYNAMIC_INFO_MAGIC_VALUE
	XREG_L	a0, FW_DYNAMIC_INFO_MAGIC_OFFSET(PREG(a2))
	bne	a0, a1, _start_hang
	li	a1, FW_DYNAMIC_INFO_VERSION_MAX
	XREG_L	a0, FW_DYNAMIC_INFO_VERSION_OFFSET(PREG(a2))
	bgt	a0, a1, _start_hang

	/* Read boot HART id */
	li	a1, FW_DYNAMIC_INFO_VERSION_2
	blt	a0, a1, 2f
	XREG_L	a0, FW_DYNAMIC_INFO_BOOT_HART_OFFSET(PREG(a2))
	ret
2:	li	a0, -1
	ret

	.section .entry, "ax", %progbits
	.align 3
	.global fw_save_info
	/*
	 * We can only use a0, a1, a2, a3, and a4 registers here.
	 * The a0, a1, and a2 registers will be same as passed by
	 * previous booting stage.
	 * Nothing to be returned here.
	 */
fw_save_info:
	/* Save next arg1 in 'a1' */
	PTR_L	PREG(a4), _dynamic_next_arg1
	XREG_S	a1, (PREG(a4))

	/* Save version == 0x1 fields */
	PTR_L	PREG(a4), _dynamic_next_addr
	XREG_L	a3, FW_DYNAMIC_INFO_NEXT_ADDR_OFFSET(PREG(a2))
	XREG_S	a3, (PREG(a4))
	PTR_L	PREG(a4), _dynamic_next_mode
	XREG_L	a3, FW_DYNAMIC_INFO_NEXT_MODE_OFFSET(PREG(a2))
	XREG_S	a3, (PREG(a4))
	PTR_L	PREG(a4), _dynamic_options
	XREG_L	a3, FW_DYNAMIC_INFO_OPTIONS_OFFSET(PREG(a2))
	XREG_S	a3, (PREG(a4))

	/* Save version == 0x2 fields */
	li	a4, FW_DYNAMIC_INFO_VERSION_2
	XREG_L	a3, FW_DYNAMIC_INFO_VERSION_OFFSET(PREG(a2))
	blt	a3, a4, 2f
	PTR_L	PREG(a4), _dynamic_boot_hart
	XREG_L	a3, FW_DYNAMIC_INFO_BOOT_HART_OFFSET(PREG(a2))
	XREG_S	a3, (PREG(a4))
2:
	ret

	.section .entry, "ax", %progbits
	.align 3
	.global fw_next_arg1
	/*
	 * We can only use a0, a1, and a2 registers here.
	 * The a0, a1, and a2 registers will be same as passed by
	 * previous booting stage.
	 * The next arg1 should be returned in 'a0'.
	 */
fw_next_arg1:
	PTR_L	PREG(a0), _dynamic_next_arg1
	XREG_L	a0, (PREG(a0))
#if defined(__CHERI_PURE_CAPABILITY__)
	scaddr	PREG(a0), PREG(a3), a0
	li a1,	CHERI_PERM_DATA		/* FDT is a read-write data */
	acperm	PREG(a0), PREG(a0), a1
#endif /* defined(__CHERI_PURE_CAPABILITY__) */
	ret

	.section .entry, "ax", %progbits
	.align 3
	.global fw_next_addr
	/*
	 * We can only use a0, a1, and a2 registers here.
	 * The next address should be returned in 'a0'.
	 */
fw_next_addr:
	PTR_L	PREG(a0), _dynamic_next_addr
	XREG_L	a0, (PREG(a0))
#if defined(__CHERI_PURE_CAPABILITY__)
	scaddr	PREG(a0), PREG(a3), a0
#endif /* defined(__CHERI_PURE_CAPABILITY__) */
	ret

	.section .entry, "ax", %progbits
	.align 3
	.global fw_next_mode
	/*
	 * We can only use a0, a1, and a2 registers here.
	 * The next address should be returned in 'a0'
	 */
fw_next_mode:
	PTR_L	PREG(a0), _dynamic_next_mode
	XREG_L	a0, (PREG(a0))
	ret

	.section .entry, "ax", %progbits
	.align 3
	.global fw_options
	/*
	 * We can only use a0, a1, and a2 registers here.
	 * The 'a4' register will have default options.
	 * The next address should be returned in 'a0'.
	 */
fw_options:
	PTR_L	PREG(a0), _dynamic_options
	XREG_L	a0, (PREG(a0))
	ret

	.section .data
	.align 3
	.type  _dynamic_next_arg1, @object
_dynamic_next_arg1:
	RISCV_LONG 0x0
	.size _dynamic_next_arg1, . - _dynamic_next_arg1

	.type  _dynamic_next_addr, @object
_dynamic_next_addr:
	RISCV_ADDR 0x0
	.size _dynamic_next_addr, . - _dynamic_next_addr

	.type  _dynamic_next_mode, @object
_dynamic_next_mode:
	RISCV_LONG PRV_S
	.size _dynamic_next_mode, . - _dynamic_next_mode

	.type  _dynamic_options, @object
_dynamic_options:
	RISCV_LONG 0x0
	.size _dynamic_options, . - _dynamic_options

	.type  _dynamic_boot_hart, @object
_dynamic_boot_hart:
	RISCV_LONG -1
	.size _dynamic_boot_hart, . - _dynamic_boot_hart
