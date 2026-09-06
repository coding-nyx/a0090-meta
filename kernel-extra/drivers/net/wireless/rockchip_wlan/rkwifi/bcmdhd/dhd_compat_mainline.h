/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Compatibility shims so the Rockchip bcmdhd tree (last updated for 6.8)
 * builds against mainline 6.18. Force-included via the Makefile.
 */
#ifndef _DHD_COMPAT_MAINLINE_H_
#define _DHD_COMPAT_MAINLINE_H_

#include <linux/version.h>
#include <linux/string.h>
#include <linux/timer.h>
#include <linux/proc_fs.h>
#include <linux/netdevice.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 9, 0) && defined(CONFIG_RPS)
#include <net/rps.h>
#endif


#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0)
/* strlcpy() was removed; emulate the classic return value (strlen(src)). */
static inline size_t dhd_compat_strlcpy(char *dst, const char *src, size_t size)
{
	size_t len = strlen(src);

	if (size) {
		size_t n = len >= size ? size - 1 : len;

		memcpy(dst, src, n);
		dst[n] = '\0';
	}
	return len;
}
#ifndef strlcpy
#define strlcpy(d, s, n)	dhd_compat_strlcpy(d, s, n)
#endif
#ifndef PDE_DATA
#define PDE_DATA(inode)		pde_data(inode)
#endif
#endif

#endif /* _DHD_COMPAT_MAINLINE_H_ */
