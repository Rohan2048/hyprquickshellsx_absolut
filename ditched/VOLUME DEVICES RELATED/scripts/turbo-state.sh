#!/usr/bin/env bash
NO_TURBO='/sys/devices/system/cpu/intel_pstate/no_turbo'
CACHE='/tmp/eww/turbo_state'

[ ! -f "$NO_TURBO" ] && echo "UNSUPPORTED" && exit 0

if [ -f "$CACHE" ]; then
    cat "$CACHE"
else
    val=$(cat "$NO_TURBO")
    [ "$val" = "0" ] && echo "ON" || echo "OFF"
fi
