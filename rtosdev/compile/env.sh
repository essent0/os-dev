# Shared paths for the compile/ scripts. Source this; do not execute it.

_rtosdev_env_self=${BASH_SOURCE[0]}
COMPILE=$(cd "$(dirname "$_rtosdev_env_self")" && pwd)
RTOSDEV_ROOT=$(cd "$COMPILE/.." && pwd)

SRC="$RTOSDEV_ROOT/FreeRTOS-Kernel"
OSDEV_ROOT=$(cd "$RTOSDEV_ROOT/.." && pwd)
QEMU_ARM=$OSDEV_ROOT/qemudev/compile/build/qemu-system-arm
BUILD="$COMPILE/build"
ELF="$BUILD/freertos.elf"
SHARE="$COMPILE/share"
LOGS="$COMPILE/logs"
GUEST="$COMPILE/guest"
HOST_TOOLS="$COMPILE/host-tools"
OVERLAY_UPPER="$COMPILE/.overlay/upper"

: "${JOBS:=$(nproc)}"
: "${TIMEOUT:=30}"
: "${GDB_PORT:=1234}"

mkdir -p "$LOGS" "$HOST_TOOLS" "$COMPILE/.overlay" "$SHARE/experiments/src"

# Host already has the cross compiler, QEMU, and gdb.
rtosdev_host_ready() {
	command -v arm-none-eabi-gcc >/dev/null 2>&1 \
		&& command -v qemu-system-arm >/dev/null 2>&1 \
		&& command -v gdb-multiarch >/dev/null 2>&1 \
		&& [[ -f /usr/lib/arm-none-eabi/include/stdlib.h ]]
}

rtosdev_newlib_header() {
	# gcc searches .../arm-none-eabi/include, which the newlib package
	# turns into a symlink. The headers under include/newlib are not
	# enough on their own.
	[[ -f /usr/lib/arm-none-eabi/include/stdlib.h \
		|| -f $OVERLAY_UPPER/lib/arm-none-eabi/include/stdlib.h ]]
}

rtosdev_overlay_ready() {
	[[ -x $OVERLAY_UPPER/bin/arm-none-eabi-gcc \
		&& -x $OVERLAY_UPPER/bin/qemu-system-arm \
		&& -x $OVERLAY_UPPER/bin/gdb-multiarch ]] \
		&& rtosdev_newlib_header
}

# Run a command. If the toolchain is not on PATH, run it in a user
# namespace where deps.sh has stacked the packages onto /usr.
rtosdev_run() {
	if rtosdev_host_ready; then
		"$@"
		return
	fi
	if ! rtosdev_overlay_ready; then
		echo "arm-none-eabi-gcc, qemu-system-arm, and gdb-multiarch are missing. Run $COMPILE/deps.sh" >&2
		return 1
	fi
	local work merged rc
	work=$(mktemp -d "$COMPILE/.overlay/work.XXXXXX")
	merged=$(mktemp -d "$COMPILE/.overlay/merged.XXXXXX")
	set +e
	unshare --user --map-root-user --mount --fork --kill-child -- \
		bash "$COMPILE/lib/ns-exec.sh" \
		"$OVERLAY_UPPER" "$work" "$merged" \
		"$@"
	rc=$?
	set -e
	rm -rf "$work" "$merged"
	return "$rc"
}
