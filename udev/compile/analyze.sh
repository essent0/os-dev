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
meta=$(dirname "$log")/meta.txt
: >"$summary"
say() { printf '%s\n' "$*" | tee -a "$summary"; }

mode=exp
expected=
if [[ -f $meta ]]; then
	mode=$(sed -n 's/^mode=//p' "$meta" | head -n 1)
	expected=$(sed -n 's/^name=//p' "$meta" | head -n 1)
fi

if grep -q 'init: starting sh' "$log"; then
	say "boot: init started sh"
else
	say "boot: did not reach the shell"
	fail=1
fi

if grep -q 'qemu timed out' "$log"; then
	say "boot: qemu timed out"
	fail=1
fi

if grep -E -q 'panic:|unexpected trap' "$log"; then
	say "boot: guest panic"
	grep -E -n 'panic:|unexpected trap' "$log" | head -n 20
	fail=1
fi

if grep -E -q 'exec .+ failed' "$log"; then
	say "boot: a command failed to exec"
	grep -E -n 'exec .+ failed' "$log" | head -n 20
	fail=1
fi

if [[ $mode == shell ]]; then
	if grep -q '\$ ' "$log"; then
		say "result: shell"
	else
		say "result: shell did not prompt"
		fail=1
	fi
elif grep -q 'UDEV_END ' "$log"; then
	got_expected=0
	while IFS= read -r rec; do
		name=${rec%% *}
		st=${rec##* }
		if [[ -n $expected && $name == "$expected" ]]; then
			got_expected=1
		fi
		if [[ $st == conflict ]]; then
			say "result: $name fail (conflicting status)"
			fail=1
		elif [[ $st == 0 && $fail -ne 0 ]]; then
			say "result: $name fail"
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
for name, st in re.findall(r"UDEV_END\s+([A-Za-z0-9_-]+)\s*status=(\d+)", text):
    if name not in seen:
        order.append(name)
        seen[name] = st
    elif seen[name] != st:
        seen[name] = "conflict"
for name in order:
    print(name, seen[name])
PY
)
	if [[ -n $expected && $got_expected -eq 0 ]]; then
		say "result: missing UDEV_END $expected"
		fail=1
	fi
else
	say "results: no UDEV_END lines"
	fail=1
fi

if [[ $fail -ne 0 ]]; then
	echo "---- last 40 log lines ----"
	tail -n 40 "$log"
	exit 1
fi
exit 0
