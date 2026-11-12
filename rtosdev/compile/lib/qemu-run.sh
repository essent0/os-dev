#!/usr/bin/env bash
# timeout(1) needs a real executable. This sources env.sh and starts QEMU.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/env.sh"

if [[ ! -x $QEMU_ARM ]]; then
	echo "local qemu-system-arm is not built. Run $OSDEV_ROOT/qemudev/compile/build.sh" >&2
	exit 1
fi

if command -v stdbuf >/dev/null 2>&1; then
	rtosdev_run stdbuf -oL -eL "$QEMU_ARM" "$@"
else
	rtosdev_run "$QEMU_ARM" "$@"
fi
