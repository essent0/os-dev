#!/usr/bin/env bash
# Pack BusyBox, /init, and a copy of share/experiments into initramfs.cpio.gz.
# Experiments on the 9p share override this copy at boot, so editing a
# script does not require regenerating the image.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

# The guest is ARM. The host busybox is the wrong architecture, so the
# initramfs carries a static busybox built with the cross compiler.
busybox=$HOST_TOOLS/busybox
bb_ver=1.36.1
bb_src=$HOST_TOOLS/src/busybox-$bb_ver
if [[ ! -x $busybox ]] || ! file "$busybox" | grep -q 'ARM, EABI5' \
	|| ldd "$busybox" >/dev/null 2>&1; then
	echo "building static ARM busybox $bb_ver"
	mkdir -p "$HOST_TOOLS/src"
	tarball=$HOST_TOOLS/src/busybox-$bb_ver.tar.bz2
	if [[ ! -f $tarball ]]; then
		curl -fsSL -o "$tarball" "https://busybox.net/downloads/busybox-$bb_ver.tar.bz2"
	fi
	rm -rf "$bb_src"
	tar -C "$HOST_TOOLS/src" -xf "$tarball"
	make -C "$bb_src" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" defconfig
	sed -i \
		-e 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
		-e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
		"$bb_src/.config"
	lidev_run make -C "$bb_src" -j"$JOBS" ARCH=arm CROSS_COMPILE="$CROSS_COMPILE" busybox busybox.links
	cp "$bb_src/busybox" "$busybox"
	cp "$bb_src/busybox.links" "$HOST_TOOLS/busybox.links"
fi
if [[ ! -f $HOST_TOOLS/busybox.links ]]; then
	echo "missing $HOST_TOOLS/busybox.links" >&2
	exit 1
fi

gen=$HOST_TOOLS/gen_init_cpio
if [[ ! -x $gen ]]; then
	echo "compiling gen_init_cpio"
	gcc -O2 -o "$gen" "$SRC/usr/gen_init_cpio.c"
fi

list=$HOST_TOOLS/initramfs.list
{
	printf '%s\n' \
		"dir /bin 0755 0 0" \
		"dir /sbin 0755 0 0" \
		"dir /proc 0755 0 0" \
		"dir /sys 0755 0 0" \
		"dir /dev 0755 0 0" \
		"dir /tmp 1777 0 0" \
		"dir /host 0755 0 0" \
		"dir /usr 0755 0 0" \
		"dir /etc 0755 0 0" \
		"dir /root 0700 0 0" \
		"dir /experiments 0755 0 0" \
		"nod /dev/console 0600 0 0 c 5 1" \
		"nod /dev/null 0666 0 0 c 1 3" \
		"nod /dev/tty 0666 0 0 c 5 0" \
		"nod /dev/ttyS0 0600 0 0 c 4 64" \
		"slink /lib usr/lib 0777 0 0" \
		"slink /lib64 usr/lib64 0777 0 0" \
		"file /bin/busybox ${busybox} 0755 0 0" \
		"file /init ${GUEST}/init 0755 0 0"

	while IFS= read -r app; do
		case $app in
		busybox|''|*/*) continue ;;
		esac
		printf 'slink /bin/%s busybox 0777 0 0\n' "$app"
	done < <(sed 's|.*/||' "$HOST_TOOLS/busybox.links")

	shopt -s nullglob
	for exp in "$SHARE/experiments"/*; do
		if [[ -f $exp && -x $exp ]]; then
			printf 'file /experiments/%s %s 0755 0 0\n' "$(basename "$exp")" "$exp"
		fi
	done
} >"$list"

for need in sh mount poweroff reboot mkdir cat echo; do
	if ! grep -q "^slink /bin/${need} " "$list"; then
		echo "busybox is missing the $need applet" >&2
		exit 1
	fi
done

raw=${INITRAMFS%.gz}
"$gen" -o "$raw" "$list"
gzip -c -9 "$raw" >"$INITRAMFS"
rm -f "$raw"
ls -lh "$INITRAMFS"
