# Shared paths for the compile/ scripts. Source this; do not execute it.

_lidev_env_self=${BASH_SOURCE[0]}
COMPILE=$(cd "$(dirname "$_lidev_env_self")" && pwd)
LIDEV_ROOT=$(cd "$COMPILE/.." && pwd)

SRC="$LIDEV_ROOT/linux"
OSDEV_ROOT=$(cd "$LIDEV_ROOT/.." && pwd)
QEMU_ARM=$OSDEV_ROOT/qemudev/compile/build/qemu-system-arm
# qemu-system-arm is the 32-bit system emulator built in qemudev.
ARCH=arm
CROSS_COMPILE=arm-linux-gnueabihf-
export ARCH CROSS_COMPILE
BUILD="$COMPILE/build"
SHARE="$COMPILE/share"
LOGS="$COMPILE/logs"
GUEST="$COMPILE/guest"
FRAGMENT="$COMPILE/config/qemu.fragment"
INITRAMFS="$COMPILE/initramfs.cpio.gz"
HOST_TOOLS="$COMPILE/host-tools"
OVERLAY_UPPER="$COMPILE/.overlay/upper"
OVERLAY_WORK="$COMPILE/.overlay/work"
OVERLAY_MERGED="$COMPILE/.overlay/merged"

: "${JOBS:=$(nproc)}"
: "${MEM:=2048}"
: "${SMP:=2}"

# The build runs inside a user namespace where id(1) says root.
# Record the real host identity before that happens.
if [[ -z ${KBUILD_BUILD_USER:-} ]]; then
	KBUILD_BUILD_USER=$(id -un)
fi
if [[ -z ${KBUILD_BUILD_HOST:-} ]]; then
	KBUILD_BUILD_HOST=$(hostname -s 2>/dev/null || hostname)
fi
export KBUILD_BUILD_USER KBUILD_BUILD_HOST

mkdir -p "$SHARE/experiments/src" "$SHARE/results" "$LOGS" \
	"$HOST_TOOLS/bin" "$GUEST" "$COMPILE/config" "$COMPILE/lib"

lidev_host_toolchain() {
	command -v flex >/dev/null 2>&1 \
		&& command -v bison >/dev/null 2>&1 \
		&& [[ -f /usr/include/libelf.h ]]
}

lidev_host_cross() {
	command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1
}

# Run a command. If the host is missing flex, bison, libelf headers, or
# the ARM cross compiler, run it in a mount namespace where deps.sh has
# stacked those packages onto /usr.
lidev_run() {
	if lidev_host_toolchain && lidev_host_cross; then
		"$@"
		return
	fi
	if ! lidev_host_toolchain \
		&& { [[ ! -x $OVERLAY_UPPER/bin/flex || ! -x $OVERLAY_UPPER/bin/bison ]]; }; then
		echo "flex and bison are not available. Run $COMPILE/deps.sh" >&2
		return 1
	fi
	if ! lidev_host_cross && [[ ! -x $OVERLAY_UPPER/bin/${CROSS_COMPILE}gcc ]]; then
		echo "${CROSS_COMPILE}gcc is not available. Run $COMPILE/deps.sh" >&2
		return 1
	fi
	rm -rf "$OVERLAY_WORK"
	mkdir -p "$OVERLAY_WORK" "$OVERLAY_MERGED"
	unshare --user --map-root-user --mount --fork -- \
		bash "$COMPILE/lib/ns-exec.sh" \
		"$OVERLAY_UPPER" "$OVERLAY_WORK" "$OVERLAY_MERGED" \
		"$@"
}

lidev_qemu() {
	if [[ ! -x $QEMU_ARM ]]; then
		echo "local qemu-system-arm is not built. Run $OSDEV_ROOT/qemudev/compile/build.sh" >&2
		return 1
	fi
	# arm-softmmu was built with --disable-install-blobs, so the virtio
	# ROM stays in the QEMU source tree.
	local bios=$OSDEV_ROOT/qemudev/qemu/pc-bios
	if command -v stdbuf >/dev/null 2>&1; then
		stdbuf -oL -eL "$QEMU_ARM" -L "$bios" "$@"
	else
		"$QEMU_ARM" -L "$bios" "$@"
	fi
}
