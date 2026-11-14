#!/usr/bin/env bash
# Compile the kernel out of tree into compile/build.
# Extra arguments are make targets. The default target is zImage,
# which does not build modules. ARCH=arm.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

if [[ ! -f $BUILD/.config ]]; then
	echo "no $BUILD/.config; run configure.sh first" >&2
	exit 1
fi

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
	targets=(zImage)
fi

echo "make -C $SRC O=$BUILD ARCH=$ARCH CROSS_COMPILE=$CROSS_COMPILE -j$JOBS ${targets[*]}"
lidev_run make -C "$SRC" O="$BUILD" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" "${targets[@]}"

if [[ -f $BUILD/arch/arm/boot/zImage ]]; then
	ls -lh "$BUILD/arch/arm/boot/zImage" "$BUILD/vmlinux"
fi
