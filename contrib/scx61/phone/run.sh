#!/system/bin/sh
# su -c sh /sdcard/Download/scx/run.sh
# Loads the module (after a reboot) and gives each scheduler 10 s.
here=$(cd "$(dirname "$0")" && pwd)
t=/data/local/tmp/scx
mkdir -p $t && cp "$here"/* $t/ && chmod 755 $t/scx-run $t/scx_*
if [ ! -d /sys/module/droid_scx ]; then
    /data/adb/ksud insmod $t/droid-scx.ko gki=1 || { dmesg | grep droid-scx | tail -5; exit 1; }
fi
dmesg | grep droid-scx | tail -3
for s in scx_simple scx_bpfland scx_lavd; do
    echo "-- $s 시작"; log="$here/$s.log"
    args=; [ $s = scx_simple ] || args=-v
    $t/scx-run $t/$s $args > "$log" 2>&1 & pid=$!
    i=0; while [ $i -lt 180 ] && ! grep -q enabled /sys/kernel/sched_ext/state; do sleep 1; i=$((i + 1)); done
    up=$(cat /sys/kernel/sched_ext/state)
    [ "$up" = enabled ] && sleep 10
    kill -INT $pid 2>/dev/null; wait $pid
    echo "== $s: $up after ${i}s"
    grep -E "load failed|too large|processed [0-9]+ insns|EXIT|Error" "$log" | head -6
done
dmesg | grep -E "sched_ext|WARNING|BUG" | tail -10
