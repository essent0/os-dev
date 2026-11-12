#!/usr/bin/env bash
# Rebuild, boot a shell command, then summarize the serial log.
#
#   experiment.sh                 hello
#   experiment.sh ls
#   experiment.sh 'cat README'
#   experiment.sh usertests
#   experiment.sh list
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

case ${1:-} in
-h|--help|help)
	sed -n '2,8p' "$0"
	exit 0
	;;
list)
	printf '%s\n' hello ls cat usertests
	exit 0
	;;
esac

exp=${1:-hello}
if [[ $exp == *$'\n'* ]]; then
	echo "bad command: $exp" >&2
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
