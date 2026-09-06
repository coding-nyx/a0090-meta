> **Historical document (2026-09-06).** Kept for the record; several claims are stale or were wrong when written (Bullseye on p6, a live wlan1, the two-stage plan). Current state: README.md and RUNBOOK.md.

# AMedia RK3588 LP4 V10 (hub-11) System Status & Technical Report

**Date:** September 6, 2026  
**Target Hardware:** AMedia RK3588 LP4 V10 TV Box / Single-Board Computer  
**Kernel:** Mainline Linux 6.18 LTS (`6.18.49-dirty`)  
**OS / Rootfs:** Debian GNU/Linux 11 (Bullseye) / UsrMerge layout on `/dev/mmcblk0p6`  
**Boot Mechanism:** Rockchip Vendor U-Boot SPL -> FIT Image on partition `p3` (`/dev/mmcblk0p3`, 64 MiB limit)  

---

## 1. Executive Summary

This report documents the entire recovery, device tree development, peripheral bring-up, and current operational state of the AMedia RK3588 LP4 V10 board (`hub-11`). 

The board has successfully transitioned from vendor kernel 5.10.160 to **mainline Linux 6.18 LTS**.
- **Display & Desktop:** Panthor DRM / VOP2 / DW-HDMI-QP outputting 1080p desktop (`startx` / XFCE).
- **USB Subsystem:** All 3 physical USB Type-A ports (two USB 2.0 and one blue USB 3.0) are fully operational and enumerating peripherals.
- **Wired Networking:** Dual Gigabit Ethernet controllers (`gmac0` and `gmac1`) are configured with RTL8211F PHYs; `eth0` is linked up with DHCP IP `192.168.0.13`.
- **Remote Access:** Tailscale is active on `100.88.4.63`.

---

## 2. What Worked & Verified Functional

### 2.1 Display & GPU
- **Controller:** Rockchip VOP2 (`video-output-processor`)
- **HDMI Interface:** Synopsys DesignWare HDMI QP (`dw-hdmi-qp`) on `hdmi0`
- **PHY:** Samsung HDPTX PHY (`hdptxphy0`)
- **GPU Driver:** ARM Mali-G610 Panthor open-source DRM driver (`panthor`)
- **Status:** **VERIFIED WORKING**. Boots cleanly into native 1080p resolution; X11 desktop (`startx`) renders with hardware acceleration.

### 2.2 USB Subsystem (All 3 External Ports)
- **Port 1 (USB 2.0 Type-A):** `usb_host0_ehci` / `usb_host0_ohci` tied to `u2phy2_host`. **WORKING**.
- **Port 3 (USB 2.0 Type-A):** `usb_host1_ehci` / `usb_host1_ohci` tied to `u2phy3_host`. **WORKING**.
- **Port 2 (Blue USB 3.0 Type-A):** `usb_host0_xhci` / `usb_host1_xhci` DWC3 controllers with Type-C / USBDP PHY. **WORKING**.
- **Power Delivery:** VBUS 5V rails mapped and locked active via always-on fixed regulators:
  - `gpio4 RK_PB0`: `vcc5v0_host`
  - `gpio4 RK_PA1`: `vcc5v0_otg`
  - `gpio4 RK_PA7`: `vcc5v0_usb`
- **Root Cause of Initial USB 3.0 Failure:** `CONFIG_PHY_ROCKCHIP_USBDP` and `CONFIG_TYPEC` were initially compiled as loadable kernel modules (`=m`). When booting without an initramfs, the DWC3 controller deferred probe (`-EPROBE_DEFER`). Building them directly into the kernel Image (`=y`) resolved this.

### 2.3 Wired Networking (Dual GMAC Architecture)
- **Controller A (`gmac0` at `0xfe1b0000` / `eth0`):**
  - Mode: `rgmii-rxid`, `clock_in_out = "output"`, `tx_delay = <0x44>`
  - PHY: Realtek RTL8211F Gigabit Ethernet at MDIO address `0x1`
  - Reset GPIO: `gpio4 RK_PB3 GPIO_ACTIVE_LOW` (assert 20 ms, deassert 100 ms)
  - Status: **VERIFIED WORKING**. Connected to LAN, obtained lease `192.168.0.13/24`.
- **Controller B (`gmac1` at `0xfe1c0000` / `eth1`):**
  - Mode: `rgmii-rxid`, `clock_in_out = "output"`, `tx_delay = <0x42>`
  - PHY: Realtek RTL8211F Gigabit Ethernet at MDIO address `0x1`
  - Reset GPIO: `gpio3 RK_PB7 GPIO_ACTIVE_LOW` (assert 20 ms, deassert 100 ms)
  - Status: **ENABLED**. Device node and PHY binding verified in DTB.
- **Root Cause of Initial Ethernet Failure:**
  1. Mainline DTS originally only enabled `gmac1`, leaving `gmac0` disabled. The physical port connected to `gmac0` remained inactive with a solid green hardware LED.
  2. Generic `ethernet-phy-ieee802.3-c22` compatible was used without the specific PHY ID (`ethernet-phy-id001c.c916`). Because the PHY was held in reset during early MDIO bus registration, the bus scan could not read the PHY ID registers over MDIO, resulting in `-ENODEV` (`RTNETLINK answers: No such device` on `ip link set eth0 up`). Explicitly binding `ethernet-phy-id001c.c916` instructs the kernel to instantiate the PHY immediately, drive the reset GPIO lines, and bind the Realtek driver.

### 2.4 Status LED & GPIO Mapping
- **Status LED:** Configured via `pwm-leds` on `pwm8` (`gpio3 RK_PD0`, pin 120) with heartbeat trigger.
- **Resolved Collision:** Initially, `pwm9` attempted to claim `gpio3 RK_PB0` (pin 104), which collided with `gmac1_rx_bus2` (`errorctl pininval 104`). Migrating to `pwm8` cleanly resolved the conflict.

---

## 3. What Did Not Work & Pending Issues

### 3.1 iptables / netfilter Compatibility
- **Symptom:** `iptables v1.8.7 (legacy): can't initialize iptables table 'filter': Table does not exist (do you need to insmod?)`
- **Cause:** Debian 11/12 defaults to the legacy `iptables-legacy` frontend, which expects older `ip_tables.ko` / `iptable_filter.ko` modules. Mainline Linux 6.18 uses the modern `nf_tables` subsystem (`nftables`).
- **Solution:** 
  1. Switch Debian alternatives to the `nft` backend:
     ```bash
     sudo update-alternatives --set iptables /usr/sbin/iptables-nft
     sudo update-alternatives --set iptables-restore /usr/sbin/iptables-nft-restore
     sudo update-alternatives --set iptables-save /usr/sbin/iptables-nft-save
     sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-nft
     sudo update-alternatives --set ip6tables-restore /usr/sbin/ip6tables-nft-restore
     sudo update-alternatives --set ip6tables-save /usr/sbin/ip6tables-nft-save
     ```
  2. Alternatively, build legacy `CONFIG_IP_NF_IPTABLES=y`, `CONFIG_IP_NF_FILTER=y`, `CONFIG_IP_NF_NAT=y` as built-ins.

### 3.2 Dynamic Linker / Symlink Overwrite
- **Symptom:** Subsequent SSH connections immediately terminate with `Connection closed by 192.168.0.13 port 22`, and local commands throw `/usr/bin/sudo: No such file or directory`.
- **Cause:** When extracting `modules.tar.zst` with standard `tar -C / -xf`, GNU `tar` extracted the top-level `lib/` directory directly onto `/`, replacing the UsrMerge symlink `/lib -> usr/lib` with an actual directory. Because the ELF interpreter `/lib/ld-linux-aarch64.so.1` no longer resolves, dynamic binaries cannot start.
- **Immediate Fix:**
  - **From local TTY:** Run the commands by directly invoking the dynamic linker:
    ```bash
    /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 /bin/mv /lib /lib_old
    /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 /bin/ln -s usr/lib /lib
    /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 /bin/cp -rn /lib_old/* /usr/lib/
    /usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 /bin/rm -rf /lib_old
    ```
  - **Or via automated rescue init:** Booting the rescue FIT image automatically detects `/mnt/lib` as a directory, restores `/mnt/lib -> usr/lib`, and relocates modules into `/usr/lib/modules/`.

---

## 4. Key Files & Artifact Reference

| File | Location | Description |
|---|---|---|
| **Board DTS** | `/home/nyx/Projects/hub11-meta/dts/rk3588-hub11.dts` | Mainline DTS with dual GMACs, RTL8211F, USB 3.0, and PWM LED |
| **Kernel Config** | `/home/nyx/Projects/hub11-meta/configs/hub11.config` | Base Kconfig fragment with built-in networking & USBDP PHY |
| **Infra Config** | `/home/nyx/Projects/hub11-meta/configs/hub11_infra.config` | Tailscale, wireguard, cgroups, and container options |
| **Active FIT Image** | `/home/nyx/build/hub11/dist/latest/hub11-boot-6.18.49-dirty.itb` | FIT package containing Image, DTB, and vendor resource.img (61.1 MiB) |
| **Kernel Modules** | `/home/nyx/build/hub11/dist/latest/modules.tar.zst` | Compressed kernel modules for 6.18.49-dirty |
| **Rescue Init C Source** | `/home/nyx/Projects/hub11-meta/recovery-init/recovery_init.c` | Freestanding AArch64 emergency rescue init |

---

## 5. Next Steps

1. Restore `/lib -> usr/lib` on the target board (via dynamic linker one-liner or rescue init).
2. Switch iptables alternatives to `iptables-nft` to enable full Tailscale subnet routing and container packet filtering.
3. Verify Wi-Fi (`brcmfmac` PCIe AP6275P) firmware loading from `/lib/firmware/brcm/`.
4. Proceed with Stage 1 1-week stability soak before formatting partition `p6` for Debian 13 (Trixie).
