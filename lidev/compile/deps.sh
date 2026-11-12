#!/usr/bin/env bash
# Install flex, bison, libelf headers, and qemu.
# Uses sudo when it can. Otherwise downloads the .debs and stacks them
# on /usr inside a user namespace (see env.sh lidev_run).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

host_ready() {
	lidev_host_toolchain && lidev_host_qemu
}

overlay_ready() {
	[[ -x $OVERLAY_UPPER/bin/flex \
		&& -x $OVERLAY_UPPER/bin/bison \
		&& -f $OVERLAY_UPPER/include/libelf.h \
		&& -x $OVERLAY_UPPER/bin/qemu-system-x86_64 ]]
}

if host_ready; then
	echo "host already has flex, bison, libelf headers, and qemu"
	exit 0
fi

if ! overlay_ready; then
	if sudo -n true 2>/dev/null; then
		sudo apt-get update
		sudo apt-get install -y \
			build-essential flex bison bc rsync cpio \
			libssl-dev libelf-dev dwarves qemu-system-x86
	else
		echo "sudo needs a password; unpacking flex, bison, libelf, and qemu under $COMPILE"
		debdir=$HOST_TOOLS/debs
		sysroot=$HOST_TOOLS/sysroot
		mkdir -p "$debdir" "$sysroot"
		if ! compgen -G "$debdir/*.deb" >/dev/null; then
			pkgs=$(apt-get install -s -y -qq flex bison libelf-dev qemu-system-x86 m4 2>/dev/null \
				| awk '/^Inst / {print $2}')
			if [[ -z $pkgs ]]; then
				echo "apt could not resolve flex, bison, libelf-dev, qemu-system-x86" >&2
				exit 1
			fi
			(
				cd "$debdir"
				# shellcheck disable=SC2086
				apt-get download $pkgs
			)
		fi
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
	qemu_ver=$(lidev_run qemu-system-x86_64 --version)
	printf '%s\n' "$flex_ver" "$bison_ver" "$qemu_ver" | awk 'NR==1 || /^bison/ || /^QEMU/'
	exit 0
fi

echo "deps.sh could not provide flex, bison, libelf, and qemu" >&2
exit 1
