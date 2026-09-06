#!/usr/bin/env bash
# Build inside the GitHub Actions ubuntu-latest runner (used by release.yml).
# NOT used for day-to-day builds — those run on lab via scripts/build-kernel.sh.
# Mirrors build-kernel.sh + build-fit.sh: repo patches, repo DTS, same config
# fragments, same FIT layout and size cap.
set -euo pipefail

cd "${GITHUB_WORKSPACE:-.}"
KERNEL_TAG=$(grep -vE '^\s*(#|$)' KERNEL_TAG | head -1 | tr -d '[:space:]')

export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION="" KBUILD_BUILD_USER=ci KBUILD_BUILD_HOST=github
git config --global user.name ci; git config --global user.email ci@invalid

SRC="$RUNNER_TEMP/linux"
git clone -q --depth 1 --branch "$KERNEL_TAG" \
    https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "$SRC"
for p in patches/*.patch; do
    git -C "$SRC" am --3way "$GITHUB_WORKSPACE/$p"
done
cp dts/rk3588-hub11*.dts "$SRC/arch/arm64/boot/dts/rockchip/"

OUT="$RUNNER_TEMP/kernel-out"; mkdir -p "$OUT"
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" \
    "$SRC/arch/arm64/configs/defconfig" configs/hub11.config configs/hub11_infra.config
make -C "$SRC" O="$OUT" olddefconfig
make -C "$SRC" O="$OUT" -j"$(nproc)" Image dtbs modules

KREL=$(cat "$OUT/include/config/kernel.release")
echo "$KREL" | grep -qE '^6\.18\.[0-9]+-hub11$' || { echo "FATAL: release '$KREL'"; exit 1; }

DIST="$RUNNER_TEMP/dist"; mkdir -p "$DIST"
cp "$OUT/arch/arm64/boot/Image" "$DIST/Image"
cp "$OUT/arch/arm64/boot/dts/rockchip/rk3588-hub11.dtb" "$DIST/vendor.dtb"   # name fixed by the .its
cp "$OUT/arch/arm64/boot/dts/rockchip/rk3588-hub11.dtb" "$DIST/rk3588-hub11.dtb"
cp "$OUT/arch/arm64/boot/dts/rockchip/rk3588-hub11-sdhs.dtb" "$DIST/rk3588-hub11-sdhs.dtb"
cp firmware-blobs/resource.img "$DIST/resource.img"
cp fit/hub11-boot.its "$DIST/hub11-boot.its"
echo "$KREL" > "$DIST/KREL"

make -C "$SRC" O="$OUT" INSTALL_MOD_PATH="$DIST/modules" INSTALL_MOD_STRIP=1 modules_install
tar -C "$DIST/modules/lib/modules" -cf - "$KREL" | zstd -q -19 -o "$DIST/modules.tar.zst"
rm -rf "$DIST/modules"

( cd "$DIST" && mkimage -E -p 0x800 -f hub11-boot.its "hub11-boot-$KREL.itb" )
SIZE=$(stat -c%s "$DIST/hub11-boot-$KREL.itb")
[ "$SIZE" -lt 67108864 ] || { echo "FATAL: FIT $SIZE >= 64 MiB"; exit 1; }
( cd "$DIST" && sha256sum Image vendor.dtb rk3588-hub11.dtb rk3588-hub11-sdhs.dtb resource.img "hub11-boot-$KREL.itb" modules.tar.zst > SHA256SUMS )
echo "Built: hub11-boot-$KREL.itb ($SIZE bytes)"
