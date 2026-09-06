#!/bin/bash
# modules were extracted by build-rootfs.sh; just index them and enable swap/zram units
set -eu
depmod -a "$KREL"
systemctl enable systemd-zram-setup@zram0.service >/dev/null 2>&1 || true
systemctl enable pci-wifi-check.service ssh-hostkeys-regen.service >/dev/null 2>&1
