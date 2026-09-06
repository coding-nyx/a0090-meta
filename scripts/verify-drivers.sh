#!/usr/bin/env bash
# scripts/verify-drivers.sh — post-boot smoke test, run ON hub-11.
#
#   scp scripts/verify-drivers.sh hub-11:/tmp/ && ssh hub-11 'bash /tmp/verify-drivers.sh'
#
# Exit 0 only if every check passes. Needs passwordless sudo for a few reads.
set -u
export PATH=$PATH:/usr/sbin:/sbin

PASS=0; FAIL=0
check() {
  local name="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    printf "  \033[32mPASS\033[0m  %s\n" "$name"; PASS=$((PASS+1))
  else
    printf "  \033[31mFAIL\033[0m  %s  (%s)\n" "$name" "$cmd"; FAIL=$((FAIL+1))
  fi
}

echo "=== Kernel ==="
check "kernel = 6.18.N-hub11 (no -dirty)" "uname -r | grep -qE '^6\.18\.[0-9]+-hub11$'"
check "modules dir matches running kernel" "test -f /usr/lib/modules/\$(uname -r)/modules.dep"
check "/proc/config.gz present" "test -r /proc/config.gz"

echo "=== GPU / display ==="
check "panthor loaded" "lsmod | grep -q '^panthor'"
check "/dev/dri/renderD128" "test -c /dev/dri/renderD128"
check "rockchip-drm bound (built-in)" "ls /sys/bus/platform/drivers/rockchip-drm/ | grep -q display-subsystem"
check "HDMI-A-1 connector" "ls -d /sys/class/drm/card*-HDMI-A-1"

echo "=== NPU (rocket) ==="
check "rocket loaded" "lsmod | grep -q '^rocket'"
check "/dev/accel/accel0" "test -c /dev/accel/accel0"

echo "=== Wired networking ==="
check "eth0 (SoC GMAC)" "ip link show eth0 | grep -q link/ether"
check "eth1 (RTL8168 via r8169)" "readlink /sys/class/net/eth1/device/driver | grep -q r8169"

echo "=== Wi-Fi (brcmfmac 43752) ==="
check "brcmfmac drives wlan0" "readlink /sys/class/net/wlan0/device/driver | grep -q brcmfmac"
check "wlan0 associated" "iw dev wlan0 link | grep -q SSID"
check "regulatory.db accepted" "! sudo -n dmesg | grep -q 'regulatory.db is malformed'"

echo "=== Bluetooth ==="
check "hci0 present" "test -d /sys/class/bluetooth/hci0"
check "controller powered" "bluetoothctl show | grep -q 'Powered: yes'"

echo "=== Storage ==="
check "eMMC mmcblk0" "test -d /sys/block/mmcblk0"
check "root on p6" "findmnt -n -o SOURCE / | grep -q mmcblk0p6"
check "microSD mmcblk1" "test -d /sys/block/mmcblk1"
check "microSD in UHS/SDR104 (set HUB11_SD_HS=1 to accept high-speed)" \
      "if [ \"\${HUB11_SD_HS:-0}\" = 1 ]; then sudo -n cat /sys/kernel/debug/mmc1/ios | grep -qiE 'sd high-speed|SDR104'; else sudo -n cat /sys/kernel/debug/mmc1/ios | grep -q SDR104; fi"
check "/DATA mounted" "mountpoint -q /DATA"

echo "=== Swap (zram) ==="
check "zram0 is swap" "grep -q '^/dev/zram0' /proc/swaps"
check "zram0 uses zstd" "grep -q '\[zstd\]' /sys/block/zram0/comp_algorithm"

echo "=== Network services ==="
check "NetworkManager active" "systemctl is-active -q NetworkManager"
check "ifupdown networking disabled" "! systemctl is-enabled -q networking"
check "tailscale0 up" "ip link show tailscale0 | grep -q UP"
check "tailscale logged in" "tailscale status --self --peers=false | grep -q hub-11"
check "TUN" "test -e /dev/net/tun"
check "WireGuard" "test -d /sys/module/wireguard || modinfo wireguard"

echo "=== Desktop (only if lightdm installed) ==="
if command -v lightdm >/dev/null; then
  check "lightdm active" "systemctl is-active -q lightdm"
  check "xfce4-session running" "pgrep -x xfce4-session"
fi

echo "=== Kconfig sanity ==="
for cfg in CONFIG_CGROUPS CONFIG_MEMCG CONFIG_CGROUP_PIDS CONFIG_OVERLAY_FS CONFIG_BRIDGE \
           CONFIG_VXLAN CONFIG_NF_TABLES CONFIG_WIREGUARD CONFIG_TUN CONFIG_ZRAM CONFIG_MMC_DW_ROCKCHIP; do
  check "$cfg" "zcat /proc/config.gz | grep -q '^${cfg}=[ym]'"
done

echo ""
echo "=== Summary: PASS=$PASS FAIL=$FAIL ==="
[ "$FAIL" -eq 0 ]
