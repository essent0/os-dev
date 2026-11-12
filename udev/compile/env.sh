# Shared paths for the compile/ scripts. Source this; do not execute it.

_udev_env_self=${BASH_SOURCE[0]}
COMPILE=$(cd "$(dirname "$_udev_env_self")" && pwd)
UDEV_ROOT=$(cd "$COMPILE/.." && pwd)

SRC="$UDEV_ROOT/xv6-public"
OSDEV_ROOT=$(cd "$UDEV_ROOT/.." && pwd)
QEMU_ARM=$OSDEV_ROOT/qemudev/compile/build/qemu-system-arm
export QEMU_ARM
BUILD="$COMPILE/build"
TREE="$BUILD/tree"
LOGS="$COMPILE/logs"
HOST_TOOLS="$COMPILE/host-tools"
OVERLAY_UPPER="$COMPILE/.overlay/upper"

: "${CPUS:=1}"
: "${MEM:=512}"
: "${ACCEL:=tcg}"
: "${GDB_PORT:=1234}"

mkdir -p "$LOGS" "$HOST_TOOLS" "$COMPILE/.overlay"

# Host gcc can compile i386 (-m32) code.
udev_m32() {
	echo 'int xv6;' | gcc -m32 -x c -c -o /dev/null - >/dev/null 2>&1
}

udev_have_qemu() {
	command -v qemu-system-i386 >/dev/null 2>&1 \
		|| [[ -x $OVERLAY_UPPER/bin/qemu-system-i386 ]]
}

# libc6-dev-i386 / gcc-multilib unpacked by deps.sh when the host gcc
# cannot build -m32. The overlay test is the header the compiler opens.
udev_have_m32_overlay() {
	[[ -f $OVERLAY_UPPER/include/i386-linux-gnu/gnu/stubs-32.h \
		|| -f $OVERLAY_UPPER/lib/i386-linux-gnu/libc.so \
		|| -e $OVERLAY_UPPER/lib32/libc.so.6 ]]
}

udev_tools_ready() {
	udev_have_qemu && { udev_m32 || udev_have_m32_overlay; }
}

# Run a command. If qemu or the i386 libraries are not on the host,
# run it where deps.sh has stacked those packages onto /usr.
udev_run() {
	if command -v qemu-system-i386 >/dev/null 2>&1 && udev_m32; then
		"$@"
		return
	fi
	if ! udev_tools_ready; then
		echo "qemu-system-i386 or gcc -m32 is missing. Run $COMPILE/deps.sh" >&2
		return 1
	fi
	local work merged rc
	work=$(mktemp -d "$COMPILE/.overlay/work.XXXXXX")
	merged=$(mktemp -d "$COMPILE/.overlay/merged.XXXXXX")
	# debug.sh kills this process group. A trapped TERM still has to
	# remove the mount dirs; an untrapped TERM would skip the rm below.
	trap 'rm -rf "$work" "$merged"; exit 143' INT TERM
	set +e
	unshare --user --map-root-user --mount --fork --kill-child -- \
		bash "$COMPILE/lib/ns-exec.sh" \
		"$OVERLAY_UPPER" "$work" "$merged" \
		"$@"
	rc=$?
	set -e
	trap - INT TERM
	rm -rf "$work" "$merged"
	return "$rc"
}

udev_rundir() {
	local stamp rundir n
	stamp=$(date +%Y%m%d-%H%M%S)
	rundir=$LOGS/$stamp
	n=0
	while [[ -e $rundir ]]; do
		n=$((n + 1))
		rundir=$LOGS/${stamp}-$n
	done
	mkdir -p "$rundir"
	ln -sfn "$rundir" "$LOGS/latest"
	printf '%s\n' "$rundir"
}

# Copy the disk images so a guest that writes the filesystem does not
# change build/tree/fs.img.
udev_copy_images() {
	local dest=$1
	cp -a "$TREE/fs.img" "$dest/fs.img"
	cp -a "$TREE/xv6.img" "$dest/xv6.img"
}

# Base qemu argv. Callers add -nographic, -serial, and -gdb.
# Images are the per-run copies, not the build tree.
udev_qemu_base() {
	local fs=$1 xv6=$2
	if [[ ! -x $QEMU_ARM ]]; then
		echo "local qemu-system-arm is not built. Run $OSDEV_ROOT/qemudev/compile/build.sh" >&2
		return 1
	fi
	UDEV_QEMU=(
		"$QEMU_ARM"
		-machine "pc,accel=${ACCEL}"
		-no-reboot
		-nic none
		-drive "file=${fs},index=1,media=disk,format=raw"
		-drive "file=${xv6},index=0,media=disk,format=raw"
		-smp "$CPUS"
		-m "$MEM"
	)
	if [[ -n ${QEMU_EXTRA:-} ]]; then
		local extra=()
		read -r -a extra <<<"$QEMU_EXTRA"
		UDEV_QEMU+=("${extra[@]}")
	fi
}
