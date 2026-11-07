#!/usr/bin/env bash
# launcher.sh -- the "App launcher" keybind (SUPER + R) goes through here so that
# Settings > Popups > Applications > Style decides what opens:
#   rofi (default)  ->  rofi -show drun
#   quickshell      ->  qs ipc call apps toggle   (falls back to rofi if the shell does not answer)
CFG="$HOME/.config/quickshell/state/popup-settings.json"

STYLE=$(python3 - "$CFG" <<'PY' 2>/dev/null
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("apps", {}).get("style", "rofi"))
except Exception:
    print("rofi")
PY
)

if [ "$STYLE" = "quickshell" ] && qs ipc call apps toggle >/dev/null 2>&1; then
    exit 0
fi
exec rofi -show drun
