#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$HOME/.config/quickshell/.animation-scale"

options="0.75×
1.00×
1.25×
1.50×
2.00×
Auto (Refresh Rate based)"

chosen=$(echo "$options" | rofi -dmenu -mesg "Animation Scaling" -theme "$SCRIPT_DIR/animation-scale.rasi")

case "$chosen" in
    "0.75×") value=0.75 ;;
    "1.00×") value=1.0 ;;
    "1.25×") value=1.25 ;;
    "1.50×") value=1.5 ;;
    "2.00×") value=2.0 ;;
    "Auto (Refresh Rate based)") value=auto ;;
    *) exit 0 ;;
esac

"$SCRIPT_DIR/set-animation-scale.sh" "$value"

current=$(cat "$STATE_FILE" 2>/dev/null)
notify-send "Animation Scaling" "Set to ${current}×"
