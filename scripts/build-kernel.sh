#!/usr/bin/env bash
# scripts/build-kernel.sh — cross-build mainline Linux 6.18 for hub-11 on lab.
#
# Usage:  bash scripts/build-kernel.sh
# Output: ~/build/hub11/kernel-out/{arch/arm64/boot/Image,dts/rockchip/rk3588-hub11*.dtb,modules}
#
# Idempotent: every run resets the work branch hub11/<KERNEL_TAG> to the pinned
# tag, re-applies patches/*.patch with git am, copies dts/*.dts from this repo
# into the tree, and builds. Refuses to run on a dirty kernel tree.
set -euo pipefail

META="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAB=${LAB:-/home/nyx}
SRC=${KERNEL_SRC:-"$LAB/src/linux-stable-6.18"}
OUT=${KERNEL_OUT:-"$LAB/build/hub11/kernel-out"}
KREL_FILE="$OUT/include/config/kernel.release"
KERNEL_TAG=$(grep -vE '^\s*(#|$)' "$META/KERNEL_TAG" | head -1 | tr -d '[:space:]')
[ -n "$KERNEL_TAG" ] || { echo "FATAL: KERNEL_TAG empty after parse"; exit 1; }

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
# CONFIG_LOCALVERSION="-hub11" lives in configs/hub11.config. Keep the env var
# set-but-empty so setlocalversion neither doubles the suffix nor appends "+".
export LOCALVERSION=""
export KBUILD_BUILD_USER=nyx
export KBUILD_BUILD_HOST=lab
export GIT_AUTHOR_NAME=Nyx GIT_AUTHOR_EMAIL=mail.me.nyx@gmail.com
export GIT_COMMITTER_NAME=Nyx GIT_COMMITTER_EMAIL=mail.me.nyx@gmail.com

cd "$SRC"

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "FATAL: kernel tree $SRC has uncommitted changes; commit or discard them first."
  git status --short | head
  exit 1
fi

# Refresh the pinned tag and reset the work branch onto it.
git fetch -q --depth=1 origin "refs/tags/$KERNEL_TAG:refs/tags/$KERNEL_TAG" 2>/dev/null || true
git rev-parse -q --verify "refs/tags/$KERNEL_TAG^{commit}" >/dev/null \
  || { echo "FATAL: kernel tag $KERNEL_TAG not found in $SRC"; exit 1; }
git checkout -q -B "hub11/$KERNEL_TAG" "$KERNEL_TAG"

# Apply repo patches in order.
shopt -s nullglob
for p in "$META"/patches/*.patch; do
  echo ">>> git am $(basename "$p")"
  git am -q --3way "$p" || { git am --abort; echo "FATAL: patch $(basename "$p") failed"; exit 1; }
done

# Board DTS files are owned by this repo; copy them into the tree (untracked
# files do not affect setlocalversion).
for d in "$META"/dts/rk3588-hub11*.dts; do
  cp "$d" "$SRC/arch/arm64/boot/dts/rockchip/$(basename "$d")"
done

# Out-of-tree driver sources (kernel-extra/README.md), untracked in the tree.
if [ -d "$META/kernel-extra" ]; then
  cp -a "$META/kernel-extra/drivers" "$SRC/"
fi

mkdir -p "$OUT"
echo ">>> merge_config.sh defconfig + hub11 + hub11_infra"
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$OUT" \
  "$SRC/arch/arm64/configs/defconfig" \
  "$META/configs/hub11.config" \
  "$META/configs/hub11_infra.config" | grep -E "Value requested|Actual value" || true

echo ">>> make olddefconfig"
make -C "$SRC" O="$OUT" olddefconfig 2>&1 | tail -5

NPROC=$(nproc)
echo ">>> make -j$NPROC Image dtbs modules"
make -C "$SRC" O="$OUT" -j"$NPROC" Image dtbs modules 2>&1 | grep -E "warning:|error:|Error|^  (LD|OBJCOPY|DTC).*(Image|hub11)" || true

test -f "$OUT/arch/arm64/boot/Image" || { echo "FATAL: Image not built"; exit 1; }
for d in "$META"/dts/rk3588-hub11*.dts; do
  dtb="$OUT/arch/arm64/boot/dts/rockchip/$(basename "${d%.dts}").dtb"
  test -f "$dtb" || { echo "FATAL: $(basename "$dtb") not built"; exit 1; }
done

KREL=$(cat "$KREL_FILE")
echo "$KREL" | grep -qE '^6\.18\.[0-9]+-hub11$' \
  || { echo "FATAL: unexpected kernel release '$KREL' (want 6.18.N-hub11)"; exit 1; }

echo ""
echo "OK: kernel $KREL built."
echo "    Image: $OUT/arch/arm64/boot/Image ($(stat -c%s "$OUT/arch/arm64/boot/Image") bytes)"
ls -1 "$OUT"/arch/arm64/boot/dts/rockchip/rk3588-hub11*.dtb | sed 's/^/    DTB:   /'
