#!/bin/bash
# ~/.config/hypr/write-wallpaper-state.sh
# Usage: write-wallpaper-state.sh <path>
#
# Single writer for quickshell_wallpaper_state.json.
# Written to a .tmp file then mv'd so QML's FileView never sees a partial
# write — mv is atomic on the same filesystem.
set -eo pipefail

STATE_FILE="$HOME/.cache/quickshell_wallpaper_state.json"
TMP_FILE="$STATE_FILE.tmp"
TRIGGER_FILE="$HOME/.cache/quickshell/theme_trigger"

NEW_PATH="$1"

if [[ -z "$NEW_PATH" ]]; then
    echo "write-wallpaper-state: no path given" >&2
    exit 1
fi

mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$TRIGGER_FILE")"

python3 - "$NEW_PATH" "$TMP_FILE" <<'EOF'
import json, sys
image, tmp = sys.argv[1:3]
json.dump({"wallpaper": image}, open(tmp, "w"))
EOF

mv "$TMP_FILE" "$STATE_FILE"

sleep 0.1
date +%s%N > "$TRIGGER_FILE"
