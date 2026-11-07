#!/usr/bin/env bash
# clipboard.sh -- the "Clipboard history" keybind (SUPER + P) goes through here so that
# Settings > Popups > Clipboard history > Style decides what opens:
#   rofi (default)  ->  the rofi list over `cliphist` (config-history.rasi), the pick is copied
#   quickshell      ->  qs ipc call clipboard toggle   (falls back to rofi if the shell does not answer)
CFG="$HOME/.config/quickshell/state/popup-settings.json"

STYLE=$(python3 - "$CFG" <<'PY' 2>/dev/null
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("clipboard", {}).get("style", "rofi"))
except Exception:
    print("rofi")
PY
)

if [ "$STYLE" = "quickshell" ] && qs ipc call clipboard toggle >/dev/null 2>&1; then
    exit 0
fi

# Escape in rofi picks nothing: leave the clipboard alone (an empty pick must not wipe it).
SEL=$(cliphist list | rofi -dmenu -config "$HOME/.config/rofi/config-history.rasi") || exit 0
[ -n "$SEL" ] || exit 0
printf '%s' "$SEL" | cliphist decode | wl-copy
