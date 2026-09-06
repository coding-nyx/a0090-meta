#!/usr/bin/env bash
# scripts/build-rootfs.sh — reproducible Debian 13 (trixie) arm64 rootfs for hub-11.
#
# Runs on lab (Fedora, qemu-user-static registered in binfmt). Needs sudo.
#
#   sudo -E bash scripts/build-rootfs.sh                 # base + gpu + xfce profiles
#   sudo -E ROOTFS_PROFILES="base gpu" bash scripts/build-rootfs.sh
#   sudo -E DIST=~/build/hub11/dist/<ts>-<krel> bash scripts/build-rootfs.sh
#
# Inputs (all in this repo):
#   rootfs/packages-base.txt     debootstrap --include list (always)
#   rootfs/packages-gpu.txt      mesa userspace                    (profile gpu)
#   rootfs/packages-xfce.txt     lean XFCE desktop                 (profile xfce)
#   rootfs/packages-infra.txt    k3s / netfilter / wireguard tools (profile infra)
#   rootfs/overlay/              copied verbatim over the chroot before hooks
#   rootfs/hooks/NN-*.sh         run inside the chroot, in order
#   rootfs/secrets/              gitignored; Wi-Fi profile, authorized_keys (see secrets.example/)
#   $DIST (default dist/latest)  kernel modules + firmware for the running kernel
#
# Output: ~/build/hub11/rootfs-dist/<ts>-<krel>/hub11-trixie-arm64.tar.zst + SHA256SUMS + MANIFEST.txt
#
# What is deliberately NOT in the tarball: Tailscale node state, SSH host keys,
# machine-id, apt lists, logs. See docs/rootfs.md and docs/tailscale.md.
set -euo pipefail

META="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB=${LAB:-/home/nyx}
DIST=${DIST:-"$LAB/build/hub11/dist/latest"}
WORK=${WORK:-"$LAB/build/hub11/rootfs-work"}
OUTROOT=${OUTROOT:-"$LAB/build/hub11/rootfs-dist"}
SUITE=${SUITE:-trixie}
MIRROR=${MIRROR:-http://deb.debian.org/debian}
ROOTFS_PROFILES=${ROOTFS_PROFILES:-"base gpu xfce"}
ALLOW_MISSING_SECRETS=${ALLOW_MISSING_SECRETS:-0}
OWNER=${SUDO_USER:-nyx}

[ "$(id -u)" -eq 0 ] || { echo "FATAL: run with sudo -E"; exit 1; }
for t in debootstrap qemu-aarch64-static zstd tar chroot; do command -v "$t" >/dev/null || { echo "FATAL: $t missing"; exit 1; }; done
DIST=$(readlink -f "$DIST")
test -f "$DIST/KREL" || { echo "FATAL: $DIST has no KREL (run build-fit.sh first)"; exit 1; }
KREL=$(cat "$DIST/KREL")
test -f "$DIST/modules.tar.zst" || { echo "FATAL: $DIST/modules.tar.zst missing"; exit 1; }

pkgs() { grep -vhE '^\s*(#|$)' "$@" | tr '\n' ',' | sed 's/,$//'; }

ROOT="$WORK/root"
rm -rf "$WORK"; mkdir -p "$ROOT"
cleanup() { for m in dev/pts dev proc sys; do umount -l "$ROOT/$m" 2>/dev/null || true; done; }
trap cleanup EXIT

echo ">>> debootstrap $SUITE arm64 (base profile)"
debootstrap --arch=arm64 --variant=minbase \
  --components=main,contrib,non-free,non-free-firmware \
  --exclude=ifupdown \
  --include="$(pkgs "$META/rootfs/packages-base.txt")" \
  "$SUITE" "$ROOT" "$MIRROR" >"$WORK/debootstrap.log" 2>&1 \
  || { tail -30 "$WORK/debootstrap.log"; echo "FATAL: debootstrap failed"; exit 1; }

echo ">>> overlay"
cp -a "$META/rootfs/overlay/." "$ROOT/"
chmod 600 "$ROOT"/etc/NetworkManager/system-connections/* 2>/dev/null || true

echo ">>> kernel $KREL modules + firmware from $DIST"
mkdir -p "$ROOT/usr/lib/modules" "$ROOT/usr/lib/firmware"
zstd -dc "$DIST/modules.tar.zst" | tar -C "$ROOT/usr/lib/modules" -xf -
test -f "$ROOT/usr/lib/modules/$KREL/modules.dep"
cp -a "$DIST/firmware/." "$ROOT/usr/lib/firmware/"

echo ">>> secrets"
SEC="$META/rootfs/secrets"
if [ -f "$SEC/nope_5g.nmconnection" ]; then
  install -m 600 "$SEC/nope_5g.nmconnection" "$ROOT/etc/NetworkManager/system-connections/nope_5g.nmconnection"
  grep -q '^interface-name=wlan0' "$ROOT/etc/NetworkManager/system-connections/nope_5g.nmconnection" \
    || sed -i '/^\[connection\]/a interface-name=wlan0' "$ROOT/etc/NetworkManager/system-connections/nope_5g.nmconnection"
elif [ "$ALLOW_MISSING_SECRETS" != 1 ]; then echo "FATAL: $SEC/nope_5g.nmconnection missing (ALLOW_MISSING_SECRETS=1 to skip)"; exit 1; fi
if [ -f "$SEC/authorized_keys" ]; then
  install -d -m 700 "$ROOT/tmp/authkeys"; install -m 600 "$SEC/authorized_keys" "$ROOT/tmp/authkeys/authorized_keys"
elif [ "$ALLOW_MISSING_SECRETS" != 1 ]; then echo "FATAL: $SEC/authorized_keys missing"; exit 1; fi

echo ">>> chroot hooks (profiles: $ROOTFS_PROFILES)"
mount -t proc proc "$ROOT/proc"; mount -t sysfs sys "$ROOT/sys"
mount --bind /dev "$ROOT/dev"; mount --bind /dev/pts "$ROOT/dev/pts"
install -m 644 /etc/resolv.conf "$ROOT/etc/resolv.conf.build"; mv -f "$ROOT/etc/resolv.conf.build" "$ROOT/etc/resolv.conf"
# No service starts inside the chroot; overlay config files win over package defaults.
printf '#!/bin/sh\nexit 101\n' > "$ROOT/usr/sbin/policy-rc.d"; chmod 755 "$ROOT/usr/sbin/policy-rc.d"
mkdir -p "$ROOT/tmp/build"
for p in $ROOTFS_PROFILES; do
  f="$META/rootfs/packages-$p.txt"; [ "$p" = base ] && continue
  test -f "$f" || { echo "FATAL: no $f"; exit 1; }
  grep -vhE '^\s*(#|$)' "$f" > "$ROOT/tmp/build/packages-$p.list"
done
cp "$META"/rootfs/hooks/*.sh "$ROOT/tmp/build/"
for h in "$ROOT"/tmp/build/*.sh; do
  echo "    hook $(basename "$h")"
  KREL="$KREL" ROOTFS_PROFILES="$ROOTFS_PROFILES" DEBIAN_FRONTEND=noninteractive \
    chroot "$ROOT" /bin/bash -e "/tmp/build/$(basename "$h")" >"$WORK/hook-$(basename "$h" .sh).log" 2>&1 \
    || { tail -30 "$WORK/hook-$(basename "$h" .sh).log"; echo "FATAL: hook $(basename "$h") failed"; exit 1; }
done
rm -rf "$ROOT/tmp/build" "$ROOT/tmp/authkeys" "$ROOT/usr/sbin/policy-rc.d"
cleanup; trap - EXIT

echo ">>> secret-leak gate"
test ! -e "$ROOT/var/lib/tailscale/tailscaled.state" || { echo "FATAL: tailscaled.state in rootfs"; exit 1; }
[ -z "$(ls "$ROOT"/etc/ssh/ssh_host_* 2>/dev/null)" ] || { echo "FATAL: ssh host keys in rootfs"; exit 1; }
LEAKS=$(grep -rlE 'psk=|PRIVATE KEY|tskey-' "$ROOT/etc" "$ROOT/root" "$ROOT/home" 2>/dev/null \
        | grep -v '/etc/NetworkManager/system-connections/' || true)
[ -z "$LEAKS" ] || { echo "FATAL: secret-looking content outside NM profiles:"; echo "$LEAKS"; exit 1; }

TS=$(date -u +%Y%m%d-%H%M)
OUT="$OUTROOT/$TS-$KREL"; mkdir -p "$OUT"
echo ">>> tar -> $OUT/hub11-trixie-arm64.tar.zst"
tar --numeric-owner --xattrs --acls -C "$ROOT" -cf - . | zstd -q -T0 -19 -o "$OUT/hub11-trixie-arm64.tar.zst"
{
  echo "built:        $(date -u +%FT%TZ) on $(hostname)"
  echo "repo:         $(git -C "$META" rev-parse --short HEAD 2>/dev/null || echo n/a) $(git -C "$META" status --porcelain 2>/dev/null | wc -l) dirty files"
  echo "suite:        $SUITE ($MIRROR)"
  echo "kernel:       $KREL from $DIST"
  echo "profiles:     $ROOTFS_PROFILES"
  echo "debootstrap:  $(debootstrap --version 2>/dev/null | head -1)"
  echo "include:      $(pkgs "$META/rootfs/packages-base.txt")"
  echo; echo "== dpkg -l =="; chroot "$ROOT" dpkg-query -W -f='${Package} ${Version}\n'
} > "$OUT/MANIFEST.txt"
(cd "$OUT" && sha256sum hub11-trixie-arm64.tar.zst MANIFEST.txt > SHA256SUMS)
chown -R "$OWNER:" "$OUTROOT"
ln -sfn "$TS-$KREL" "$OUTROOT/latest"
rm -rf "$WORK"
echo ""
echo "OK: $OUT"
du -h "$OUT/hub11-trixie-arm64.tar.zst" | cut -f1
