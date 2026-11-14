#!/usr/bin/env bash
# Install flex, bison, libelf headers, and the ARM cross compiler.
# The guest emulator is qemudev's qemu-system-arm, not a distro package.
# Uses sudo when it can. Otherwise downloads the .debs and stacks them
# on /usr inside a user namespace (see env.sh lidev_run).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

host_ready() {
	lidev_host_toolchain && lidev_host_cross
}

overlay_ready() {
	{ lidev_host_toolchain || { [[ -x $OVERLAY_UPPER/bin/flex \
		&& -x $OVERLAY_UPPER/bin/bison \
		&& -f $OVERLAY_UPPER/include/libelf.h ]]; }; } \
		&& { lidev_host_cross || [[ -x $OVERLAY_UPPER/bin/${CROSS_COMPILE}gcc ]]; }
}

if host_ready; then
	echo "host already has flex, bison, libelf headers, and ${CROSS_COMPILE}gcc"
	exit 0
fi

if ! overlay_ready; then
	if sudo -n true 2>/dev/null; then
		sudo apt-get update
		sudo apt-get install -y \
			build-essential flex bison bc rsync cpio \
			libssl-dev libelf-dev dwarves gcc-arm-linux-gnueabihf
	else
		echo "sudo needs a password; unpacking flex, bison, libelf, and ${CROSS_COMPILE}gcc under $COMPILE"
		debdir=$HOST_TOOLS/debs
		sysroot=$HOST_TOOLS/sysroot
		mkdir -p "$debdir" "$sysroot"
		pkgs=$(apt-get install -s -y -qq flex bison libelf-dev gcc-arm-linux-gnueabihf m4 bc 2>/dev/null \
			| awk '/^Inst / {print $2}')
		if [[ -z $pkgs ]]; then
			echo "apt could not resolve flex, bison, libelf-dev, gcc-arm-linux-gnueabihf" >&2
			exit 1
		fi
		(
			cd "$debdir"
			# shellcheck disable=SC2086
			apt-get download $pkgs
		)
		for deb in "$debdir"/*.deb; do
			dpkg-deb -x "$deb" "$sysroot"
		done
		mkdir -p "$OVERLAY_UPPER"
		rsync -a "$sysroot/usr/" "$OVERLAY_UPPER/"
	fi
fi

if host_ready || overlay_ready; then
	echo "toolchain:"
	flex_ver=$(lidev_run flex --version)
	bison_ver=$(lidev_run bison --version)
	gcc_ver=$(lidev_run "${CROSS_COMPILE}gcc" --version)
	printf '%s\n' "$flex_ver" "$bison_ver" "$gcc_ver" | awk 'NR==1 || /^bison/ || /arm-linux-gnueabihf/'
	exit 0
fi

echo "deps.sh could not provide flex, bison, libelf, and ${CROSS_COMPILE}gcc" >&2
exit 1
