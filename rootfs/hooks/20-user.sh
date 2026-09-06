#!/bin/bash
# user nyx with passwordless sudo and hardware groups; ssh key from secrets
set -eu
id nyx >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,dialout,audio,video,render,netdev,plugdev nyx
passwd -l root >/dev/null
install -d -m 440 /etc/sudoers.d
echo 'nyx ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/90-user-nyx; chmod 440 /etc/sudoers.d/90-user-nyx
if [ -f /tmp/authkeys/authorized_keys ]; then
  install -d -m 700 -o nyx -g nyx /home/nyx/.ssh
  install -m 600 -o nyx -g nyx /tmp/authkeys/authorized_keys /home/nyx/.ssh/authorized_keys
fi
# desktop config from /etc/skel for the existing user too
if [ -d /etc/skel/.config ]; then cp -a /etc/skel/.config /home/nyx/ 2>/dev/null || true; chown -R nyx:nyx /home/nyx/.config; fi
