#!/usr/bin/env bash
# scripts/stage-modules.sh — install a dist's kernel modules + firmware on hub-11
# BEFORE flashing its FIT (flash-boot.sh refuses otherwise).
#
# The modules tarball is rooted at <krel>/ and is only ever extracted into a
# scratch dir, then copied into /usr/lib/modules/<krel>/. Never `tar -C /`:
# on a usr-merged system that once replaced the /lib symlink and bricked
# the userland.
#
# Usage:  bash scripts/stage-modules.sh ~/build/hub11/dist/latest
set -euo pipefail

HUB11=${HUB11:-hub-11}
DISTDIR="${1:?usage: $0 <dist dir>}"
DISTDIR=$(readlink -f "$DISTDIR")
KREL=$(cat "$DISTDIR/KREL")
test -f "$DISTDIR/modules.tar.zst" || { echo "FATAL: no modules.tar.zst in $DISTDIR"; exit 1; }

TOP=$(zstd -dc "$DISTDIR/modules.tar.zst" | tar -tf - | cut -d/ -f1 | sort -u)
[ "$TOP" = "$KREL" ] || { echo "FATAL: tarball top-level is '$TOP', expected '$KREL'"; exit 1; }

echo "=== push modules + firmware for $KREL to $HUB11 ==="
ssh "$HUB11" "rm -rf /tmp/modstage && mkdir -p /tmp/modstage/fw"
scp -q "$DISTDIR/modules.tar.zst" "$HUB11:/tmp/modstage/"
scp -qr "$DISTDIR/firmware/." "$HUB11:/tmp/modstage/fw/"

ssh "$HUB11" "
  set -e
  cd /tmp/modstage
  zstd -dc modules.tar.zst | tar -xf -
  test -f '$KREL/modules.dep'
  sudo -n mkdir -p /usr/lib/modules/$KREL
  sudo -n cp -a '$KREL/.' /usr/lib/modules/$KREL/
  sudo -n depmod -a $KREL
  sudo -n mkdir -p /usr/lib/firmware
  sudo -n cp -a fw/. /usr/lib/firmware/
  cd / && rm -rf /tmp/modstage
  echo \"OK: /usr/lib/modules/$KREL (\$(find /usr/lib/modules/$KREL -name '*.ko*' | wc -l) modules), firmware refreshed\"
"
