#!/bin/sh
# Extract the android14-6.1 GKI kernel Image that tests/vm/run-scx.sh boots,
# from the same pinned DDK image the module is built with.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["6.1"]["image"])' "$root/build/gki-targets.json")
mkdir -p "$root/out/gki/android14-6.1"
docker run --rm --platform linux/amd64 -v "$root:/module" "$image" sh -euc '
    llvm-objcopy -O binary -R .note -R .note.gnu.build-id -R .comment -S "$KDIR/vmlinux" \
        /module/out/gki/android14-6.1/Image'
ls -l "$root/out/gki/android14-6.1/Image"
