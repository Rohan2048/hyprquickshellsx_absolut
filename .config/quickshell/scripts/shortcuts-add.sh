#!/usr/bin/env bash
FILE="${1:-$HOME/.config/quickshell/state/shortcuts.json}"
MAX="${2:-10}"
LABEL="${3:-Shortcuts}"
mkdir -p "$(dirname "$FILE")"
[ ! -s "$FILE" ] && echo "[]" > "$FILE"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICONS_DIR="$HOME/.config/quickshell/icons"
mkdir -p "$ICONS_DIR"

# --- Prevent concurrent runs from truncating/corrupting the shared cache ---
LOCK_FD=9
exec 9>"$ICONS_DIR/.shortcuts-add.lock"
if ! flock -n 9; then
  notify-send "$LABEL" "Already scanning — hang tight, rofi will pop up shortly"
  exit
fi

COUNT=$(python3 -c "import json,sys
try:
    print(len(json.load(open('$FILE'))))
except Exception:
    print(0)")
[ "$COUNT" -ge "$MAX" ] && notify-send "$LABEL" "Maximum $MAX shortcuts reached" && exit

CACHE_STAMP="$ICONS_DIR/.last_scan"
APP_CACHE="$ICONS_DIR/.app_cache.tsv"       # name \t desktop_path \t icon_safe_name

# --- Scan check (cheap: just mtimes, so the common "cache is fresh" path
# never has to launch Python at all) ---
SCAN_NEEDED=false
{ [ ! -f "$CACHE_STAMP" ] || [ ! -s "$APP_CACHE" ]; } && SCAN_NEEDED=true

if ! $SCAN_NEEDED; then
  CHANGED=$(find /usr/share/applications "$HOME/.local/share/applications" \
    /var/lib/flatpak/exports/share/applications \
    "$HOME/.local/share/flatpak/exports/share/applications" \
    /var/lib/snapd/desktop/applications \
    -maxdepth 1 -name "*.desktop" -newer "$CACHE_STAMP" 2>/dev/null | wc -l)
  [ "$CHANGED" -gt 0 ] && SCAN_NEEDED=true
fi

if $SCAN_NEEDED; then
  notify-send "$LABEL" "Scanning applications…" -t 3000
  if ! python3 "$SCRIPT_DIR/scan_apps.py"; then
    notify-send "$LABEL" "Scan failed — check $APP_CACHE"
    exit 1
  fi
fi

# --- Load cache into maps (fast, no disk scan, no re-resolution) ---
declare -A DESKTOP_MAP
declare -A ICON_MAP

while IFS=$'\t' read -r NAME DFILE ICON_SAFE; do
  DESKTOP_MAP["$NAME"]="$DFILE"
  if [ -n "$ICON_SAFE" ] && [ -f "$ICONS_DIR/${ICON_SAFE}.png" ]; then
    ICON_MAP["$NAME"]="$ICONS_DIR/${ICON_SAFE}.png"
  fi
done < "$APP_CACHE"

if [ "${#DESKTOP_MAP[@]}" -eq 0 ]; then
  notify-send "$LABEL" "No applications found — check $APP_CACHE"
  rm -f "$CACHE_STAMP"
  exit 1
fi

# --- Rofi picker (only reached once everything above is fully loaded) ---
CHOSEN=$(
  printf '%s\n' "${!DESKTOP_MAP[@]}" | sort | while IFS= read -r NAME; do
    if [ -n "${ICON_MAP[$NAME]}" ]; then
      printf '%s\0icon\x1f%s\n' "$NAME" "${ICON_MAP[$NAME]}"
    else
      printf '%s\n' "$NAME"
    fi
  done | rofi -dmenu -p "Add Shortcut" -i -show-icons -format s
)

[ -z "$CHOSEN" ] && exit

DESKTOP_PATH="${DESKTOP_MAP[$CHOSEN]}"
[ -z "$DESKTOP_PATH" ] && notify-send "$LABEL" "No .desktop found for: $CHOSEN" && exit

APP_NAME=$(grep -m1 "^Name=" "$DESKTOP_PATH" | cut -d= -f2-)
APP_EXEC=$(grep -m1 "^Exec=" "$DESKTOP_PATH" | cut -d= -f2- | sed 's/ %[a-zA-Z]//g')
APP_ICON=$(grep -m1 "^Icon=" "$DESKTOP_PATH" | cut -d= -f2-)

ICON_SAFE=$(echo "$APP_ICON" | tr '/' '_' | tr ' ' '_')
CACHED_ICON="$ICONS_DIR/${ICON_SAFE}.png"

[ ! -f "$CACHED_ICON" ] && notify-send "$LABEL" "Icon missing for $APP_NAME — install imagemagick or librsvg2-tools" && exit

ID=$(date +%s%N)

if ! python3 - <<PYEOF
import json, sys
try:
    with open('$FILE') as f:
        data = json.load(f)
except Exception:
    data = []
data.append({
    'id': '$ID',
    'name': '$APP_NAME',
    'exec': '$APP_EXEC',
    'icon': '$CACHED_ICON'
})
with open('$FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
then
  notify-send "$LABEL" "Failed to write $FILE — check permissions"
  exit 1
fi

notify-send "$LABEL" "Added: $APP_NAME"
# No eww update call needed — QuickShell's FileView watches shortcuts.json
# directly and picks up this write on its own.
