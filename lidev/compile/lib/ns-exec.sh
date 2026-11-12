#!/usr/bin/env bash
# Enter a mount namespace where /.overlay/upper is stacked on /usr,
# then exec the requested command. Invoked by lidev_run in env.sh.
set -euo pipefail

upper=$1
work=$2
merged=$3
shift 3

mount -t overlay overlay \
	-o "lowerdir=/usr,upperdir=${upper},workdir=${work}" \
	"$merged"
mount --bind "$merged" /usr
exec "$@"
