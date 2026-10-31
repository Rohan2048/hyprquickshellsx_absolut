#!/usr/bin/env bash
# apply-wallpaper.sh <image path> -- the same steps wallpaper_switcher.sh runs after you pick one
# (used by the Quickshell wallpaper picker).
sel="$1"
[ -f "$sel" ] || { echo "Error: File not found - $sel" >&2; exit 1; }

sed -i "s|^WALLPAPER=.*|WALLPAPER=\"$sel\"|" ~/.config/hypr/shellwrapper.sh
~/.local/bin/wal -i "$sel" -q
bash ~/.config/hypr/apply-theme.sh
~/.config/hypr/write-wallpaper-state.sh "$sel"
hyprctl reload
