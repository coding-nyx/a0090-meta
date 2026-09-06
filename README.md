# a0090-meta

Maintenance repo for **hub-11**, an AMedia RK3588 LP4 V10 board (board code
A009 / A0090). It produces and documents the box's whole software stack:
mainline Linux 6.18 LTS built from a pinned stable tag plus a few patches, a
reproducible Debian 13 (trixie) arm64 rootfs, and the recovery material.

## State of the box (2026-09-06)

| item | value |
|---|---|
| kernel | `6.18.49-hub11` on `/dev/mmcblk0p3` (FIT, 64 MiB cap) |
| rootfs | Debian 13 on eMMC `/dev/mmcblk0p6`, PARTUUID `614e0000-0000-4b53-8000-1d28000054a9` |
| scratch | 256 GB microSD `/dev/mmcblk1p1` (label `DATA`) at `/DATA`, UHS-I SDR104 |
| swap | zram, 50 % of RAM, zstd (`systemd-zram-generator`) |
| network | `eth0`/`eth1` GbE, `wlan0` client (BCM43752), Tailscale `100.88.4.63` |
| desktop | lean XFCE, LightDM autologin (docs/desktop.md) |
| hotspot | `wlan1` via vendor bcmdhd (kernel-extra/), see docs/wlan1-ap.md |

The vendor Debian 11 userland is gone; only the vendor boot FIT is archived
(`lab:~/hub11-backups/backup-installed-boot-20260905-2330.fit`).

## Layout

```
KERNEL_TAG                 pinned stable tag (v6.18.49), bumped deliberately
RK_BIN_SHA                 sha256 of the rk3588 first-stage blobs (untouched on p1)
configs/                   Kconfig fragments merged onto arch/arm64 defconfig
dts/rk3588-hub11.dts       board DTS (mainline bindings); -sdhs.dts = SD high-speed fallback
patches/                   applied with git am onto KERNEL_TAG (pci retries, DTB Makefile, bcmdhd hook, es8328 ratio)
kernel-extra/              out-of-tree sources copied into the tree (Rockchip bcmdhd, ported)
fit/hub11-boot.its         FIT: kernel + DTB + resource.img, vendor load-address shape
firmware-blobs/            Wi-Fi/BT/Mali firmware + vendor resource.img, MANIFEST.yaml with sha256
rootfs/                    package lists, overlay/, hooks/, secrets.example/ (secrets/ is gitignored)
scripts/                   build-kernel, build-fit, stage-modules, flash-boot, build-rootfs, verify-drivers
docs/                      rootfs, tailscale, desktop, wlan1-ap, sd-benchmark, history/
```

## Build host

lab (Fedora 44, x86_64, 4 cores: a full kernel build takes about an hour).

```bash
sudo dnf install -y aarch64-linux-gnu-gcc uboot-tools dwarves ncurses-devel \
     elfutils-libelf-devel qemu-user-static debootstrap git rsync zstd
git clone --depth 1 --branch v6.18.49 \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git ~/src/linux-stable-6.18
```

## Kernel: build, stage, flash

```bash
bash scripts/build-kernel.sh          # resets branch hub11/<tag>, git am patches/, copies dts/ + kernel-extra/, builds
bash scripts/build-fit.sh             # ~/build/hub11/dist/<ts>-<krel>/ (self-contained), updates dist/latest
bash scripts/stage-modules.sh ~/build/hub11/dist/latest   # /usr/lib/modules/<krel> + firmware on the box
bash scripts/flash-boot.sh   ~/build/hub11/dist/latest   # p3 backup to lab, flash, readback, reboot
ssh hub-11 'bash -s' < scripts/verify-drivers.sh
```

`HUB11=nyx@100.88.4.63` overrides the SSH target. `HUB11_DTB=rk3588-hub11-sdhs.dtb`
selects the SD high-speed-only DTB if the card misbehaves at SDR104.

The release string is fixed by `CONFIG_LOCALVERSION="-hub11"`; the scripts export
`LOCALVERSION=""` so it is never doubled and never gains `-dirty`. flash-boot
refuses a FIT of 64 MiB or more and refuses when the matching modules are not
staged.

## Rootfs

`sudo -E bash scripts/build-rootfs.sh` → `~/build/hub11/rootfs-dist/latest/`.
Profiles `base gpu xfce` by default, `infra` for the k3s node flavour. No node
keys, host keys or Wi-Fi PSKs are baked in. See docs/rootfs.md.

## Recovery

- Bad kernel: `flash-boot.sh` prints the rollback `dd` for the p3 backup it just made.
- Bricked boot: maskrom (pin in the AV jack while powering on), then
  `rkdeveloptool db ~/hub11-backups/rkbin/rk3588_loader_v1.24.114.bin`,
  `rkdeveloptool wl 32768 <p3 backup .fit>`, `rkdeveloptool rd`. The loader and
  the rkbin blobs live on lab, not only on the SD card. Details in RUNBOOK.md.
- Tailscale identity after a reflash: docs/tailscale.md.

## Bumping the kernel

Edit `KERNEL_TAG`, run the three build scripts. `kernel-extra/` (bcmdhd) is the
part most likely to break on a new tag; fix it there, keep the fix in its README.
