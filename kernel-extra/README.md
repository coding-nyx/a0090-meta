# kernel-extra: out-of-tree sources copied into the kernel tree at build time

`scripts/build-kernel.sh` copies this tree over `$KERNEL_SRC` after applying
`patches/*.patch`. Files here are untracked in the kernel tree, so they do not
affect `setlocalversion` (no `-dirty`).

## drivers/net/wireless/rockchip_wlan (bcmdhd 101.10.591.52)

Rockchip's `bcmdhd` for the Ampak AP6275P (BCM43752, PCIe). Taken from
`armbian/linux-rockchip` branch `rk-6.1-rkr7.2`, commit 5ef479b1070b
(`drivers/net/wireless/rockchip_wlan`, `include/linux/rfkill-wlan.h`), then
ported to mainline 6.18:

- `rkwifi/bcmdhd/dhd_compat_mainline.h` (force-included): `strlcpy`, `PDE_DATA`, `net/rps.h`.
- `rkwifi/bcmdhd/dhd_rk_platform.c`: replaces the vendor `net/rfkill/rfkill-wlan.c`
  (power is a fixed regulator in the DTS; host-wake GPIO read from the `wlan-platdata` node).
- `include/linuxver.h`: `timer_delete*`, string `MODULE_IMPORT_NS`.
- `wl_cfg80211.c`, `wl_cfgvif.c`: 6.17 `radio_idx` in `set_tx_power`/`get_tx_power`/`set_wiphy_params`, 3-arg `cfg80211_ch_switch_notify`.
- `dhd_pcie*.c`: vendor ASPM / link-reset calls guarded behind `CONFIG_PCIEASPM_ROCKCHIP_WIFI_EXTENSION`.
- `dhd_linux.c`: `kstat_irqs` as `struct irqstat`.
- stub headers `include/net/lib80211.h`, `include/asm/unaligned.h`; `Kconfig` no longer depends on `RFKILL_RK`.
- `Makefile`: `-I$(src)`, `CONFIG_BCMDHD_STATIC_IF` → `-DWL_STATIC_IF` (creates `wlan1` at boot).

Hooked into the tree by `patches/0003-net-wireless-hook-rockchip_wlan.patch`.
Why: the vendor firmware only supports AP/RSDB under this driver (docs/wlan1-ap.md).
Re-check at every `KERNEL_TAG` bump: `make M=... ` errors are the porting surface.
