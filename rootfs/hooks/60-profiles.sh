#!/bin/bash
# optional package profiles: gpu, xfce, infra (lists staged by build-rootfs.sh)
set -eu
apt-get update -qq
for p in $ROOTFS_PROFILES; do
  [ "$p" = base ] && continue
  list=/tmp/build/packages-$p.list; [ -s "$list" ] || continue
  echo ">> profile $p"
  xargs -a "$list" apt-get install -y -q --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold
done
if [ -x /usr/sbin/lightdm ]; then
  systemctl enable lightdm >/dev/null 2>&1
  systemctl set-default graphical.target >/dev/null 2>&1
  getent group autologin >/dev/null || groupadd -r autologin
  usermod -aG autologin nyx
else
  systemctl set-default multi-user.target >/dev/null 2>&1
fi
