#!/bin/bash
# locale, timezone, hostname sanity
set -eu
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
echo "en_IN UTF-8" >> /etc/locale.gen
locale-gen >/dev/null
update-locale LANG=en_US.UTF-8
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
echo "Asia/Kolkata" > /etc/timezone
echo hub-11 > /etc/hostname
grep -q hub-11 /etc/hosts || printf '127.0.0.1\tlocalhost\n127.0.1.1\thub-11\n::1\tlocalhost ip6-localhost ip6-loopback\n' > /etc/hosts
