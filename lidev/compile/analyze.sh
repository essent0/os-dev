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

if grep -q '^LIDEV_BOOT ' "$log"; then
	say "boot: $(grep -m1 '^LIDEV_BOOT ' "$log" | tr -d '\r' | sed 's/^LIDEV_BOOT //')"
else
	say "boot: did not reach userspace"
	fail=1
fi

if grep -q 'qemu timed out' "$log"; then
	say "boot: qemu timed out"
	fail=1
fi

if grep -E -q 'Kernel panic|Oops:|kernel BUG|BUG:' "$log"; then
	say "boot: kernel fault"
	grep -E -n 'Kernel panic|Oops:|kernel BUG|BUG:' "$log" | head -n 20
	fail=1
fi

if grep -q 'LIDEV_END ' "$log"; then
	while IFS= read -r rec; do
		name=${rec%% *}
		st=${rec##* }
		if [[ $st == 0 ]]; then
			say "result: $name pass"
		else
			say "result: $name fail (status $st)"
			fail=1
		fi
	done < <(python3 - "$log" <<'PY'
import re, sys
text = open(sys.argv[1], errors="replace").read().replace("\r", "")
# Drop the ttyS0 timestamp prefix, including lines copied from /dev/kmsg.
text = re.sub(r"(?m)^[ \t]*\[[ \t]*[0-9]+\.[0-9]+\][ \t]*", "", text)
# A printk can also land in the middle of a userspace write.
text = re.sub(r"\[[ \t]*[0-9]+\.[0-9]+\][^\n]*", "\n", text)
seen = {}
order = []
for name, st in re.findall(r"LIDEV_END\s+([A-Za-z0-9_.,+-]+)\s*status=(\d+)", text):
    if name not in seen:
        order.append(name)
        seen[name] = st
    elif seen[name] != st:
        seen[name] = "conflict"
for name in order:
    print(name, seen[name])
PY
)
else
	say "results: no LIDEV_END lines"
	fail=1
fi

if grep -q '# Totals:' "$log"; then
	if awk '
		/# Totals: pass:/ {
			for (i = 1; i <= NF; i++) {
				n = split($i, a, ":")
				if (n == 2 && a[1] ~ /^(pass|fail|skip|error|xfail|xpass)$/)
					sum[a[1]] += a[2]
			}
		}
		END {
			printf "kselftest: pass:%d fail:%d skip:%d error:%d\n", \
				sum["pass"]+0, sum["fail"]+0, sum["skip"]+0, sum["error"]+0
			if ((sum["fail"]+0) > 0 || (sum["error"]+0) > 0)
				exit 1
		}
	' "$log"; then
		:
	else
		fail=1
	fi
fi

warns=$(grep -c 'WARNING:' "$log" || true)
if [[ ${warns:-0} -gt 0 ]]; then
	say "warnings: $warns (reported, not failed)"
fi

if [[ $fail -ne 0 ]]; then
	say "---- tail ----"
	tail -n 30 "$log" | tee -a "$summary"
	say "log: $log"
	exit 1
fi
say "log: $log"
exit 0
