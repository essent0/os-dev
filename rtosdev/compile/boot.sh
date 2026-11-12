#!/usr/bin/env bash
# Boot build/freertos.elf on the local qemu-system-arm (mps2-an385).
#
#   boot.sh                 run the hello experiment, then power off
#   boot.sh NAME            run one experiment (comma or + separates several)
#   boot.sh shell           interactive UART shell
#   boot.sh run             heartbeat once a second until Ctrl-C
#
# Logs land in compile/logs/<timestamp>/ and compile/logs/latest.
# TIMEOUT seconds (default 30) kills a one-shot guest. Shell and run wait.
# QEMU_EXTRA is split on spaces and appended to the qemu command.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

mode=exp
exp=hello
case ${1:-} in
"") ;;
shell) mode=shell ;;
run) mode=run ;;
-h|--help)
	sed -n '2,12p' "$0"
	exit 0
	;;
*) exp=$1 ;;
esac

if [[ ! -f $ELF ]]; then
	echo "no image at $ELF; run build.sh first" >&2
	exit 1
fi

if [[ $mode == exp && ! $exp =~ ^[A-Za-z0-9_,+-]+$ ]]; then
	echo "experiment name must be letters, numbers, _, -, +, or commas: $exp" >&2
	exit 2
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

# qemu splits -semihosting-config on commas, so '+' joins experiment names.
semi_arg=rtosdev.exp=${exp//,/+}
case $mode in
shell) semi_arg=rtosdev.shell=1 ;;
run) semi_arg=rtosdev.run=1 ;;
esac

cmd=(
	-machine mps2-an385
	-cpu cortex-m3
	-kernel "$ELF"
	-display none
	-monitor none
	-serial stdio
	-semihosting-config "enable=on,target=native,arg=${semi_arg}"
	-no-reboot
)

extra=()
if [[ -n ${QEMU_EXTRA:-} ]]; then
	read -r -a extra <<<"$QEMU_EXTRA"
	cmd+=("${extra[@]}")
fi

{
	printf 'mode=%s\n' "$mode"
	printf 'exp=%s\n' "$exp"
	printf 'timeout=%s\n' "${TIMEOUT}"
	printf 'semi=%s\n' "$semi_arg"
	printf 'qemu='
	printf '%q ' "${cmd[@]}"
	printf '\n'
} >"$rundir/meta.txt"

echo "log: $rundir/serial.log"
if [[ $mode == exp ]]; then
	echo "mode: $exp  timeout: ${TIMEOUT}s"
else
	echo "mode: $mode"
fi

set +e
if [[ $mode == exp ]]; then
	# stdin stays closed. timeout puts QEMU in its own process group, and a
	# read from the terminal there stops the guest before it prints anything.
	timeout "$TIMEOUT" "$COMPILE/lib/qemu-run.sh" "${cmd[@]}" \
		</dev/null 2>&1 | tee "$rundir/serial.log"
else
	"$COMPILE/lib/qemu-run.sh" "${cmd[@]}" 2>&1 | tee "$rundir/serial.log"
fi
rc=${PIPESTATUS[0]}
set -e

if [[ $rc -eq 124 ]]; then
	echo "qemu timed out after ${TIMEOUT}s" | tee -a "$rundir/serial.log"
fi
echo "qemu exit: $rc"
exit "$rc"
