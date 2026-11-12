#!/usr/bin/env bash
# GDB against the QEMU mps2-an385 image.
#
#   debug.sh            halt at main, serial in logs/<stamp>/serial.log
#   debug.sh qemu       foreground guest shell, gdb stub on :1234
#   debug.sh attach     attach gdb to a stub that is already listening
#   debug.sh batch      halt at main, backtrace, run hello, then exit
#
# GDB_PORT defaults to 1234. Helpers live in gdb/freertos.gdb (rtos-current, rtos-faults).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

mode=${1:-gdb}
case $mode in
gdb|qemu|attach|batch) ;;
-h|--help|help)
	sed -n '2,10p' "$0"
	exit 0
	;;
*)
	echo "usage: debug.sh [gdb|qemu|attach|batch]" >&2
	exit 2
	;;
esac

if [[ ! -f $ELF ]]; then
	echo "no image at $ELF; run build.sh first" >&2
	exit 1
fi

gdb_args() {
	local extra=()
	if [[ $mode == batch ]]; then
		extra=(-batch)
	fi
	rtosdev_run gdb-multiarch "${extra[@]}" \
		-ex "set pagination off" \
		-ex "set confirm off" \
		-ex "set architecture arm" \
		-ex "file $ELF" \
		-ex "target remote :$GDB_PORT" \
		-ex "source $COMPILE/gdb/freertos.gdb" \
		"$@"
}

if [[ $mode == attach ]]; then
	echo "attaching to 127.0.0.1:$GDB_PORT"
	gdb_args -ex "rtos-faults" -ex "break main"
	exit 0
fi

stamp=$(date +%Y%m%d-%H%M%S)
rundir=$LOGS/$stamp
n=0
while [[ -e $rundir ]]; do
	n=$((n + 1))
	rundir=$LOGS/${stamp}-$n
done
mkdir -p "$rundir"
ln -sfn "$rundir" "$LOGS/latest"

if [[ $mode == qemu ]]; then
	semi=rtosdev.shell=1
	serial=( -serial stdio )
else
	semi=rtosdev.exp=hello
	if [[ $mode == gdb ]]; then
		semi=rtosdev.shell=1
	fi
	serial=( -serial "file:$rundir/serial.log" )
fi

cmd=(
	-machine mps2-an385
	-cpu cortex-m3
	-kernel "$ELF"
	-display none
	-monitor none
	"${serial[@]}"
	-semihosting-config "enable=on,target=native,arg=${semi}"
	-no-reboot
	-gdb "tcp::$GDB_PORT"
)
if [[ $mode != qemu ]]; then
	cmd+=(-S)
fi
if [[ -n ${QEMU_EXTRA:-} ]]; then
	read -r -a extra <<<"$QEMU_EXTRA"
	cmd+=("${extra[@]}")
fi

{
	printf 'mode=debug-%s\n' "$mode"
	printf 'semi=%s\n' "$semi"
	printf 'gdb_port=%s\n' "$GDB_PORT"
	printf 'qemu='
	printf '%q ' "${cmd[@]}"
	printf '\n'
} >"$rundir/meta.txt"

if [[ $mode == qemu ]]; then
	echo "gdb stub: 127.0.0.1:$GDB_PORT"
	echo "in another terminal: $COMPILE/debug.sh attach"
	echo "poweroff shuts the guest down. Ctrl-C kills QEMU."
	exec "$COMPILE/lib/qemu-run.sh" "${cmd[@]}"
fi

echo "log: $rundir/serial.log"
echo "gdb stub: 127.0.0.1:$GDB_PORT"

set -m
"$COMPILE/lib/qemu-run.sh" "${cmd[@]}" </dev/null >"$rundir/qemu.log" 2>&1 &
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
	gdb_args \
		-ex "break main" \
		-ex "continue" \
		-ex "bt" \
		-ex "delete breakpoints" \
		-ex "continue"
	rc=$?
else
	echo "stopped at main. rtos-current works after the scheduler starts."
	echo "guest serial is $rundir/serial.log"
	gdb_args -ex "rtos-faults" -ex "break main" -ex "continue"
	rc=$?
fi
set -e
exit "$rc"
