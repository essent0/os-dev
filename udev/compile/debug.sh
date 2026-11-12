#!/usr/bin/env bash
# GDB against the QEMU xv6 image.
#
#   debug.sh            halt at kernel main, serial in logs/<stamp>/serial.log
#   debug.sh qemu       foreground xv6 shell, gdb stub on :1234
#   debug.sh attach     attach gdb to a stub that is already listening
#   debug.sh batch      halt at kernel main, print a backtrace, exit
#
# GDB_PORT defaults to 1234. The stop hook is gdb/xv6.gdb (i8086 vs i386).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

mode=${1:-gdb}
case $mode in
gdb|qemu|attach|batch) ;;
-h|--help|help)
	sed -n '2,9p' "$0"
	exit 0
	;;
*)
	echo "usage: debug.sh [gdb|qemu|attach|batch]" >&2
	exit 2
	;;
esac

if [[ ! -f $TREE/kernel ]]; then
	echo "no kernel at $TREE/kernel; run build.sh first" >&2
	exit 1
fi
if ! command -v gdb >/dev/null 2>&1; then
	echo "gdb is missing. Run deps.sh" >&2
	exit 1
fi

gdb_args() {
	local extra=()
	if [[ $mode == batch ]]; then
		extra=(-batch)
	fi
	gdb -nx "${extra[@]}" \
		-ex "set pagination off" \
		-ex "set confirm off" \
		-ex "file $TREE/kernel" \
		-ex "directory $TREE" \
		"$@"
}

if [[ $mode == attach ]]; then
	echo "attaching to 127.0.0.1:$GDB_PORT"
	gdb_args \
		-ex "source $COMPILE/gdb/xv6.gdb" \
		-ex "target remote :$GDB_PORT"
	exit 0
fi

rundir=$(udev_rundir)
udev_copy_images "$rundir"
udev_qemu_base "$rundir/fs.img" "$rundir/xv6.img"

if [[ $mode == qemu ]]; then
	cmd=("${UDEV_QEMU[@]}" -nographic -gdb "tcp::$GDB_PORT")
else
	cmd=(
		"${UDEV_QEMU[@]}"
		-display none
		-monitor none
		-serial "file:$rundir/serial.log"
		-S
		-gdb "tcp::$GDB_PORT"
	)
fi

{
	printf 'mode=debug-%s\n' "$mode"
	printf 'name=debug\n' 
	printf 'gdb_port=%s\n' "$GDB_PORT"
	printf 'qemu='
	printf '%q ' "${cmd[@]}"
	printf '\n'
} >"$rundir/meta.txt"

if [[ $mode == qemu ]]; then
	echo "gdb stub: 127.0.0.1:$GDB_PORT"
	echo "in another terminal: $COMPILE/debug.sh attach"
	echo "Ctrl-A X exits QEMU."
	cmd_str=$(printf '%q ' "${cmd[@]}")
	if command -v script >/dev/null 2>&1; then
		exec udev_run script -qef -c "$cmd_str" "$rundir/serial.log"
	fi
	exec udev_run "${cmd[@]}"
fi

echo "log: $rundir/serial.log"
echo "gdb stub: 127.0.0.1:$GDB_PORT"

set -m
udev_run "${cmd[@]}" </dev/null >"$rundir/qemu.log" 2>&1 &
qpid=$!
cleanup() {
	kill -TERM -"$qpid" 2>/dev/null || kill "$qpid" 2>/dev/null || true
	wait "$qpid" 2>/dev/null || true
}
trap cleanup EXIT

if ! python3 - "$GDB_PORT" "$qpid" <<'PY'
import os, socket, sys, time
port = int(sys.argv[1])
pid = int(sys.argv[2])
for _ in range(50):
    if not os.path.exists(f"/proc/{pid}"):
        sys.exit(1)
    s = socket.socket()
    s.settimeout(0.2)
    try:
        s.connect(("127.0.0.1", port))
        s.close()
        sys.exit(0)
    except OSError:
        time.sleep(0.1)
sys.exit(1)
PY
then
	echo "qemu did not open gdb port $GDB_PORT" >&2
	cat "$rundir/qemu.log" >&2 || true
	exit 1
fi

set +e
if [[ $mode == batch ]]; then
	# timeout cannot call a shell function, so the gdb argv is repeated here.
	timeout 30 gdb -nx -batch \
		-ex "set pagination off" \
		-ex "set confirm off" \
		-ex "file $TREE/kernel" \
		-ex "directory $TREE" \
		-ex "target remote :$GDB_PORT" \
		-ex "break main" \
		-ex "continue" \
		-ex "bt" \
		-ex "printf \"debug_rc: hit main\\n\"" \
		-ex "quit" | tee "$rundir/gdb.log"
	rc=${PIPESTATUS[0]}
	if [[ $rc -eq 0 ]] && ! grep -q 'debug_rc: hit main' "$rundir/gdb.log"; then
		rc=1
	fi
else
	echo "stopped before kernel main. continue to boot."
	echo "guest serial is $rundir/serial.log"
	gdb_args \
		-ex "source $COMPILE/gdb/xv6.gdb" \
		-ex "target remote :$GDB_PORT" \
		-ex "break main"
	rc=$?
fi
set -e
exit "$rc"
