# wlan1 / access point

**Status:** the mainline `brcmfmac` path is not viable with the vendor firmware
(record below). The fix is the vendor `bcmdhd` driver ported into our kernel
(`kernel-extra/`, `patches/0003`), which is what the vendor image used. See
"bcmdhd port" at the end.

## brcmfmac: tested and not viable with the current firmware

Goal was the vendor-image behaviour: `wlan0` as Wi-Fi client plus a second
interface (`wlan1`) acting as a hotspot. Result on 2026-09-06, mainline 6.18.49
`brcmfmac`, AP6275P (BCM43752 PCIe) with the vendor firmware
`fw_bcm43752a2_pcie_ag.bin` (18.35.387.23.146, 2022-07-12): **no AP mode at all**.

## What the driver advertises

`iw phy phy0 info`, valid interface combinations:

```
#{ managed } <= 2, #{ P2P-device } <= 1, total <= 3, #channels <= 2
#{ managed } <= 1, #{ AP } <= 1, #{ P2P-client } <= 1, #{ P2P-device } <= 1, total <= 4, #channels <= 1
```

So cfg80211 would allow STA+AP on one channel. The firmware does not deliver it.

## What was tried

| test | result |
|---|---|
| `iw phy phy0 interface add wlan1 type __ap` | interface appears (legacy fallback), but `brcmf_cfg80211_request_ap_if: failed to create interface(v1/v2), err=-52` |
| NetworkManager hotspot on wlan1, channel 149 (wlan0's channel) | `send_key_to_dongle: wsec_key error (-52)`, `brcmf_cfg80211_stop_ap: setting AP mode failed -52` |
| client on wlan1, AP on wlan0 | client: `brcmf_cfg80211_connect: failed to enable fw supplicant`; not usable |
| AP only on wlan0, client down (NetworkManager / wpa_supplicant AP path) | `brcmf_vif_set_mgmt_ie: vndr ie set error : -52`, no beacon seen from lab |
| `hostapd` directly on wlan0, client down, 65 s | hostapd prints `AP-ENABLED`, but lab (same room, same channel) never sees the SSID in three scans; firmware accepts the mode and does not beacon |
| `hostapd` on virtual wlan1 while wlan0 stays associated | `Failed to set channel (freq=5745): -95 (Operation not supported)`, interface init fails; wlan0 unaffected |

`-52` is `BCME_IE_NOTFOUND` from the firmware. This Rockchip firmware build is
made for Rockchip's out-of-tree `bcmdhd` driver, which drives it with a
different IOVAR dialect (interface creation, vendor IEs, RSDB). Upstream
`brcmfmac` expects Broadcom/Infineon FullMAC firmware behaviour; client mode
happens to work, AP mode does not. That is why the vendor image had a
working `wlan1` and this one does not. Even the
P2P-device interface fails the same way at boot (`p2p-dev` vif, `err=-5`).

## Firmware alternatives checked

- Rockchip/Radxa `rkwifibt`: an `_apsta` firmware exists **only for the SDIO
  AP6275S**, not for the PCIe AP6275P. The PCIe directory has the same
  `fw_bcm43752a2_pcie_ag.bin` we already use.
- Debian `firmware-brcm80211` (trixie): no 43752 files.
- Armbian firmware repo: same vendor blob.

## What is kept in the repo

`rootfs/overlay-optional/wlan1-ap/` holds the udev rule, systemd unit,
NetworkManager hotspot template and the channel-follow dispatcher that were
written for this. They are **not** installed by `build-rootfs.sh`. If a
firmware build with working AP support turns up, copy them into
`rootfs/overlay/` at their original paths and put the PSK in `rootfs/secrets/`.

## Alternatives if a hotspot is needed

1. A cheap USB Wi-Fi dongle with mainline AP support (e.g. MT7921U/MT7612U)
   on one of the three USB ports; NetworkManager hotspot on it.
2. Wired uplink (eth0/eth1) and turn wlan0 into the AP — also blocked by the
   same firmware, so this needs the dongle too.

Client Wi-Fi (`wlan0` on `nope_5g`) is unaffected and pinned to wlan0
(`connection.interface-name=wlan0`).

## bcmdhd port (the way forward)

- Source: Rockchip `bcmdhd` 101.10.591.52 from `armbian/linux-rockchip`
  `rk-6.1-rkr7.2`, ported to 6.18 in `kernel-extra/drivers/net/wireless/rockchip_wlan`
  (what changed: `kernel-extra/README.md`). Built as module `bcmdhd.ko` with
  `CONFIG_BCMDHD_PCIE=y` and `CONFIG_BCMDHD_STATIC_IF=y` (creates `wlan1` at boot,
  the vendor RSDB behaviour).
- Firmware: the same vendor files, reachable under the names bcmdhd expects via
  symlinks in `rootfs/overlay/usr/lib/firmware/brcm/`
  (`fw_bcm43752a2_pcie_ag.bin`, `nvram_ap6275p.txt`, `clm_bcm43752a2_pcie_ag.blob`).
- Userspace: `rootfs/overlay/etc/modprobe.d/bcmdhd.conf` blacklists `brcmfmac`;
  delete that line to fall back to client-only mainline Wi-Fi.
- DTS: `wireless-wlan { compatible = "wlan-platdata"; WIFI,host_wake_irq = <&gpio0 RK_PB2 ...>; }`
  feeds the host-wake IRQ; power is the always-on `wl_en_3v3` regulator.
- Hotspot config: `rootfs/overlay-optional/wlan1-ap/` (NetworkManager profile
  template, channel-follow dispatcher). Move into `rootfs/overlay/` once wlan1
  is confirmed working under bcmdhd; PSK lives in `rootfs/secrets/hub11-ap.psk`.
- Cost: ~300k lines of vendor code without upstream review; re-port at every
  `KERNEL_TAG` bump (`make M=kernel-extra/... ` against the new tree shows the surface).

### bcmdhd status 2026-09-06 21:00

First boot with `bcmdhd.ko` (6.18.49-hub11): module loads, PCIe device found
(`devid=0x449d chip=0xaae8 rev 2`), firmware (936074 B) and NVRAM download and
verify, "Took ARM out of Reset", then `dhdpcie_readshared: address of
pciedev_shared invalid ... dongle is not ready` after 2 s: the firmware never
starts. Probe fails cleanly; Ethernet unaffected. A live `modprobe -r bcmdhd;
modprobe bcmdhd` cycle crashed the kernel (box needed a power cycle), so
debugging continues only at boot time or offline. Until it works,
`/etc/modprobe.d/bcmdhd.conf` should blacklist `bcmdhd` (not brcmfmac) so the
client link stays on mainline brcmfmac.

Leads: PCIe ASPM/L1 state on the link (vendor driver disabled it through the
Rockchip ASPM extension we had to guard out), the missing optional
`config_bcm43752a2_pcie_ag.txt`, and whether the dongle needs a WL_REG_ON power
cycle before download (vendor rfkill toggled it; our regulator is always-on).
