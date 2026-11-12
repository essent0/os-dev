#!/usr/bin/env bash
# Run an experiment in the guest, then summarize the serial log.
#
#   experiment.sh                 boot and run hello
#   experiment.sh NAME            boot and run share/experiments/NAME
#   experiment.sh NAME,OTHER      run several in one boot
#   experiment.sh build NAME      gcc -static share/experiments/src/NAME.c, then boot it
#   experiment.sh list
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

usage() {
	sed -n '2,9p' "$0"
}

case ${1:-} in
-h|--help|help) usage; exit 0 ;;
list)
	find "$SHARE/experiments" -maxdepth 1 -type f -printf '%f\n' | sort
	exit 0
	;;
build)
	name=${2:?usage: experiment.sh build NAME}
	src=$SHARE/experiments/src/$name.c
	if [[ ! -f $src ]]; then
		echo "missing $src" >&2
		exit 1
	fi
	gcc -static -O2 -Wall -Wextra -o "$SHARE/experiments/$name" "$src"
	shift
	;;
esac

exp=${1:-hello}
if [[ ! $exp =~ ^[A-Za-z0-9_.,+-]+$ ]]; then
	echo "bad experiment name: $exp" >&2
	exit 2
fi

boot_rc=0
"$COMPILE/boot.sh" "$exp" || boot_rc=$?
set +e
"$COMPILE/analyze.sh"
an_rc=$?
set -e
if [[ $boot_rc -eq 124 ]]; then
	exit 124
fi
exit "$an_rc"
