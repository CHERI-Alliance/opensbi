/*
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Copyright (c) 2020 Western Digital Corporation or its affiliates.
 *
 * Authors:
 *   Anup Patel <anup.patel@wdc.com>
 *   Atish Patra <atish.patra@wdc.com>
 */

#include <sbi/riscv_asm.h>
#include <sbi/riscv_cheri.h>
#include <sbi/sbi_console.h>
#include <sbi/sbi_domain.h>
#include <sbi/sbi_ecall.h>
#include <sbi/sbi_ecall_interface.h>
#include <sbi/sbi_error.h>
#include <sbi/sbi_hsm.h>
#include <sbi/sbi_ipi.h>
#include <sbi/sbi_platform.h>
#include <sbi/sbi_system.h>
#include <sbi/sbi_timer.h>
#include <sbi/sbi_tlb.h>
#include <sbi/sbi_trap.h>
#include <sbi/sbi_unpriv.h>
#include <sbi/sbi_hart.h>

/*
 * The hart_mask is a virtual address (pointer) in legacy extension.
 * The pointer is a capability rather then a integer on a core supports
 * Zcheripurecap extension. sbi_is_hart_mask_ptr_valid() is used to
 * check if the virtual pointer is valid to be used to access the
 * hart_mask.
 *
 * It will return SBI_EINVAL (SBI_ERR_INVALID_PARAM) if the capabilty
 * pointer cannot be used to read the hart_mask.
 */
static inline int sbi_is_hart_mask_ptr_valid(ulong **pmask)
{
#if defined(__CHERI_PURE_CAPABILITY__)
	if (*pmask && cheri_is_valid(*pmask) &&
	    (cheri_perms_get(*pmask) & CHERI_PERM_READ))
		return SBI_OK;

	return SBI_EINVAL;
#else  /* !defined(__CHERI_PURE_CAPABILITY__) */
	return SBI_OK;
#endif /* !defined(__CHERI_PURE_CAPABILITY__) */
}

static bool sbi_load_hart_mask_unpriv(ulong *pmask, ulong *hmask,
				      struct sbi_trap_info *uptrap)
{
	ulong mask = 0;

	if (pmask) {
		mask = sbi_load_ulong(pmask, uptrap);
		if (uptrap->cause)
			return false;
	} else {
		sbi_hsm_hart_interruptible_mask(sbi_domain_thishart_ptr(),
						0, &mask);
	}
	*hmask = mask;

	return true;
}

static int sbi_ecall_legacy_handler(unsigned long extid, unsigned long funcid,
				    struct sbi_trap_regs *regs,
				    struct sbi_ecall_return *out)
{
	int ret = SBI_OK;
	struct sbi_tlb_info tlb_info;
	u32 source_hart = current_hartid();
	struct sbi_trap_info trap = {0};
	ulong hmask = 0;
	ulong *pmask = NULL;

	switch (extid) {
	case SBI_EXT_0_1_SET_TIMER:
#if __riscv_xlen == 32
		sbi_timer_event_start((((u64)regs->a1 << 32) | (u64)regs->a0));
#else
		sbi_timer_event_start((u64)regs->a0);
#endif
		break;
	case SBI_EXT_0_1_CONSOLE_PUTCHAR:
		sbi_putc(regs->a0);
		break;
	case SBI_EXT_0_1_CONSOLE_GETCHAR:
		ret = sbi_getc();
		break;
	case SBI_EXT_0_1_CLEAR_IPI:
		sbi_ipi_clear_smode();
		break;
	case SBI_EXT_0_1_SEND_IPI:
		pmask = (ulong *)regs->a0;
		ret = sbi_is_hart_mask_ptr_valid(&pmask);
		if (ret == SBI_OK) {
			if (sbi_load_hart_mask_unpriv(pmask,
							&hmask, &trap)) {
				ret = sbi_ipi_send_smode(hmask, 0);
			} else {
				sbi_trap_redirect(regs, &trap);
				out->skip_regs_update = true;
			}
		}
		break;
	case SBI_EXT_0_1_REMOTE_FENCE_I:
		pmask = (ulong *)regs->a0;
		ret = sbi_is_hart_mask_ptr_valid(&pmask);
		if (ret == SBI_OK) {
			if (sbi_load_hart_mask_unpriv(pmask,
							&hmask, &trap)) {
				SBI_TLB_INFO_INIT(&tlb_info, 0, 0, 0, 0,
						SBI_TLB_FENCE_I, source_hart);
				ret = sbi_tlb_request(hmask, 0, &tlb_info);
			} else {
				sbi_trap_redirect(regs, &trap);
				out->skip_regs_update = true;
			}
		}
		break;
	case SBI_EXT_0_1_REMOTE_SFENCE_VMA:
		pmask = (ulong *)regs->a0;
		ret = sbi_is_hart_mask_ptr_valid(&pmask);
		if (ret == SBI_OK) {
			if (sbi_load_hart_mask_unpriv(pmask,
						&hmask, &trap)) {
				SBI_TLB_INFO_INIT(&tlb_info, regs->a1, regs->a2, 0, 0,
						SBI_TLB_SFENCE_VMA, source_hart);
				ret = sbi_tlb_request(hmask, 0, &tlb_info);
			} else {
				sbi_trap_redirect(regs, &trap);
				out->skip_regs_update = true;
			}
		}
		break;
	case SBI_EXT_0_1_REMOTE_SFENCE_VMA_ASID:
		pmask = (ulong *)regs->a0;
		ret = sbi_is_hart_mask_ptr_valid(&pmask);
		if (ret == SBI_OK) {
			if (sbi_load_hart_mask_unpriv(pmask,
							&hmask, &trap)) {
				SBI_TLB_INFO_INIT(&tlb_info, regs->a1,
						regs->a2, regs->a3, 0,
						SBI_TLB_SFENCE_VMA_ASID,
						source_hart);
				ret = sbi_tlb_request(hmask, 0, &tlb_info);
			} else {
				sbi_trap_redirect(regs, &trap);
				out->skip_regs_update = true;
			}
		}
		break;
	case SBI_EXT_0_1_SHUTDOWN:
		sbi_system_reset(SBI_SRST_RESET_TYPE_SHUTDOWN,
				 SBI_SRST_RESET_REASON_NONE);
		break;
	default:
		ret = SBI_ENOTSUPP;
	}

	return ret;
}

struct sbi_ecall_extension ecall_legacy;

static int sbi_ecall_legacy_register_extensions(void)
{
	return sbi_ecall_register_extension(&ecall_legacy);
}

struct sbi_ecall_extension ecall_legacy = {
	.extid_start		= SBI_EXT_0_1_SET_TIMER,
	.extid_end		= SBI_EXT_0_1_SHUTDOWN,
	.register_extensions	= sbi_ecall_legacy_register_extensions,
	.handle			= sbi_ecall_legacy_handler,
};
