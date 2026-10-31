#!/usr/bin/env bash
# qs-pick.sh -- ask the Quickshell version of a keybind menu for an answer.
#
#   qs-pick.sh list  <menu> <title>                  items on stdin, one per line
#   qs-pick.sh input <menu> <title> [placeholder]
#   qs-pick.sh open  <menu>                          the popup does the whole job itself (wallpaper)
#
#   <menu> = powermenu | schedule | hdmi | animscale | wallpaper   (Settings > Popups)
#
# Exit status:
#   0  the picked text is on stdout (empty = cancelled, the caller should just stop)
#   3  "use rofi": the menu is set to Rofi, or the shell did not answer (not running / crashed).
#      The caller then runs its normal rofi command. That is the whole crash fallback: it is
#      decided when the key is pressed, nothing watches the shell.
CFG="$HOME/.config/quickshell/state/popup-settings.json"
MODE="$1"; MENU="$2"; TITLE="$3"; PLACEHOLDER="${4:-}"

STYLE=$(python3 - "$CFG" "$MENU" <<'PY' 2>/dev/null
import json, sys
try:
    print(json.load(open(sys.argv[1])).get("power", {}).get(sys.argv[2] + "Style", "rofi"))
except Exception:
    print("rofi")
PY
)
[ "$STYLE" = "quickshell" ] || exit 3

if [ "$MODE" = "open" ]; then
    # exit 0 = the shell opened it (nothing more to do); 3 = use rofi
    case "$MENU" in
        wallpaper) timeout 3 qs ipc call wallpaperPicker open >/dev/null 2>&1 && exit 0 ;;
    esac
    exit 3
fi

RES="${XDG_RUNTIME_DIR:-/tmp}/qs-choice-$MENU"
rm -f "$RES" "$RES.tmp"

if [ "$MODE" = "list" ]; then
    ITEMS=$(paste -sd'|' -)
    timeout 3 qs ipc call choice list "$MENU" "$TITLE" "$ITEMS" "$RES" >/dev/null 2>&1 || exit 3
else
    timeout 3 qs ipc call choice input "$MENU" "$TITLE" "$PLACEHOLDER" "$RES" >/dev/null 2>&1 || exit 3
fi

# The popup writes the answer (empty = cancelled) when it closes. Wait up to 2 minutes.
for _ in $(seq 1 1200); do
    if [ -f "$RES" ]; then
        cat "$RES"
        rm -f "$RES"
        exit 0
    fi
    sleep 0.1
done
qs ipc call choice close >/dev/null 2>&1
exit 0
