#!/usr/bin/env bash
# Incremental out-of-tree build of FreeRTOS-Kernel for QEMU mps2-an385.
#
#   build.sh            link build/freertos.elf
#   build.sh clean      delete build/
#   build.sh -j4        extra make arguments are passed through
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
	sed -n '2,7p' "$0"
	exit 0
fi

rtosdev_run make -C "$COMPILE" -j"$JOBS" "$@"

if [[ ${1:-} == clean ]]; then
	exit 0
fi

if [[ -f $ELF ]]; then
	echo "elf: $ELF"
	echo "map: $BUILD/freertos.map"
fi
