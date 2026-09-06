# rootfs/secrets/ (gitignored)

Files applied by `scripts/build-rootfs.sh` at build time, never committed:

| file | purpose |
|---|---|
| `nope_5g.nmconnection` | NetworkManager keyfile for the home Wi-Fi (contains the PSK). Copy from hub-11 `/etc/NetworkManager/system-connections/`. |
| `authorized_keys` | SSH public keys for user `nyx`. |
| `hub11-ap.psk`, `hub11-ap.nmconnection` | hotspot secret (only used with `rootfs/overlay-optional/wlan1-ap/`). |

The Tailscale node key is **not** a build input. It lives only on hub-11 and in
`lab:~/hub11-backups/tailscaled.state`; see docs/tailscale.md.
