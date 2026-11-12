#!/usr/bin/env bash
# Install tools if needed, build, boot hello and ping.
#
#   cycle.sh
#   cycle.sh tasks
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

exp=${1:-hello,ping}
case $exp in
-h|--help|help)
	sed -n '2,6p' "$0"
	exit 0
	;;
esac

echo "== deps =="
"$here/deps.sh"
echo "== build =="
"$here/build.sh"
echo "== experiment: $exp =="
"$here/experiment.sh" "$exp"
