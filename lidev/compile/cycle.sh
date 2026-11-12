#!/usr/bin/env bash
# Configure, compile, boot, run an experiment, then run kselftests.
#
#   cycle.sh                 experiment hello, then the default kselftests
#   cycle.sh dmesg           same, but run the dmesg experiment first
#   cycle.sh --reconfig      regenerate .config from config/qemu.fragment
#   cycle.sh help
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
	sed -n '2,8p' "$0"
	cat <<EOF

Scripts, in the order a change usually takes:

  deps.sh          flex, bison, libelf, qemu
  configure.sh     x86_64_defconfig + kvm guest + config/qemu.fragment
  build.sh         incremental make, default target bzImage
  initramfs.sh     busybox initramfs
  boot.sh          qemu. boot.sh shell drops to a serial shell
  experiment.sh    boot one program from share/experiments
  kselftest.sh     build and run a small kselftest set in the guest
  analyze.sh       read compile/logs/latest/serial.log

Edit share/experiments (or src/*.c and experiment.sh build). Kernel edits
are picked up by the next build.sh. Experiment script edits are picked up
on the next boot through the 9p share, without rebuilding the initramfs.
EOF
}

reconfig=()
exp=hello
while [[ $# -gt 0 ]]; do
	case $1 in
	-h|--help|help) usage; exit 0 ;;
	--reconfig) reconfig=(--reconfig); shift ;;
	*) exp=$1; shift ;;
	esac
done

echo "== deps =="
"$here/deps.sh"
echo "== configure =="
if [[ ! -f $here/build/.config || ${#reconfig[@]} -gt 0 ]]; then
	"$here/configure.sh" ${reconfig[@]+"${reconfig[@]}"}
else
	echo "keeping $here/build/.config"
fi
echo "== build =="
"$here/build.sh"
echo "== initramfs =="
"$here/initramfs.sh"
echo "== experiment: $exp =="
"$here/experiment.sh" "$exp"
echo "== kselftest =="
"$here/kselftest.sh"
