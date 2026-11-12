#!/usr/bin/env bash
# Out-of-tree build of qemu-system-arm from ../qemu.
#
#   build.sh            configure if needed, then compile
#   build.sh clean      delete compile/build
#
# The source tree is left on branch dummy at tag v9.2.0.
# This script does not check out, switch, or retag anything.
# Only the arm system emulator is built.
set -euo pipefail

COMPILE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=$(cd "$COMPILE/../qemu" && pwd)
BUILD=$COMPILE/build
HOST_TOOLS=$COMPILE/host-tools
SYSROOT=$HOST_TOOLS/sysroot
DEBDIR=$HOST_TOOLS/debs

: "${JOBS:=$(nproc)}"

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
	sed -n '2,11p' "$0"
	exit 0
fi

if [[ ${1:-} == clean ]]; then
	rm -rf "$BUILD"
	echo "removed $BUILD"
	exit 0
fi

if [[ ! -d $SRC/.git ]]; then
	echo "qemu source is missing at $SRC" >&2
	exit 1
fi

branch=$(git -C "$SRC" symbolic-ref --short HEAD)
desc=$(git -C "$SRC" describe --tags --exact-match HEAD 2>/dev/null || true)
if [[ $branch != dummy || $desc != v9.2.0 ]]; then
	echo "qemu is branch ${branch} at ${desc:-unknown}; expected dummy at v9.2.0" >&2
	echo "build.sh does not switch branches. Stay on dummy at v9.2.0." >&2
	exit 1
fi

pc_dirs() {
	local dir dirs=()
	for dir in \
		"$SYSROOT/usr/lib/x86_64-linux-gnu/pkgconfig" \
		"$SYSROOT/usr/lib/pkgconfig" \
		"$SYSROOT/usr/share/pkgconfig"
	do
		[[ -d $dir ]] && dirs+=("$dir")
	done
	local IFS=:
	printf '%s\n' "${dirs[*]:-}"
}

export_build_env() {
	local pc
	pc=$(pc_dirs)
	if [[ -n $pc ]]; then
		if [[ -n ${PKG_CONFIG_PATH:-} ]]; then
			export PKG_CONFIG_PATH="${pc}:${PKG_CONFIG_PATH}"
		else
			export PKG_CONFIG_PATH=$pc
		fi
	fi
	if [[ -x $SYSROOT/usr/bin/ninja ]]; then
		export PATH="$SYSROOT/usr/bin:${PATH}"
	fi
	local inc=() lib=()
	[[ -d $SYSROOT/usr/include ]] && inc+=("-I$SYSROOT/usr/include")
	[[ -d $SYSROOT/usr/lib/x86_64-linux-gnu ]] && lib+=("-L$SYSROOT/usr/lib/x86_64-linux-gnu")
	[[ -d $SYSROOT/usr/lib ]] && lib+=("-L$SYSROOT/usr/lib")
	if [[ -d $SYSROOT/usr/lib/x86_64-linux-gnu ]]; then
		lib+=("-Wl,-rpath,$SYSROOT/usr/lib/x86_64-linux-gnu")
	fi
	EXTRA_CFLAGS="${inc[*]:-}"
	EXTRA_LDFLAGS="${lib[*]:-}"
}

deps_ready() {
	export_build_env
	command -v ninja >/dev/null 2>&1 \
		&& pkg-config --exists glib-2.0 gobject-2.0 gio-2.0 pixman-1 \
		&& { [[ -f /usr/include/libfdt.h ]] || [[ -f $SYSROOT/usr/include/libfdt.h ]]; }
}

rewrite_pc_prefixes() {
	local pc
	while IFS= read -r -d '' pc; do
		if grep -q '^prefix=/usr$' "$pc"; then
			sed -i "s|^prefix=/usr$|prefix=${SYSROOT}/usr|" "$pc"
		fi
	done < <(find "$SYSROOT" -name '*.pc' -print0)
}

# Dev packages ship libfoo.so -> libfoo.so.N. The runtime .so.N is already
# on the host. Prefer the amd64 copy: i386 libraries are installed too,
# and a 32-bit link fails with "file in wrong format".
host_library() {
	local base=$1 arch=$2
	local cand
	for cand in \
		"/usr/lib/${arch}/${base}" \
		"/lib/${arch}/${base}" \
		"/usr/lib/x86_64-linux-gnu/${base}" \
		"/lib/x86_64-linux-gnu/${base}"
	do
		if [[ -e $cand ]]; then
			printf '%s\n' "$cand"
			return 0
		fi
	done
	return 1
}

link_is_amd64() {
	local dest
	dest=$(readlink -f "$1" 2>/dev/null || true)
	[[ -n $dest && -f $dest ]] || return 1
	file -b "$dest" | grep -q 'ELF 64-bit'
}

fix_library_links() {
	local link target base arch host
	[[ -d $SYSROOT ]] || return 0
	while IFS= read -r -d '' link; do
		if link_is_amd64 "$link"; then
			continue
		fi
		target=$(readlink "$link")
		base=$(basename "$target")
		arch=$(basename "$(dirname "$link")")
		if host=$(host_library "$base" "$arch"); then
			ln -sfn "$host" "$link"
		fi
	done < <(find "$SYSROOT" -type l -print0)
}

ensure_deps() {
	if deps_ready; then
		return
	fi
	if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then
		echo "need ninja, libglib2.0-dev, libpixman-1-dev, and libfdt-dev" >&2
		exit 1
	fi
	local pkgs resolved
	pkgs=(libglib2.0-dev libpixman-1-dev libfdt-dev ninja-build)
	echo "unpacking build dependencies under $HOST_TOOLS"
	mkdir -p "$DEBDIR" "$SYSROOT"
	resolved=$(apt-get install -s -y -qq --no-install-recommends "${pkgs[@]}" 2>/dev/null \
		| awk '/^Inst / {print $2}')
	if [[ -z $resolved ]]; then
		echo "apt could not resolve: ${pkgs[*]}" >&2
		exit 1
	fi
	echo "downloading: $resolved"
	(
		cd "$DEBDIR"
		# shellcheck disable=SC2086
		apt-get download $resolved
	)
	local deb
	shopt -s nullglob
	for deb in "$DEBDIR"/*.deb; do
		dpkg-deb -x "$deb" "$SYSROOT"
	done
	shopt -u nullglob
	rewrite_pc_prefixes
	fix_library_links
	if ! deps_ready; then
		echo "build dependencies are still missing after unpacking $SYSROOT" >&2
		exit 1
	fi
}

ensure_deps
fix_library_links
export_build_env

if [[ ! -f $BUILD/build.ninja ]]; then
	mkdir -p "$BUILD"
	echo "configuring arm-softmmu in $BUILD"
	(
		cd "$BUILD"
		"$SRC/configure" \
			--target-list=arm-softmmu \
			--disable-docs \
			--disable-gtk \
			--disable-sdl \
			--disable-vnc \
			--disable-curses \
			--disable-guest-agent \
			--disable-tools \
			--disable-plugins \
			--disable-libusb \
			--disable-opengl \
			--disable-virglrenderer \
			--disable-dbus-display \
			--disable-capstone \
			--disable-slirp \
			--disable-spice \
			--disable-xen \
			--disable-kvm \
			--disable-install-blobs \
			--disable-rust \
			--enable-fdt=system \
			--extra-cflags="$EXTRA_CFLAGS" \
			--extra-ldflags="$EXTRA_LDFLAGS" \
			-Dwerror=false
	)
fi

echo "compiling qemu-system-arm (-j$JOBS)"
make -C "$BUILD" -j"$JOBS"

if [[ ! -x $BUILD/qemu-system-arm ]]; then
	echo "build finished but $BUILD/qemu-system-arm is missing" >&2
	exit 1
fi

echo "qemu: $BUILD/qemu-system-arm"
"$BUILD/qemu-system-arm" --version | head -n 1
