#!/usr/bin/env bash
# Build a few kselftests and run them in the guest against this kernel.
#
#   kselftest.sh                  build if needed, boot, run, summarize
#   kselftest.sh build            install tests only
#   kselftest.sh rebuild          install even if the target list is unchanged
#   kselftest.sh run              boot tests already installed
#   kselftest.sh proc size        install and run those targets
#
# Default targets are "size proc". Override with arguments or TARGETS="proc".
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

usage() {
	sed -n '2,11p' "$0"
}

action=cycle
force=0
case ${1:-} in
-h|--help|help) usage; exit 0 ;;
build) action=build; shift ;;
rebuild) action=build; force=1; shift ;;
run) action=run; shift ;;
esac

if [[ $# -gt 0 ]]; then
	targets="$*"
	if [[ $action == cycle ]]; then
		force=1
	fi
else
	targets=${TARGETS:-size proc}
fi

stamp=$SHARE/kselftest/.targets
need_build=0
case $action in
build) need_build=1 ;;
run) need_build=0 ;;
cycle)
	if [[ $force -eq 1 || ! -x $SHARE/kselftest/run_kselftest.sh ]]; then
		need_build=1
	elif [[ $(cat "$stamp" 2>/dev/null || true) != "$targets" ]]; then
		need_build=1
	fi
	;;
esac

if [[ $need_build -eq 1 ]]; then
	if [[ ! -f $BUILD/.config ]]; then
		echo "no kernel config; run configure.sh first" >&2
		exit 1
	fi
	echo "kselftest targets: $targets"
	lidev_run make -C "$SRC" O="$BUILD" headers
	rm -rf "$SHARE/kselftest"
	mkdir -p "$SHARE/kselftest"
	lidev_run make -C "$SRC/tools/testing/selftests" \
		O="$BUILD" \
		TARGETS="$targets" \
		KSFT_INSTALL_PATH="$SHARE/kselftest" \
		install
	printf '%s\n' "$targets" >"$stamp"
	echo "installed: $SHARE/kselftest"
fi

if [[ $action == build ]]; then
	exit 0
fi

if [[ ! -x $SHARE/kselftest/run_kselftest.sh ]]; then
	echo "kselftests are not installed. Run kselftest.sh build" >&2
	exit 1
fi

export TIMEOUT=${TIMEOUT:-600}
boot_rc=0
"$COMPILE/boot.sh" kselftest || boot_rc=$?
set +e
"$COMPILE/analyze.sh"
an_rc=$?
set -e
if [[ $boot_rc -eq 124 ]]; then
	exit 124
fi
exit "$an_rc"
