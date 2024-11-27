/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2025 MIPS
 *
 */
	.text
	.align	12
	.globl	mips_warm_boot
	.type	mips_warm_boot, @function
mips_warm_boot:
	j	_start_warm
	.align	2
	.size	mips_warm_boot, . - mips_warm_boot
