#!/usr/bin/env bash
# Provide arm-none-eabi-gcc, qemu-system-arm, and gdb-multiarch.
# Uses sudo when it can. Otherwise downloads the distro packages and
# stacks them on /usr inside a user namespace (see env.sh rtosdev_run).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

pkgs_apt=(gcc-arm-none-eabi libnewlib-arm-none-eabi qemu-system-arm gdb-multiarch)

show_versions() {
	echo "toolchain:"
	rtosdev_run arm-none-eabi-gcc --version | head -n 1
	rtosdev_run qemu-system-arm --version | head -n 1
	rtosdev_run gdb-multiarch --version | head -n 1
}

if rtosdev_host_ready || rtosdev_overlay_ready; then
	show_versions
	exit 0
fi

if sudo -n true 2>/dev/null; then
	if command -v apt-get >/dev/null 2>&1; then
		sudo apt-get update
		sudo apt-get install -y --no-install-recommends "${pkgs_apt[@]}"
	elif command -v dnf >/dev/null 2>&1; then
		sudo dnf install -y arm-none-eabi-gcc-cs arm-none-eabi-newlib qemu-system-arm gdb make python3
	elif command -v pacman >/dev/null 2>&1; then
		sudo pacman -S --needed --noconfirm arm-none-eabi-gcc arm-none-eabi-newlib qemu-system-arm gdb make python
	else
		echo "no supported package manager; install arm-none-eabi-gcc, qemu-system-arm, and gdb-multiarch" >&2
		exit 1
	fi
	show_versions
	exit 0
fi

if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then
	echo "sudo is unavailable and apt-get is not here." >&2
	echo "install arm-none-eabi-gcc, qemu-system-arm, and gdb-multiarch, then re-run deps.sh" >&2
	exit 1
fi

echo "sudo needs a password; unpacking the toolchain under $COMPILE"
debdir=$HOST_TOOLS/debs
sysroot=$HOST_TOOLS/sysroot
rm -rf "$sysroot"
mkdir -p "$debdir" "$sysroot" "$OVERLAY_UPPER"

pkgs=$(apt-get install -s -y -qq --no-install-recommends "${pkgs_apt[@]}" 2>/dev/null \
	| awk '/^Inst / {print $2}')
if [[ -z $pkgs ]]; then
	echo "apt could not resolve: ${pkgs_apt[*]}" >&2
	exit 1
fi
echo "downloading: $pkgs"
(
	cd "$debdir"
	# shellcheck disable=SC2086
	apt-get download $pkgs
)
shopt -s nullglob
debs=("$debdir"/*.deb)
if [[ ${#debs[@]} -eq 0 ]]; then
	echo "apt-get download produced no packages in $debdir" >&2
	exit 1
fi
for deb in "${debs[@]}"; do
	dpkg-deb -x "$deb" "$sysroot"
done

# debs install into usr/. A few still drop libraries in lib/.
cp -a "$sysroot/usr/." "$OVERLAY_UPPER/"
if [[ -d $sysroot/lib && ! -L $sysroot/lib ]]; then
	mkdir -p "$OVERLAY_UPPER/lib"
	cp -a "$sysroot/lib/." "$OVERLAY_UPPER/lib/"
fi

# The newlib postinst points the toolchain at this C library with two
# alternatives symlinks. Create them here; update-alternatives needs root.
ln -sfn newlib "$OVERLAY_UPPER/lib/arm-none-eabi/lib"
ln -sfn ../../include/newlib "$OVERLAY_UPPER/lib/arm-none-eabi/include"

# The gcc package sometimes ships only arm-none-eabi-gcc-<ver> and lets
# the postinst create the unsuffixed name. Do that here.
if [[ ! -e $OVERLAY_UPPER/bin/arm-none-eabi-gcc ]]; then
	for cand in "$OVERLAY_UPPER"/bin/arm-none-eabi-gcc-*; do
		[[ -x $cand ]] || continue
		ln -s "$(basename "$cand")" "$OVERLAY_UPPER/bin/arm-none-eabi-gcc"
		break
	done
fi
for tool in ld as objcopy objdump ar nm size gdb; do
	if [[ ! -e $OVERLAY_UPPER/bin/arm-none-eabi-$tool ]]; then
		for cand in "$OVERLAY_UPPER"/bin/arm-none-eabi-"$tool"-*; do
			[[ -x $cand ]] || continue
			ln -s "$(basename "$cand")" "$OVERLAY_UPPER/bin/arm-none-eabi-$tool"
			break
		done
	fi
done

if ! rtosdev_overlay_ready && ! rtosdev_host_ready; then
	echo "deps.sh unpacked packages but the toolchain binaries are still missing" >&2
	echo "looked in $OVERLAY_UPPER/bin" >&2
	ls -1 "$OVERLAY_UPPER/bin" | head -n 40 >&2 || true
	exit 1
fi

show_versions
