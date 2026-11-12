#!/usr/bin/env bash
# Copy xv6-public into build/tree and build xv6.img and fs.img there.
# xv6-public is not modified. The xv6 makefile has no out-of-tree mode.
#
#   build.sh
#   build.sh clean
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
	sed -n '2,6p' "$0"
	exit 0
fi

if [[ ${1:-} == clean ]]; then
	rm -rf "$BUILD"
	echo "removed $BUILD"
	exit 0
fi

if [[ ! -f $SRC/Makefile ]]; then
	echo "no xv6 tree at $SRC" >&2
	exit 1
fi
if ! command -v rsync >/dev/null 2>&1; then
	echo "rsync is required" >&2
	exit 1
fi
if ! command -v perl >/dev/null 2>&1; then
	echo "perl is required (vectors.pl, sign.pl). Run deps.sh" >&2
	exit 1
fi
if ! udev_m32 && ! udev_have_m32_overlay; then
	echo "gcc -m32 failed. Run deps.sh" >&2
	exit 1
fi

mkdir -p "$TREE"
# Generated files stay in the tree so the next make is incremental.
# --delete drops sources that disappeared from xv6-public.
rsync -a --delete \
	--exclude .git \
	--exclude '*.o' \
	--exclude '*.d' \
	--exclude '*.asm' \
	--exclude '*.sym' \
	--exclude '*.img' \
	--exclude '_*' \
	--exclude kernel \
	--exclude kernelmemfs \
	--exclude bootblock \
	--exclude entryother \
	--exclude initcode \
	--exclude initcode.out \
	--exclude mkfs \
	--exclude vectors.S \
	--exclude .gdbinit \
	"$SRC/" "$TREE/"

# Current gcc rejects mp.c under -Werror (array-bounds). Drop -Werror in
# the build copy only. xv6-public/Makefile is left as it is.
python3 - "$TREE/Makefile" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    " -Werror ",
    " -Wno-array-bounds -Wno-infinite-recursion ",
)
needle = "LDFLAGS += -m $(shell $(LD) -V | grep elf_i386 2>/dev/null | head -n 1)\n"
extra = (
    "LDFLAGS += $(shell $(LD) --help 2>/dev/null "
    "| grep -q no-warn-rwx-segments && echo --no-warn-rwx-segments)\n"
)
if "no-warn-rwx-segments" not in text and needle in text:
    text = text.replace(needle, needle + extra, 1)
path.write_text(text)
PY

echo "building in $TREE"
if udev_m32; then
	make -C "$TREE" -j1 xv6.img fs.img
else
	udev_run make -C "$TREE" -j1 xv6.img fs.img
fi

[[ -f $TREE/kernel && -f $TREE/xv6.img && -f $TREE/fs.img ]]
echo "kernel:  $TREE/kernel"
echo "xv6.img: $TREE/xv6.img"
echo "fs.img:  $TREE/fs.img"
