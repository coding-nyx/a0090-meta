#!/bin/bash
# Tailscale package + repo, enabled, with NO node identity in the image.
set -eu
apt-get update -qq
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list
apt-get update -qq
apt-get install -y -q --no-install-recommends -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold tailscale
systemctl enable tailscaled >/dev/null 2>&1
rm -f /var/lib/tailscale/tailscaled.state
