#!/usr/bin/env bash
# Provide qemu-system-i386 and a gcc that can compile -m32.
# Uses sudo when it can. Otherwise downloads the distro packages and
# stacks them on /usr inside a user namespace (see env.sh udev_run).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

show_versions() {
	echo "toolchain:"
	gcc --version | head -n 1
	if udev_m32; then
		echo "gcc -m32: yes"
	else
		echo "gcc -m32: via overlay"
	fi
	udev_run qemu-system-i386 --version | head -n 1
	gdb --version | head -n 1
	perl -v | sed -n 's/^This is //p' | head -n 1
}

need_pkgs() {
	local -n _out=$1
	_out=()
	if ! command -v qemu-system-i386 >/dev/null 2>&1 \
		&& [[ ! -x $OVERLAY_UPPER/bin/qemu-system-i386 ]]; then
		_out+=(qemu-system-x86)
	fi
	if ! udev_m32 && ! udev_have_m32_overlay; then
		_out+=(gcc-multilib libc6-dev-i386)
	fi
	if ! command -v perl >/dev/null 2>&1; then
		_out+=(perl)
	fi
	if ! command -v gdb >/dev/null 2>&1; then
		_out+=(gdb)
	fi
	if ! command -v python3 >/dev/null 2>&1; then
		_out+=(python3)
	fi
	if ! command -v make >/dev/null 2>&1; then
		_out+=(make)
	fi
}

pkgs=()
need_pkgs pkgs
if [[ ${#pkgs[@]} -eq 0 ]]; then
	show_versions
	exit 0
fi

if sudo -n true 2>/dev/null; then
	if command -v apt-get >/dev/null 2>&1; then
		sudo apt-get update
		sudo apt-get install -y --no-install-recommends "${pkgs[@]}"
	elif command -v dnf >/dev/null 2>&1; then
		sudo dnf install -y qemu-system-x86 gcc glibc-devel.i686 gdb perl python3 make
	elif command -v pacman >/dev/null 2>&1; then
		sudo pacman -S --needed --noconfirm qemu-system-x86 gcc gdb perl python make
	else
		echo "no supported package manager; install qemu-system-x86 and gcc -m32" >&2
		exit 1
	fi
	show_versions
	exit 0
fi

if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then
	echo "sudo is unavailable and apt-get is not here." >&2
	echo "install qemu-system-i386 and a gcc that accepts -m32, then re-run deps.sh" >&2
	exit 1
fi

echo "sudo needs a password; unpacking tools under $COMPILE"
debdir=$HOST_TOOLS/debs
sysroot=$HOST_TOOLS/sysroot
mkdir -p "$debdir" "$OVERLAY_UPPER"
rm -rf "$sysroot"
mkdir -p "$sysroot"

resolved=$(apt-get install -s -y -qq --no-install-recommends "${pkgs[@]}" 2>/dev/null \
	| awk '/^Inst / {print $2}')
if [[ -z $resolved ]]; then
	echo "apt could not resolve: ${pkgs[*]}" >&2
	exit 1
fi
echo "downloading: $resolved"
(
	cd "$debdir"
	# shellcheck disable=SC2086
	apt-get download $resolved
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

if [[ -d $sysroot/usr ]]; then
	cp -a "$sysroot/usr/." "$OVERLAY_UPPER/"
fi
if [[ -d $sysroot/lib && ! -L $sysroot/lib ]]; then
	mkdir -p "$OVERLAY_UPPER/lib"
	cp -a "$sysroot/lib/." "$OVERLAY_UPPER/lib/"
fi

if ! udev_tools_ready; then
	echo "deps.sh unpacked packages but qemu-system-i386 or gcc -m32 is still missing" >&2
	exit 1
fi

show_versions
