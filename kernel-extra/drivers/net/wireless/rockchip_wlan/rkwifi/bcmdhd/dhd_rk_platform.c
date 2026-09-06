// SPDX-License-Identifier: GPL-2.0
/*
 * Minimal Rockchip platform glue for bcmdhd on a mainline kernel.
 *
 * Replaces the vendor net/rfkill/rfkill-wlan.c (which needs wakelocks,
 * rk_vendor_storage, GRF syscon and mmc pwrseq internals). The AP6275P on
 * hub-11 is PCIe with WL_REG_ON driven by an always-on fixed regulator in the
 * device tree, so power and card-detect are no-ops. The out-of-band host
 * wake IRQ is read from a "wlan-platdata" node:
 *
 *   wireless-wlan {
 *       compatible = "wlan-platdata";
 *       host-wake-gpios = <&gpio0 RK_PB2 GPIO_ACTIVE_HIGH>;   /* gpiod "host-wake" */
 *   };
 */
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/gpio/consumer.h>
#include <linux/interrupt.h>
#include <linux/rfkill-wlan.h>

static struct gpio_desc *rk_wifi_host_wake;
static int rk_wifi_host_wake_flag = -1;

static void rk_wifi_platform_probe_once(void)
{
	struct device_node *np;
	static bool done;

	if (done)
		return;
	done = true;

	np = of_find_compatible_node(NULL, NULL, "wlan-platdata");
	if (!np) {
		pr_info("bcmdhd: no wlan-platdata node, OOB host wake disabled\n");
		return;
	}
	rk_wifi_host_wake = fwnode_gpiod_get_index(of_fwnode_handle(np),
						   "host-wake", 0,
						   GPIOD_IN, "wifi_host_wake");
	if (IS_ERR(rk_wifi_host_wake)) {
		pr_info("bcmdhd: host-wake-gpios unavailable (%ld)\n",
			PTR_ERR(rk_wifi_host_wake));
		rk_wifi_host_wake = NULL;
	} else {
		rk_wifi_host_wake_flag = gpiod_is_active_low(rk_wifi_host_wake) ? 0 : 1;
	}
	of_node_put(np);
}

int rockchip_wifi_power(int on)
{
	/* WL_REG_ON is a regulator-always-on in the DTS. */
	return 0;
}
EXPORT_SYMBOL(rockchip_wifi_power);

int rockchip_wifi_set_carddetect(int val)
{
	/* PCIe: nothing to do. */
	return 0;
}
EXPORT_SYMBOL(rockchip_wifi_set_carddetect);

int rockchip_wifi_get_oob_irq(void)
{
	int irq;

	rk_wifi_platform_probe_once();
	if (!rk_wifi_host_wake)
		return -1;
	irq = gpiod_to_irq(rk_wifi_host_wake);
	return irq > 0 ? irq : -1;
}
EXPORT_SYMBOL(rockchip_wifi_get_oob_irq);

int rockchip_wifi_get_oob_irq_flag(void)
{
	rk_wifi_platform_probe_once();
	return rk_wifi_host_wake_flag;	/* 1 = active high, 0 = active low */
}
EXPORT_SYMBOL(rockchip_wifi_get_oob_irq_flag);

int rockchip_wifi_mac_addr(unsigned char *buf)
{
	return -1;	/* let the firmware / NVRAM MAC stand */
}
EXPORT_SYMBOL(rockchip_wifi_mac_addr);

int rockchip_wifi_ref_voltage(int on)
{
	return 0;
}
EXPORT_SYMBOL(rockchip_wifi_ref_voltage);

int rockchip_wifi_reset(int on)
{
	return 0;
}
EXPORT_SYMBOL(rockchip_wifi_reset);
