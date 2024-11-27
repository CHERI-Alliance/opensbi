/*
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef __RISCV_CHERI_H__
#define __RISCV_CHERI_H__

#ifndef __ASSEMBLER__
#if defined(__riscv_zcheripurecap)
#include <cheriintrin.h>
#endif
#include <sbi/sbi_types.h>
#else /* __ASSEMBLER__ */
/* Capability permissions definition for assembly */
#if defined(__riscv_zcheripurecap)
#define CHERI_PERM_CAP			__CHERI_CAP_PERMISSION_CAPABILITY__
#define CHERI_PERM_WRITE		__CHERI_CAP_PERMISSION_WRITE__
#define CHERI_PERM_READ			__CHERI_CAP_PERMISSION_READ__
#define CHERI_PERM_EXECUTE		__CHERI_CAP_PERMISSION_EXECUTE__
#define CHERI_PERM_SYSTEM_REGS		__CHERI_CAP_PERMISSION_ACCESS_SYSTEM_REGISTERS__
#define CHERI_PERM_LOAD_MUTABLE		__CHERI_CAP_PERMISSION_LOAD_MUTABLE__
#if defined(__riscv_zcherilevels)
#define CHERI_PERM_ELEVATE_LEVEL	__CHERI_CAP_PERMISSION_ELEVATE_LEVEL__
#define CHERI_PERM_STORE_LEVEL		__CHERI_CAP_PERMISSION_STORE_LEVEL__
#define CHERI_PERM_CAPABILITY_LEVEL	__CHERI_CAP_PERMISSION_CAPABILITY_LEVEL__
#endif /* defined(__riscv_zcherilevels) */
#endif /* defined(__riscv_zcheripurecap) */
#endif /* __ASSEMBLER__ */

/* Capability permissions for Stack */
#define CHERI_PERM_STACK		(~CHERI_PERM_EXECUTE)
/* Capability permissions for Heap */
#define CHERI_PERM_HEAP			(~CHERI_PERM_EXECUTE)
/* Capability permissions for Executable */
#define CHERI_PERM_EXECUTABLE		(~CHERI_PERM_WRITE)
/* Capability permissions for Read Only Data */
#define CHERI_PERM_R_DATA		(~(CHERI_PERM_WRITE | CHERI_PERM_EXECUTE))
/* Capability permissions for Read Write Data */
#define CHERI_PERM_DATA			(~CHERI_PERM_EXECUTE)
/* Capability permissions for IO*/
#define CHERI_PERM_IO			(~(CHERI_PERM_EXECUTE | CHERI_PERM_CAP))

#ifndef __ASSEMBLER__
#if defined(__CHERI_PURE_CAPABILITY__)
extern void* cheri_infinite_cap;

static inline void *cheri_infinite_cap_get(void)
{
	return cheri_infinite_cap;
}

static inline void *cheri_build_cap_rw(unsigned long base, unsigned long size)
{
	void *ptr = cheri_address_set(cheri_infinite_cap_get(), base);
	ptr = cheri_bounds_set(ptr, size);
	ptr = cheri_perms_and(ptr, CHERI_PERM_DATA);
	ptr = cheri_is_invalid(ptr) ? NULL : ptr;

	return (void *)ptr;
}

static inline void *cheri_build_cap_r(unsigned long base, unsigned long size)
{
	void *ptr = cheri_address_set(cheri_infinite_cap_get(), base);
	ptr = cheri_bounds_set(ptr, size);
	ptr = cheri_perms_and(ptr, CHERI_PERM_R_DATA);
	ptr = cheri_is_invalid(ptr) ? NULL : ptr;

	return (void *)ptr;
}

static inline void *cheri_build_cap_inf(unsigned long offset)
{
	void *ptr = cheri_address_set(cheri_infinite_cap_get(), offset);
	return (void *)ptr;
}
#endif
#endif /* __ASSEMBLER__ */

#endif /* __RISCV_CHERI_H__ */