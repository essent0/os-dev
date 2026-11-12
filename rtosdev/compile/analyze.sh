#!/usr/bin/env bash
# Summarize a QEMU serial log.
#   analyze.sh                  latest run
#   analyze.sh path/to/serial.log
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

log=${1:-$LOGS/latest/serial.log}
if [[ $log == -h || $log == --help ]]; then
	echo "usage: analyze.sh [serial.log]"
	exit 0
fi
if [[ ! -f $log ]]; then
	echo "no serial log at $log" >&2
	exit 1
fi

fail=0
summary=$(dirname "$log")/summary.txt
: >"$summary"
say() { printf '%s\n' "$*" | tee -a "$summary"; }

if grep -q 'RTOSDEV_BOOT ' "$log"; then
	say "boot: $(grep -m1 'RTOSDEV_BOOT ' "$log" | tr -d '\r' | sed 's/^RTOSDEV_BOOT //')"
else
	say "boot: did not reach the guest"
	fail=1
fi

if grep -q 'qemu timed out' "$log"; then
	say "boot: qemu timed out"
	fail=1
fi

if grep -E -q 'RTOSDEV_FAULT|RTOSDEV_ASSERT' "$log"; then
	say "boot: guest fault"
	grep -E -n 'RTOSDEV_FAULT|RTOSDEV_ASSERT' "$log" | head -n 20
	fail=1
fi

if grep -q 'RTOSDEV_END ' "$log"; then
	while IFS= read -r rec; do
		name=${rec%% *}
		st=${rec##* }
		if [[ $st == conflict ]]; then
			say "result: $name fail (conflicting status)"
			fail=1
		elif [[ $st == 0 ]]; then
			say "result: $name pass"
		else
			say "result: $name fail (status $st)"
			fail=1
		fi
	done < <(python3 - "$log" <<'PY'
import re, sys
text = open(sys.argv[1], errors="replace").read().replace("\r", "")
seen = {}
order = []
for name, st in re.findall(r"RTOSDEV_END\s+([A-Za-z0-9_-]+)\s*status=(\d+)", text):
    if name not in seen:
        order.append(name)
        seen[name] = st
    elif seen[name] != st:
        seen[name] = "conflict"
for name in order:
    print(name, seen[name])
PY
)
elif grep -q 'RTOSDEV_SHELL' "$log"; then
	say "result: shell"
else
	say "results: no RTOSDEV_END lines"
	fail=1
fi

if [[ $fail -ne 0 ]]; then
	echo "---- last 30 log lines ----"
	tail -n 30 "$log"
	exit 1
fi
exit 0
