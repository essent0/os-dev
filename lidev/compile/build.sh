#!/usr/bin/env bash
# Compile the kernel out of tree into compile/build.
# Extra arguments are make targets. The default target is bzImage,
# which does not build modules.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

if [[ ! -f $BUILD/.config ]]; then
	echo "no $BUILD/.config; run configure.sh first" >&2
	exit 1
fi

targets=("$@")
if [[ ${#targets[@]} -eq 0 ]]; then
	targets=(bzImage)
fi

echo "make -C $SRC O=$BUILD -j$JOBS ${targets[*]}"
lidev_run make -C "$SRC" O="$BUILD" -j"$JOBS" "${targets[@]}"

if [[ -f $BUILD/arch/x86/boot/bzImage ]]; then
	ls -lh "$BUILD/arch/x86/boot/bzImage" "$BUILD/vmlinux"
fi
