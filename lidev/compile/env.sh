# Shared paths for the compile/ scripts. Source this; do not execute it.

_lidev_env_self=${BASH_SOURCE[0]}
COMPILE=$(cd "$(dirname "$_lidev_env_self")" && pwd)
LIDEV_ROOT=$(cd "$COMPILE/.." && pwd)

SRC="$LIDEV_ROOT/linux"
OSDEV_ROOT=$(cd "$LIDEV_ROOT/.." && pwd)
QEMU_ARM=$OSDEV_ROOT/qemudev/compile/build/qemu-system-arm
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

lidev_host_qemu() {
	command -v qemu-system-x86_64 >/dev/null 2>&1
}

# Run a command. If the host is missing flex, bison, libelf headers, or
# (when the command is qemu) qemu itself, run it in a mount namespace
# where deps.sh has stacked those packages onto /usr.
lidev_run() {
	local overlay=0 arg needs_qemu=0
	if ! lidev_host_toolchain; then
		overlay=1
	fi
	for arg in "$@"; do
		if [[ $arg == qemu-system-x86_64 ]]; then
			needs_qemu=1
		fi
	done
	if [[ $needs_qemu -eq 1 ]] && ! lidev_host_qemu; then
		overlay=1
	fi
	if [[ $overlay -eq 0 ]]; then
		"$@"
		return
	fi
	if [[ ! -x $OVERLAY_UPPER/bin/flex || ! -x $OVERLAY_UPPER/bin/bison ]]; then
		echo "flex and bison are not available. Run $COMPILE/deps.sh" >&2
		return 1
	fi
	if [[ $needs_qemu -eq 1 ]] && ! lidev_host_qemu \
		&& [[ ! -x $OVERLAY_UPPER/bin/qemu-system-x86_64 ]]; then
		echo "qemu-system-x86_64 is not available. Run $COMPILE/deps.sh" >&2
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
	if command -v stdbuf >/dev/null 2>&1; then
		lidev_run stdbuf -oL -eL "$QEMU_ARM" "$@"
	else
		lidev_run "$QEMU_ARM" "$@"
	fi
}
