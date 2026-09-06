#!/bin/bash
# NetworkManager owns the network; regdb signed with the upstream key so the
# mainline kernel accepts it; wlan1 AP bits are optional (see overlay-optional).
set -eu
systemctl enable NetworkManager systemd-timesyncd avahi-daemon ssh >/dev/null 2>&1
systemctl disable networking >/dev/null 2>&1 || true
if [ -e /lib/firmware/regulatory.db-upstream ]; then
  update-alternatives --set regulatory.db /lib/firmware/regulatory.db-upstream >/dev/null
  ln -sf regulatory.db.p7s-upstream /lib/firmware/regulatory.db.p7s
fi
chmod 600 /etc/NetworkManager/system-connections/* 2>/dev/null || true
