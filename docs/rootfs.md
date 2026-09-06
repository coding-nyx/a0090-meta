# Rootfs: build, validate, deploy

hub-11 runs Debian 13 (trixie) arm64 on eMMC `/dev/mmcblk0p6`
(PARTUUID `614e0000-0000-4b53-8000-1d28000054a9`), installed 2026-09-06. The
vendor Debian 11 userland is gone; nothing in this repo can bring it back
(only the vendor *boot* FIT is archived, see RUNBOOK).

## Build (on lab)

```
bash scripts/build-kernel.sh && bash scripts/build-fit.sh      # kernel first: the rootfs embeds its modules
sudo -E bash scripts/build-rootfs.sh                            # profiles: base gpu xfce
sudo -E ROOTFS_PROFILES="base gpu infra" bash scripts/build-rootfs.sh   # headless k3s node flavour
```

Output: `~/build/hub11/rootfs-dist/<ts>-<krel>/hub11-trixie-arm64.tar.zst`,
`SHA256SUMS`, `MANIFEST.txt` (include list, full package list, kernel, repo
commit). `latest` symlink points at the newest.

Inputs, all in `rootfs/`:

| path | role |
|---|---|
| `packages-base.txt` | debootstrap `--include` (minbase, `--exclude=ifupdown`) |
| `packages-gpu.txt`, `packages-xfce.txt`, `packages-infra.txt` | opt-in profiles |
| `overlay/` | files copied verbatim: fstab, zram, sysctl, regdom, first-boot units, `/etc/skel` desktop config, greeter, wallpaper |
| `hooks/NN-*.sh` | run in the chroot in order: locale/tz, user, tailscale, network, modules, profiles, cleanup |
| `secrets/` (gitignored) | `nope_5g.nmconnection`, `authorized_keys` — see `secrets.example/README.md` |
| `overlay-optional/wlan1-ap/` | hotspot bits, not installed (docs/wlan1-ap.md) |

Kernel modules and firmware come from `~/build/hub11/dist/latest` (override with
`DIST=`), so the tarball boots standalone with the FIT of the same `KREL`.

Deliberately absent from the tarball, enforced by the leak gate at the end of
the script: Tailscale node state, SSH host keys (regenerated on first boot by
`ssh-hostkeys-regen.service`), `machine-id`, apt lists, logs, shell history.

## Validate without flashing

On lab (fast):

```
R=~/build/hub11/rootfs-work/root      # only while WORK is kept; or extract the tarball somewhere
sudo systemctl --root=$R is-enabled tailscaled NetworkManager lightdm systemd-zram-setup@zram0
sudo tar -tf <tarball> | grep -E 'tailscaled.state|ssh_host_' && echo LEAK
```

On hub-11 with the SD card mounted (boots the image as a container):

```
sudo mkdir -p /DATA/rootfs-test && sudo tar -C /DATA/rootfs-test --zstd -xf /DATA/artifacts/hub11-trixie-arm64.tar.zst
sudo systemd-nspawn -D /DATA/rootfs-test -b --private-network -M hub11test
#   ... login as nyx, check `systemctl --failed`, `dpkg -l | wc -l`, then:
sudo machinectl poweroff hub11test; sudo rm -rf /DATA/rootfs-test
```

`--private-network` keeps the container's tailscaled from ever reaching the
control plane.

## Deploy onto p6

Prerequisites: `/DATA` mounted (the SD card), the tarball and its SHA256SUMS in
`/DATA/artifacts/`, the matching FIT already on p3, and a UART console or the
patience to recover via maskrom if it goes wrong.

1. Snapshot the current root and identity (mandatory):
   ```
   TS=$(date -u +%Y%m%d-%H%M)
   sudo mkdir -p /DATA/artifacts/identity-$TS && sudo cp -a /var/lib/tailscale/tailscaled.state /etc/ssh/ssh_host_* /DATA/artifacts/identity-$TS/ && sudo chmod 600 /DATA/artifacts/identity-$TS/*
   sudo tar --one-file-system --numeric-owner -C / -cf - . | zstd -T0 > /DATA/artifacts/p6-root-$TS.tar.zst
   ```
2. Swap the userland in place from a RAM copy of busybox (this is how the
   2026-09-06 install was done): copy `/bin/busybox` to `/run/bin/sh` and
   friends, `cd /`, move every top-level directory except `/run`, `/dev`,
   `/proc`, `/sys`, `/tmp`, `/DATA` into `/old_root`, extract the tarball with
   the busybox `tar`, `sync`, restore `/var/lib/tailscale/tailscaled.state`
   from the identity snapshot, `sync`, then `reboot -f`. Do it from a script in
   `/run` so nothing under the old root is needed once it starts.
3. First boot: SSH host keys regenerate, tailscaled comes up with the restored
   identity, zram and `/DATA` are in fstab. Run `scripts/verify-drivers.sh`.
4. Remove `/old_root` after verification (`sudo rm -rf /old_root`); it is the
   only rollback of the previous userland besides the tar snapshot.

A cleaner installer-initramfs path (boot once from p4, extract, reboot) is
still the intended long-term mechanism and is not built yet.
