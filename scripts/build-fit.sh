#!/usr/bin/env bash
# scripts/build-fit.sh — assemble hub11-boot-<krel>.itb on lab.
#
# Usage:  bash scripts/build-fit.sh
#         HUB11_DTB=rk3588-hub11-sdhs.dtb bash scripts/build-fit.sh   # SD high-speed fallback
# Output: ~/build/hub11/dist/<UTC ts>-<krel>/
#           hub11-boot-<krel>.itb   Image   vendor.dtb (=the chosen board DTB)
#           resource.img  hub11-boot.its  modules.tar.zst  firmware/  KREL  SHA256SUMS
#         ~/build/hub11/dist/latest -> that directory
#
# Every dist directory is self-contained (real copies, no symlinks), so an
# older dist is a valid rollback even after the kernel tree is rebuilt.
set -euo pipefail

META="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB=${LAB:-/home/nyx}
OUT=${KERNEL_OUT:-"$LAB/build/hub11/kernel-out"}
DIST=${DIST:-"$LAB/build/hub11/dist"}
HUB11_DTB=${HUB11_DTB:-rk3588-hub11.dtb}

KREL=$(cat "$OUT/include/config/kernel.release")
TS=$(date -u +%Y%m%d-%H%M)
DEST="$DIST/$TS-$KREL"
DTB_SRC="$OUT/arch/arm64/boot/dts/rockchip/$HUB11_DTB"
test -f "$DTB_SRC" || { echo "FATAL: $DTB_SRC not built"; exit 1; }

mkdir -p "$DEST"
cd "$DEST"

cp "$OUT/arch/arm64/boot/Image" Image
cp "$META/firmware-blobs/resource.img" resource.img
cp "$DTB_SRC" vendor.dtb          # name is fixed by fit/hub11-boot.its
cp "$META/fit/hub11-boot.its" hub11-boot.its
echo "$KREL" > KREL
echo "$HUB11_DTB" > DTB
mkdir -p firmware
cp -r "$META/firmware-blobs/brcm" firmware/
mkdir -p firmware/arm/mali/arch10.8
cp "$META/firmware-blobs/mali/mali_csffw.bin" firmware/arm/mali/arch10.8/

# Modules: tarball is rooted at <krel>/ so it can only ever be extracted into
# /usr/lib/modules/ — never with -C / (that clobbered the /lib symlink once).
rm -rf "$DEST/modules"
make -C "$OUT" O="$OUT" \
    INSTALL_MOD_PATH="$DEST/modules" \
    INSTALL_MOD_STRIP=1 \
    STRIP=/usr/bin/aarch64-linux-gnu-strip \
    CROSS_COMPILE=aarch64-linux-gnu- \
    LOCALVERSION="" \
    modules_install >/dev/null
test -f "$DEST/modules/lib/modules/$KREL/modules.dep" || { echo "FATAL: modules_install produced no $KREL"; exit 1; }
tar -C "$DEST/modules/lib/modules" -cf "$DEST/modules.tar" "$KREL"
zstd -q -f -T0 -19 "$DEST/modules.tar" -o "$DEST/modules.tar.zst"
rm -rf "$DEST/modules.tar" "$DEST/modules"

echo ">>> mkimage -E -p 0x800 -f hub11-boot.its"
mkimage -E -p 0x800 -f hub11-boot.its "hub11-boot-$KREL.itb" >/dev/null

SIZE=$(stat -c%s "hub11-boot-$KREL.itb")
echo ">>> FIT size: $SIZE bytes ($(( (67108864 - SIZE) / 1024 )) KiB headroom under the 64 MiB p3 cap)"
if [ "$SIZE" -ge 67108864 ]; then
  echo "FATAL: FIT exceeds 64 MiB p3 partition."
  exit 1
fi

sha256sum Image vendor.dtb resource.img "hub11-boot-$KREL.itb" modules.tar.zst > SHA256SUMS
find firmware -type f -print0 | sort -z | xargs -0 sha256sum >> SHA256SUMS
cat SHA256SUMS

ln -sfn "$TS-$KREL" "$DIST/latest"
echo ""
echo "OK: $DEST  (dist/latest updated)"
echo "    FIT: hub11-boot-$KREL.itb   DTB: $HUB11_DTB"
