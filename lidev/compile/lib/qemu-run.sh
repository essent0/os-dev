#!/usr/bin/env bash
# timeout/qemu entry. Sources env.sh so qemu runs with the local toolchain.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/env.sh"
lidev_qemu "$@"
