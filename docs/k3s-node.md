# hub-11 as a k3s node

hub-11 is a worker in the LAN k3s cluster whose server is `lab`
(`https://192.168.0.9:6443`, flannel vxlan over the LAN). It joins over its
**LAN interface `wlan0` (192.168.0.8)**, like the other workers.

## Why not the Tailscale IP

hub-11 is the only would-be Tailscale node in a LAN flannel cluster. Tailscale's
interface is 1280 MTU, so flannel there is 1230 while the rest of the cluster is
1450. Pods then pass small packets (ping, node shows Ready) but drop real
traffic (DNS/HTTP fail). Tested and confirmed 2026-09-06. The cluster data plane
is all on one LAN, so Tailscale buys nothing here but MTU breakage. Tailscale
stays up for SSH/management (100.88.4.63); only the k3s data plane is on wlan0.
If the whole cluster ever moves to Tailscale, set flannel MTU 1230 on every node.

## Live config (on the box)

`/etc/systemd/system/k3s-agent.service` ExecStart pins:
`--node-ip=192.168.0.8 --node-external-ip=192.168.0.8 --flannel-iface=wlan0`
plus node labels (arch/soc/has-npu/has-gpu). A drop-in
`k3s-agent.service.d/10-wait-wlan0.conf` waits for 192.168.0.8 before start.
Give hub-11 a **DHCP reservation** for 192.168.0.8 so node-ip stays valid.

## Reproducible (rootfs `infra` profile)

Build the rootfs with infra included:
`sudo -E ROOTFS_PROFILES="base gpu xfce infra" bash scripts/build-rootfs.sh`

- `rootfs/overlay/etc/rancher/k3s/config.yaml` — flannel-iface, node-ip, labels.
- `rootfs/overlay/usr/local/sbin/hub11-k3s-join` + `hub11-k3s-join.service` —
  first boot installs the pinned k3s (v1.36.3+k3s1) as an agent and joins,
  using `/etc/rancher/k3s/join.env`.
- `rootfs/secrets/k3s-token` (gitignored) → rendered into join.env at build time;
  server URL defaults to `https://192.168.0.9:6443`.

## Verify

```
ssh nyx@100.88.4.63 systemctl is-active k3s-agent      # active
sudo k3s kubectl get node hub-11 -o wide               # Ready, INTERNAL-IP 192.168.0.8
# pod test: schedule busybox on hub-11, expect PING/HTTP/DNS OK
```
