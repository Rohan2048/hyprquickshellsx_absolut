#!/bin/bash
#wallpaper-apply.sh
selected_path="$1"

[ -f "$selected_path" ] || { echo "Error: File not found - $selected_path"; exit 1; }

# Update shellwrapper
sed -i "s|^WALLPAPER=.*|WALLPAPER=\"$selected_path\"|" ~/.config/hypr/shellwrapper.sh

# Generate Pywal colors
/home/rohan/.local/bin/wal -i "$selected_path" -q

# Update plasma-integration
bash ~/.config/hypr/apply-theme.sh

# Set wallpaper
echo "$selected_path" > "$HOME/.cache/quickshell_wallpaper"
date +%s%N > ~/.cache/quickshell/theme_trigger

# Reload dunst config (new colors) without dropping the notification server
if pgrep -x dunst >/dev/null; then
    dunstctl reload
else
    setsid dunst >/dev/null 2>&1 &
    disown
fi

# Reload Hyprland
# instead of: hyprctl reload
source "$HOME/.cache/wal/colors.sh"   # or wherever pywal drops the vars

hyprctl --batch "\
keyword general:col.active_border rgb(${color4#\#}); \
keyword general:col.inactive_border rgb(${color0#\#}); \
keyword decoration:col.shadow rgb(${color0#\#})"
