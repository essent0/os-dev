#!/usr/bin/env bash
# Compile Linux, QEMU (arm), FreeRTOS, and xv6.
#
#   ./buildall.sh
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

run() {
	echo "==> $*"
	"$@"
}

run "$root/lidev/compile/deps.sh"
run "$root/lidev/compile/configure.sh"
run "$root/lidev/compile/build.sh"
run "$root/lidev/compile/initramfs.sh"
run "$root/qemudev/compile/build.sh"
run "$root/rtosdev/compile/deps.sh"
run "$root/rtosdev/compile/build.sh"
run "$root/udev/compile/deps.sh"
run "$root/udev/compile/build.sh"

echo "buildall: linux, qemu, freertos, xv6"
