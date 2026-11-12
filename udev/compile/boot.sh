#!/usr/bin/env bash
# Boot build/tree xv6.img and fs.img on the local qemu-system-arm.
#
#   boot.sh                 echo a pass marker from the shell
#   boot.sh ls              run ls, then the marker
#   boot.sh 'cat README'    one shell command, then the marker
#   boot.sh shell           interactive shell (Ctrl-A X quits QEMU)
#
# Logs land in compile/logs/<timestamp>/ and compile/logs/latest.
# TIMEOUT bounds a one-shot boot (20s, or 240s for usertests).
# The shell does not time out. QEMU_EXTRA is split on spaces.
# CPUS defaults to 1. ACCEL defaults to tcg.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

mode=exp
raw=${1:-hello}
case $raw in
-h|--help|help)
	sed -n '2,12p' "$0"
	exit 0
	;;
shell) mode=shell ;;
esac

if [[ ! -f $TREE/kernel || ! -f $TREE/xv6.img || ! -f $TREE/fs.img ]]; then
	echo "no xv6 images under $TREE; run build.sh first" >&2
	exit 1
fi

name=hello
lines=()
if [[ $mode == exp ]]; then
	case $raw in
	hello)
		name=hello
		lines=("echo UDEV_END hello status=0")
		;;
	ls)
		name=ls
		lines=("ls" "echo UDEV_END ls status=0")
		;;
	cat)
		name=cat
		lines=("cat README" "echo UDEV_END cat status=0")
		;;
	usertests)
		name=usertests
		lines=("usertests" "echo UDEV_END usertests status=0")
		;;
	*)
		if [[ $raw == *$'\n'* || -z $raw ]]; then
			echo "shell command must be one line: $raw" >&2
			exit 2
		fi
		name=${raw%% *}
		name=${name//[^A-Za-z0-9_-]/_}
		lines=("$raw" "echo UDEV_END ${name} status=0")
		;;
	esac
fi

if [[ $mode == exp && -z ${TIMEOUT:-} ]]; then
	if [[ $name == usertests ]]; then
		TIMEOUT=240
	else
		TIMEOUT=20
	fi
fi

rundir=$(udev_rundir)
udev_copy_images "$rundir"

{
	printf 'mode=%s\n' "$mode"
	printf 'name=%s\n' "$name"
	printf 'cpus=%s\n' "$CPUS"
	printf 'accel=%s\n' "$ACCEL"
	if [[ $mode == exp ]]; then
		printf 'timeout=%s\n' "$TIMEOUT"
		printf 'lines='
		printf '%q ' "${lines[@]}"
		printf '\n'
	fi
} >"$rundir/meta.txt"

echo "log: $rundir/serial.log"

if [[ $mode == shell ]]; then
	udev_qemu_base "$rundir/fs.img" "$rundir/xv6.img"
	cmd=("${UDEV_QEMU[@]}" -nographic)
	echo "xv6 shell. Ctrl-A X exits QEMU."
	printf 'qemu=' >>"$rundir/meta.txt"
	printf '%q ' "${cmd[@]}" >>"$rundir/meta.txt"
	printf '\n' >>"$rundir/meta.txt"
	cmd_str=$(printf '%q ' "${cmd[@]}")
	if command -v script >/dev/null 2>&1; then
		udev_run script -qef -c "$cmd_str" "$rundir/serial.log"
	else
		udev_run "${cmd[@]}"
	fi
	exit 0
fi

line_args=()
for line in "${lines[@]}"; do
	line_args+=(--line "$line")
done

set +e
udev_run python3 "$COMPILE/lib/guest-run.py" \
	--timeout "$TIMEOUT" \
	--log "$rundir/serial.log" \
	--fs "$rundir/fs.img" \
	--xv6 "$rundir/xv6.img" \
	--smp "$CPUS" \
	--mem "$MEM" \
	--accel "$ACCEL" \
	"${line_args[@]}"
rc=$?
set -e
exit "$rc"
