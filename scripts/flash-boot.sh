#!/usr/bin/env bash
# scripts/flash-boot.sh — flash a dist directory's FIT to /dev/mmcblk0p3 on hub-11.
#
# PRE-FLIGHT (mandatory, cannot be skipped):
#   1. streams the current p3 to lab:~/hub11-backups/backup-installed-boot-<ts>.fit
#      and verifies its sha256 against the device (no /DATA needed on the box);
#   2. refuses unless /usr/lib/modules/<krel> already exists on the box
#      (run scripts/stage-modules.sh first);
#   3. refuses a FIT >= 64 MiB.
# After dd it reads p3 back and compares the hash before rebooting.
#
# Usage (from lab, over Tailscale):
#   bash scripts/flash-boot.sh ~/build/hub11/dist/latest
#   bash scripts/flash-boot.sh /path/to/hub11-boot-6.18.49-hub11.itb
set -euo pipefail

HUB11=${HUB11:-hub-11}
LAB=${LAB:-/home/nyx}
BACKUP_DIR="$LAB/hub11-backups"
ARG="${1:?usage: $0 <dist dir | hub11-boot-X.itb>}"

if [ -d "$ARG" ]; then
  ITB=$(ls "$ARG"/hub11-boot-*.itb | head -1)
else
  ITB="$ARG"
fi
test -f "$ITB" || { echo "FATAL: $ITB not found"; exit 1; }
ITB=$(readlink -f "$ITB")
NAME=$(basename "$ITB")
KREL=${NAME#hub11-boot-}; KREL=${KREL%.itb}
SIZE=$(stat -c%s "$ITB")
[ "$SIZE" -lt 67108864 ] || { echo "FATAL: $NAME is $SIZE bytes, >= 64 MiB p3"; exit 1; }
ITB_SHA=$(sha256sum "$ITB" | cut -d' ' -f1)

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

echo "=== PRE-FLIGHT 1/3: modules for $KREL present on $HUB11? ==="
ssh "$HUB11" "test -f /usr/lib/modules/$KREL/modules.dep" \
  || { echo "FATAL: /usr/lib/modules/$KREL missing on $HUB11 — run scripts/stage-modules.sh first"; exit 1; }
echo "ok"

echo "=== PRE-FLIGHT 2/3: stream backup of current p3 to lab ==="
TS=$(date -u +%Y%m%d-%H%M)
BK="$BACKUP_DIR/backup-installed-boot-$TS.fit"
ssh "$HUB11" "sudo -n dd if=/dev/mmcblk0p3 bs=4M status=none" > "$BK"
[ "$(stat -c%s "$BK")" -eq 67108864 ] || { echo "FATAL: backup is not 64 MiB"; exit 1; }
DEV_SHA=$(ssh "$HUB11" "sudo -n sha256sum /dev/mmcblk0p3" | cut -d' ' -f1)
BK_SHA=$(sha256sum "$BK" | cut -d' ' -f1)
[ "$DEV_SHA" = "$BK_SHA" ] || { echo "FATAL: backup hash mismatch"; exit 1; }
echo "ok: $BK ($BK_SHA)"

echo "=== PRE-FLIGHT 3/3: push $NAME ==="
scp -q "$ITB" "$HUB11:/tmp/$NAME"
REMOTE_SHA=$(ssh "$HUB11" "sha256sum /tmp/$NAME" | cut -d' ' -f1)
[ "$REMOTE_SHA" = "$ITB_SHA" ] || { echo "FATAL: upload corrupted"; exit 1; }
echo "ok"

echo "=== FLASH ==="
ssh "$HUB11" "
  set -e
  sudo -n dd if=/tmp/$NAME of=/dev/mmcblk0p3 bs=4M conv=fsync status=none
  sync
  RB=\$(sudo -n dd if=/dev/mmcblk0p3 bs=4M iflag=count_bytes count=$SIZE status=none | sha256sum | cut -d' ' -f1)
  [ \"\$RB\" = \"$ITB_SHA\" ] || { echo 'FATAL: readback hash mismatch — NOT rebooting'; exit 1; }
  rm -f /tmp/$NAME
  echo 'OK: p3 = $NAME (readback verified). Rebooting in 3s...'
  sleep 3
  sudo -n systemctl reboot
" || { echo "Flash step failed; p3 backup is $BK"; exit 1; }

echo ""
echo "=== Rollback if needed ==="
echo "  scp $BK $HUB11:/tmp/restore.fit"
echo "  ssh $HUB11 'sudo dd if=/tmp/restore.fit of=/dev/mmcblk0p3 bs=4M conv=fsync && sudo reboot'"
echo "  (maskrom: rkdeveloptool db ~/hub11-backups/rkbin/rk3588_loader_v1.24.114.bin; wl 32768 $BK; rd)"
