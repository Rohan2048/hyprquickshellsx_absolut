#!/usr/bin/env bash
NO_TURBO='/sys/devices/system/cpu/intel_pstate/no_turbo'

if [ ! -f "$NO_TURBO" ]; then
    echo "UNSUPPORTED"
    exit 0
fi

mkdir -p /tmp/quickshell
CACHE='/tmp/quickshell/turbo_state'
TRIGGER='/tmp/quickshell/turbo_state_trigger'
CURRENT=$(cat "$NO_TURBO")
BATTERY=$(cat /sys/class/power_supply/BAT0/capacity)

if [ "$CURRENT" = "1" ] && [ "$BATTERY" -lt 20 ]; then
    notify-send "Turbo Mode" "Cannot enable turbo mode. Low battery (${BATTERY}%)"
    exit 0
fi

if [ "$CURRENT" = "0" ]; then
    echo "1" | sudo tee "$NO_TURBO" > /dev/null
    NEW_STATE="OFF"
else
    echo "0" | sudo tee "$NO_TURBO" > /dev/null
    NEW_STATE="ON"
fi

echo "$NEW_STATE" > "$CACHE"
# Append to trigger file — tail -f in deflisten picks this up
echo "$NEW_STATE" >> "$TRIGGER"
echo "$NEW_STATE"
