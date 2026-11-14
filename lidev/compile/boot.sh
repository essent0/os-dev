#!/usr/bin/env bash
# Boot compile/build's zImage on the local qemu-system-arm (virt, cortex-a15).
#
#   boot.sh                 run the hello experiment
#   boot.sh NAME            run share/experiments/NAME (commas allowed)
#   boot.sh shell           interactive serial shell
#   boot.sh kselftest       run share/kselftest inside the guest
#
# Logs land in compile/logs/<timestamp>/ and compile/logs/latest.
# TIMEOUT seconds (default 120, or 600 for kselftest) kills a hung guest.
# QEMU_EXTRA is split on spaces and appended to the qemu command.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

mode=exp
exp=hello
case ${1:-} in
"") ;;
shell) mode=shell ;;
kselftest) mode=kselftest ;;
-h|--help)
	sed -n '2,12p' "$0"
	exit 0
	;;
*) exp=$1 ;;
esac

image=$BUILD/arch/arm/boot/zImage
if [[ ! -f $image ]]; then
	echo "no zImage at $image; run build.sh first" >&2
	exit 1
fi
if [[ ! -f $INITRAMFS ]]; then
	echo "no initramfs at $INITRAMFS; run initramfs.sh first" >&2
	exit 1
fi

if [[ $mode == exp && ! $exp =~ ^[A-Za-z0-9_.,+-]+$ ]]; then
	echo "experiment name must be letters, numbers, ., _, +, - or commas: $exp" >&2
	exit 2
fi

stamp=$(date +%Y%m%d-%H%M%S)
rundir=$LOGS/$stamp
mkdir -p "$rundir" "$SHARE" "$SHARE/results"
ln -sfn "$rundir" "$LOGS/latest"

append="console=ttyAMA0,115200 earlycon loglevel=7 panic=1 rdinit=/init"
case $mode in
shell) append+=" lidev.shell=1" ;;
kselftest) append+=" lidev.kselftest=1" ;;
exp) append+=" lidev.exp=${exp}" ;;
esac

# This host is not an ARM machine. qemu-system-arm emulates the guest.
accel=tcg
cpu=cortex-a15

if [[ $mode == kselftest ]]; then
	: "${TIMEOUT:=600}"
else
	: "${TIMEOUT:=120}"
fi
if [[ $accel == tcg && $TIMEOUT -lt 600 ]]; then
	TIMEOUT=600
fi

# virtio-mmio. The virt machine's PCI ECAM sits above 4G, and this
# 32-bit kernel does not bring that host bridge up.
fs=(
	-fsdev "local,id=hostshare,path=${SHARE},security_model=mapped-file"
	-device "virtio-9p-device,fsdev=hostshare,mount_tag=hostshare"
)
if [[ $mode == kselftest ]]; then
	fs+=(
		-fsdev "local,id=hostusr,path=/usr,security_model=none,readonly=on"
		-device "virtio-9p-device,fsdev=hostusr,mount_tag=hostusr"
	)
fi

extra=()
if [[ -n ${QEMU_EXTRA:-} ]]; then
	read -r -a extra <<<"$QEMU_EXTRA"
fi

cmd=(
	-machine "virt,accel=${accel}"
	-cpu "$cpu"
	-m "$MEM"
	-smp "$SMP"
	-kernel "$image"
	-initrd "$INITRAMFS"
	-append "$append"
	-display none
	-vga none
	-serial stdio
	-monitor none
	-no-reboot
	"${fs[@]}"
	"${extra[@]}"
)

{
	printf 'mode=%s\n' "$mode"
	printf 'exp=%s\n' "$exp"
	printf 'accel=%s\n' "$accel"
	printf 'timeout=%s\n' "$TIMEOUT"
	printf 'append=%s\n' "$append"
	printf 'qemu='
	printf '%q ' "${cmd[@]}"
	printf '\n'
} >"$rundir/meta.txt"

echo "log: $rundir/serial.log"
echo "accel: $accel  mem: ${MEM}M  smp: $SMP  timeout: ${TIMEOUT}s"

set +e
if [[ $mode == shell ]]; then
	"$COMPILE/lib/qemu-run.sh" "${cmd[@]}" 2>&1 | tee "$rundir/serial.log"
else
	# stdin stays closed. timeout puts QEMU in its own process group, and a
	# read from the terminal there stops the VM before it prints anything.
	timeout "$TIMEOUT" "$COMPILE/lib/qemu-run.sh" "${cmd[@]}" \
		</dev/null 2>&1 | tee "$rundir/serial.log"
fi
rc=${PIPESTATUS[0]}
set -e

if [[ $rc -eq 124 ]]; then
	echo "qemu timed out after ${TIMEOUT}s" | tee -a "$rundir/serial.log"
fi
echo "qemu exit: $rc"
exit "$rc"
