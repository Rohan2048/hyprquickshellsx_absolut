#!/usr/bin/env bash
# Usage: set-animation-scale.sh <0.75|1.0|1.25|1.5|2.0|auto>
set -euo pipefail

STATE_DIR="$HOME/.config/quickshell"
STATE_FILE="$STATE_DIR/.animation-scale"
MODE="${1:-1.0}"

mkdir -p "$STATE_DIR"

if [[ "$MODE" == "auto" ]]; then
    rate=$(hyprctl monitors -j | jq '([.[] | select(.focused==true)][0].refreshRate) // .[0].refreshRate')
    rate_int=$(printf '%.0f' "$rate")
    scale=$(awk -v r="$rate_int" 'BEGIN { printf "%.4f", r/60 }')
else
    scale="$MODE"
fi

echo "$scale" > "$STATE_FILE"
