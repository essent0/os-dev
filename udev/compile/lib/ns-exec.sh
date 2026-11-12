#!/usr/bin/env bash
# Stack /.overlay/upper on /usr, then exec the command.
# Invoked by udev_run in env.sh as root inside a user namespace.
set -euo pipefail

upper=$1
work=$2
merged=$3
shift 3

# workdir must be empty on every mount. mktemp already made it empty.
mount -t overlay overlay \
	-o "lowerdir=/usr,upperdir=${upper},workdir=${work}" \
	"$merged"
mount --bind "$merged" /usr
exec "$@"
