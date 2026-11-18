#!/bin/sh
# The VM part of run-scx.sh on a host with qemu-system-aarch64 and no
# Docker. The initramfs comes from "DS_SCX_PACK=out/scx/initramfs
# tests/vm/run-scx.sh" on a machine that has Docker.
#
#   run-scx-qemu.sh IMAGE INITRAMFS [SCHEDULER]
#
# SCHEDULER tries that one scheduler and skips the port tests.
set -eu
[ $# -ge 2 ] || { sed -n 2,8p "$0"; exit 2; }
log=${DS_SCX_LOG:-console.log}
rm -f "$log"
timeout 900 qemu-system-aarch64 -machine virt -cpu max -m 1024 -smp 2 \
    -nographic -monitor none -nic none -no-reboot -kernel "$1" -initrd "$2" \
    -append "console=ttyAMA0 rdinit=/init nokaslr selinux=0 panic=-1 ${3:+scx_try=$3}" >"$log" 2>&1 || true
grep -aE "^(SCX|PORT|TRY|state=|attaches=|kfunc_errors=|DS_SCX|libbpf)" "$log" || true
if ! grep -q "^DS_SCX_VM_RESULT=0" "$log" ||
   grep -Eq "WARNING: CPU:|BUG:|Oops:|Kernel panic|bad: scheduling|Unable to handle|rcu.*stall" "$log"; then
    tail -80 "$log"; exit 1
fi
