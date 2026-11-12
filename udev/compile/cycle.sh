#!/usr/bin/env bash
# Install tools if needed, build, and boot the acceptance commands.
#
#   cycle.sh                 hello, then ls
#   cycle.sh usertests       one shell command instead
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

case ${1:-} in
-h|--help|help)
	sed -n '2,6p' "$0"
	exit 0
	;;
esac

echo "== deps =="
"$here/deps.sh"
echo "== build =="
"$here/build.sh"
if [[ $# -eq 0 ]]; then
	echo "== experiment: hello =="
	"$here/experiment.sh" hello
	echo "== experiment: ls =="
	"$here/experiment.sh" ls
else
	echo "== experiment: $1 =="
	"$here/experiment.sh" "$1"
fi
