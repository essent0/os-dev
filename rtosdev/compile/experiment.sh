#!/usr/bin/env bash
# Rebuild, boot an experiment, then summarize the serial log.
#
#   experiment.sh                 hello
#   experiment.sh NAME            one experiment
#   experiment.sh hello,ping      several in one boot
#   experiment.sh build NAME      rebuild (source is share/experiments/src/NAME.c) and boot
#   experiment.sh list
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

usage() {
	sed -n '2,9p' "$0"
}

case ${1:-} in
-h|--help|help) usage; exit 0 ;;
list)
	find "$SHARE/experiments/src" -maxdepth 1 -name '*.c' -printf '%f\n' \
		| sed 's/\.c$//' | sort
	exit 0
	;;
build)
	name=${2:?usage: experiment.sh build NAME}
	src=$SHARE/experiments/src/$name.c
	if [[ ! -f $src ]]; then
		echo "missing $src" >&2
		exit 1
	fi
	shift
	;;
esac

exp=${1:-hello}
if [[ ! $exp =~ ^[A-Za-z0-9_,+-]+$ ]]; then
	echo "bad experiment name: $exp" >&2
	exit 2
fi

"$COMPILE/build.sh"

boot_rc=0
"$COMPILE/boot.sh" "$exp" || boot_rc=$?
set +e
"$COMPILE/analyze.sh"
an_rc=$?
set -e
if [[ $boot_rc -eq 124 ]]; then
	exit 124
fi
if [[ $an_rc -ne 0 ]]; then
	exit "$an_rc"
fi
exit "$boot_rc"
