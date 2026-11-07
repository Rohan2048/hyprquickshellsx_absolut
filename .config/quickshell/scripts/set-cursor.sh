#!/usr/bin/env bash
# set-cursor.sh <theme|default> [size]  -- Settings > Cursor
# Applies the cursor theme to the running session and remembers it:
#   * hyprctl setcursor            (now, Wayland)
#   * state/cursor-theme.txt       ("<theme><TAB><size>", read by hyprland.lua at the next start)
#   * GTK 3 / 4 settings.ini, ~/.icons/default (X11 / Xwayland apps) and gsettings, when present
theme="${1:-default}"
size="${2:-}"
STATE="$HOME/.config/quickshell/state/cursor-theme.txt"
mkdir -p "$(dirname "$STATE")"
[ -z "$size" ] && size=$(awk -F'\t' 'NR==1{print $2}' "$STATE" 2>/dev/null)
[[ "$size" =~ ^[0-9]+$ ]] || size=20

printf '%s\t%s\n' "$theme" "$size" > "$STATE"
hyprctl setcursor "$theme" "$size" >/dev/null 2>&1 || true

esc=${theme//\\/\\\\}; esc=${esc//&/\\&}; esc=${esc//|/\\|}
for v in gtk-3.0 gtk-4.0; do
    ini="$HOME/.config/$v/settings.ini"
    [ -f "$ini" ] || continue
    sed -i "s|^gtk-cursor-theme-name=.*|gtk-cursor-theme-name=$esc|; s|^gtk-cursor-theme-size=.*|gtk-cursor-theme-size=$size|" "$ini"
done

mkdir -p "$HOME/.icons/default"
printf '[Icon Theme]\nName=Default\nInherits=%s\n' "$theme" > "$HOME/.icons/default/index.theme"

# gsettings can be slow (dconf): run it in the background so this script returns at once
if command -v gsettings >/dev/null 2>&1; then
    ( gsettings set org.gnome.desktop.interface cursor-theme "$theme"
      gsettings set org.gnome.desktop.interface cursor-size "$size" ) >/dev/null 2>&1 &
fi
exit 0
