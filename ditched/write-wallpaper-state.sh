#!/bin/bash
# ~/.config/hypr/write-wallpaper-state.sh
# Usage: write-wallpaper-state.sh <image|video> <path>
#
# Single writer for quickshell_wallpaper_state.json. Reads the existing
# state first so the path you're NOT setting right now (image when you're
# switching video, or vice versa) is preserved rather than clobbered.
# Written to a .tmp file then mv'd so QML's FileView never sees a partial
# write — mv is atomic on the same filesystem.
set -eo pipefail

STATE_FILE="$HOME/.cache/quickshell_wallpaper_state.json"
TMP_FILE="$STATE_FILE.tmp"
TRIGGER_FILE="$HOME/.cache/quickshell/theme_trigger"

MODE="$1"
NEW_PATH="$2"

if [[ "$MODE" != "image" && "$MODE" != "video" ]]; then
    echo "write-wallpaper-state: mode must be 'image' or 'video', got '$MODE'" >&2
    exit 1
fi

if [[ -z "$NEW_PATH" ]]; then
    echo "write-wallpaper-state: no path given" >&2
    exit 1
fi

existing_image=""
existing_video=""
if [[ -f "$STATE_FILE" ]]; then
    read -r existing_image existing_video < <(python3 - "$STATE_FILE" <<'EOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    d = {}
print(d.get("wallpaper", ""), d.get("video", ""))
EOF
)
fi

if [[ "$MODE" == "image" ]]; then
    IMAGE_PATH="$NEW_PATH"
    VIDEO_PATH="$existing_video"
else
    IMAGE_PATH="$existing_image"
    VIDEO_PATH="$NEW_PATH"
fi

mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$TRIGGER_FILE")"

python3 - "$IMAGE_PATH" "$VIDEO_PATH" "$MODE" "$TMP_FILE" <<'EOF'
import json, sys
image, video, mode, tmp = sys.argv[1:5]
json.dump({"wallpaper": image, "video": video, "mode": mode}, open(tmp, "w"))
EOF

mv "$TMP_FILE" "$STATE_FILE"

sleep 0.1
date +%s%N > "$TRIGGER_FILE"
