#!/usr/bin/env bash
# set-governor.sh <governor>
# Sets CPU governor for all cores and writes a trigger file that
# Services/Battery.qml is tail -f-ing to pick up the change live.

GOVERNOR="$1"
[ -z "$GOVERNOR" ] && exit 1

mkdir -p /tmp/quickshell

# Apply to all CPU cores
for CPU in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
    echo "$GOVERNOR" | sudo tee "$CPU" > /dev/null
done

# Update cache and wake deflisten
echo "$GOVERNOR" > /tmp/quickshell/cpu_governor
echo "$GOVERNOR" >> /tmp/quickshell/cpu_governor_trigger
