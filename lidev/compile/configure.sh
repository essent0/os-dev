#!/usr/bin/env bash
# multi_v7_defconfig + config/qemu.fragment. ARCH=arm.
# Pass --reconfig to regenerate .config from scratch.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

reconfig=0
if [[ ${1:-} == --reconfig ]]; then
	reconfig=1
elif [[ -n ${1:-} ]]; then
	echo "usage: configure.sh [--reconfig]" >&2
	exit 2
fi

if [[ ! -f $SRC/Makefile ]]; then
	echo "kernel tree not found at $SRC" >&2
	exit 1
fi

if [[ -f $BUILD/.config && $reconfig -eq 0 ]] && grep -q '^CONFIG_ARM=y$' "$BUILD/.config"; then
	echo "keeping $BUILD/.config"
	echo "run configure.sh --reconfig to apply config/qemu.fragment again"
	exit 0
fi

if [[ -d $BUILD ]]; then
	echo "removing $BUILD so the ARM config does not reuse another architecture"
	rm -rf "$BUILD"
fi
mkdir -p "$BUILD"

echo "writing $BUILD/.config"
lidev_run make -C "$SRC" O="$BUILD" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" multi_v7_defconfig
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$BUILD" \
	"$BUILD/.config" "$FRAGMENT"
lidev_run make -C "$SRC" O="$BUILD" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig

missing=0
for sym in \
	CONFIG_ARM \
	CONFIG_ARCH_VIRT \
	CONFIG_SERIAL_AMBA_PL011_CONSOLE \
	CONFIG_BLK_DEV_INITRD \
	CONFIG_RD_GZIP \
	CONFIG_DEVTMPFS \
	CONFIG_BINFMT_ELF \
	CONFIG_BINFMT_SCRIPT \
	CONFIG_9P_FS \
	CONFIG_NET_9P \
	CONFIG_NET_9P_VIRTIO \
	CONFIG_VIRTIO_PCI \
	CONFIG_MAGIC_SYSRQ \
	CONFIG_TMPFS \
	CONFIG_PROC_FS \
	CONFIG_SYSFS
do
	if ! grep -q "^${sym}=y$" "$BUILD/.config"; then
		echo "config is missing ${sym}=y" >&2
		missing=1
	fi
done
if [[ $missing -ne 0 ]]; then
	echo "edit $FRAGMENT and run configure.sh --reconfig" >&2
	exit 1
fi

echo "local version: $(grep '^CONFIG_LOCALVERSION=' "$BUILD/.config")"
echo "debug info: $(grep -E '^CONFIG_DEBUG_INFO' "$BUILD/.config" | tr '\n' ' ')"
echo "config ready: $BUILD/.config"
