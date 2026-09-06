# hub-11 RUNBOOK

## Board identity

AMedia RK3588 LP4 V10 (A009), 4x A76 + 4x A55, 3.8 GiB LPDDR4, 32 GB eMMC,
256 GB microSD, 2x GbE (SoC GMAC1 `eth0` + RTL8168 PCIe `eth1`), Ampak AP6275P
(BCM43752 Wi-Fi 6 PCIe + BCM4362A2 BT UART), Mali-G610 (panthor), 3-core NPU
(rocket), HDMI out + HDMI in. Console `ttyS2` 1500000n8.

## Partition map (GPT, eMMC `mmcblk0`)

```
p1  uboot     4M   untouched (vendor U-Boot + rkbin first stage, see RK_BIN_SHA)
p2  misc      4M   untouched
p3  boot     64M   our FIT (hub11-boot-<krel>.itb), sector 32768
p4  recovery 128M  untouched vendor
p5  backup   32M   untouched vendor
p6  rootfs   28.7G Debian 13, PARTUUID 614e0000-0000-4b53-8000-1d28000054a9
mmcblk1p1  DATA  238G  ext4, LABEL=DATA, mounted /DATA (fstab, nofail)
```

## Routine kernel update

1. `bash scripts/build-kernel.sh && bash scripts/build-fit.sh`
2. `bash scripts/stage-modules.sh ~/build/hub11/dist/latest`
3. `bash scripts/flash-boot.sh ~/build/hub11/dist/latest` (backs up p3 to
   `~/hub11-backups/backup-installed-boot-<ts>.fit`, verifies, flashes, reads
   back, reboots)
4. `ssh hub-11 'bash -s' < scripts/verify-drivers.sh` must print `FAIL=0`
5. `ssh hub-11 'sudo rm -rf /usr/lib/modules/<old krel>'` once happy

## Rollback

Previous FIT (the backup flash-boot made):

```
scp ~/hub11-backups/backup-installed-boot-<ts>.fit hub-11:/tmp/restore.fit
ssh hub-11 'sudo dd if=/tmp/restore.fit of=/dev/mmcblk0p3 bs=4M conv=fsync && sudo reboot'
```

Keep the matching `/usr/lib/modules/<krel>` on the box until the new kernel is
verified, or the rolled-back kernel comes up without modules.

The factory 5.10 boot FIT (`backup-installed-boot-20260905-2330.fit`, sha
`62a04243…`) boots the vendor kernel only; the vendor userland no longer exists,
so this is a last resort to reach a console, not a working system.

## Maskrom recovery (worst case)

1. Power off. Insert a non-conductive pin into the AV jack (recovery button),
   power on, hold 3 s. `lsusb` on lab shows `2207:350b`.
2. `rkdeveloptool db ~/hub11-backups/rkbin/rk3588_loader_v1.24.114.bin`
3. `rkdeveloptool wl 32768 ~/hub11-backups/backup-installed-boot-<ts>.fit`
4. `rkdeveloptool rd`

`~/hub11-backups/rkbin/` holds every rk3588 blob from the vendor rkbin tree plus
`boot_merger` and `RKBOOT/RK3588MINIALL.ini` used to build the loader.

## Rootfs reinstall

docs/rootfs.md (build, validate in nspawn, deploy, identity restore).

## Storage

- `/DATA` is the microSD, mounted by label with `nofail`; the box boots without it.
- Swap is zram only (`/etc/systemd/zram-generator.conf`, `/etc/sysctl.d/90-zram.conf`).
- Benchmark and card details: docs/sd-benchmark.md.

## Networking

- NetworkManager owns everything (ifupdown disabled). `nope_5g` pinned to `wlan0`.
- Tailscale identity: docs/tailscale.md. The node key is on the box and in
  `~/hub11-backups/tailscaled.state` only.
- Regulatory db uses the upstream-signed alternative (Debian's signature is
  rejected by a mainline kernel).
- Hotspot / wlan1: docs/wlan1-ap.md.

## Backups on lab (`~/hub11-backups`, mode 700)

| file | what |
|---|---|
| `backup-installed-boot-20260905-2330.fit` | factory p3 (vendor 5.10 kernel) |
| `backup-installed-boot-<ts>.fit` | p3 before each flash |
| `tailscaled.state` | node identity (0600) |
| `ssh_host_keys/` | vendor-era host keys (obsolete after the Trixie install) |
| `rkbin/` | first-stage blobs + maskrom loader |
| `a0090-meta-pre-rewrite-<date>.bundle` | repo history before the 2026-09-06 rewrite |

## Maintenance cadence

- Monthly: bump `KERNEL_TAG` to the newest 6.18.y, rebuild, flash, verify.
- After each kernel bump: re-check `kernel-extra/` builds (bcmdhd port).
- Quarterly: `sudo apt full-upgrade` on the box, rebuild the rootfs tarball so a
  reflash does not fall behind.
