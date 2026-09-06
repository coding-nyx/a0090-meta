# rootfs/secrets/ (gitignored)

Files applied by `scripts/build-rootfs.sh` at build time, never committed:

| file | purpose |
|---|---|
| `nope_5g.nmconnection` | NetworkManager keyfile for the home Wi-Fi (contains the PSK). Copy from hub-11 `/etc/NetworkManager/system-connections/`. |
| `authorized_keys` | SSH public keys for user `nyx`. |
| `hub11-ap.psk`, `hub11-ap.nmconnection` | hotspot secret (only used with `rootfs/overlay-optional/wlan1-ap/`). |

The Tailscale node key is **not** a build input. It lives only on hub-11 and in
`lab:~/hub11-backups/tailscaled.state`; see docs/tailscale.md.

## k3s-token (infra profile)

`rootfs/secrets/k3s-token` — the cluster join token, from the k3s server:
`sudo cat /var/lib/rancher/k3s/server/node-token` on lab. Used only when the
`infra` profile is built; rendered into `/etc/rancher/k3s/join.env` and consumed
by the first-boot `hub11-k3s-join.service`. Server URL defaults to
`https://192.168.0.9:6443` (override with `K3S_URL=` when building).
