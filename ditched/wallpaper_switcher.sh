#!/bin/bash
#wallpaper_switcher.sh
WALLPAPER_DIR="$HOME/Downloads/WALLPAPERS"
THUMB_DIR="$HOME/.cache/wallpaper_thumbs"
mkdir -p "$THUMB_DIR"

ROFI_THEME="$HOME/.config/rofi/wallpaper-selector.rasi"

for cmd in rofi; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "$cmd is not installed."
        exit 1
    fi
done

if ! command -v convert &>/dev/null && ! command -v magick &>/dev/null; then
    echo "ImageMagick is required for thumbnail generation."
    exit 1
fi

convert_cmd=$(command -v magick || command -v convert)

needs_thumbnails() {
    for ext in jpg jpeg png webp bmp gif; do
        shopt -s nullglob
        for img in "$WALLPAPER_DIR"/*."$ext"; do
            [ -f "$img" ] || continue
            filename=$(basename "$img")
            name="${filename%.*}"
            thumb_path="$THUMB_DIR/${name}_thumb.png"
            if [ ! -f "$thumb_path" ] || [ "$img" -nt "$thumb_path" ]; then
                shopt -u nullglob
                return 0
            fi
        done
        shopt -u nullglob
    done
    return 1
}

generate_thumbnails() {
    for ext in jpg jpeg png webp bmp gif; do
        shopt -s nullglob
        for img in "$WALLPAPER_DIR"/*."$ext"; do
            [ -f "$img" ] || continue
            filename=$(basename "$img")
            name="${filename%.*}"
            thumb_path="$THUMB_DIR/${name}_thumb.png"

            if [ ! -f "$thumb_path" ] || [ "$img" -nt "$thumb_path" ]; then
                "$convert_cmd" "$img[0]" -strip -thumbnail 500x500^ -gravity center -extent 500x500 "$thumb_path" 2>/dev/null
            fi
        done
        shopt -u nullglob
    done
}

create_rofi_entries() {
    mapping_file="/tmp/wallpaper_mapping_$$"
    > "$mapping_file"

    for ext in jpg jpeg png webp bmp gif; do
        shopt -s nullglob
        for img in "$WALLPAPER_DIR"/*."$ext"; do
            [ -f "$img" ] || continue
            filename=$(basename "$img")
            name="${filename%.*}"
            thumb="$THUMB_DIR/${name}_thumb.png"

            echo "$name|$img" >> "$mapping_file"

            if [ -f "$thumb" ]; then
                printf "%s\x00icon\x1f%s\n" "$name" "$thumb"
            else
                echo "$name"
            fi
        done
        shopt -u nullglob
    done
}

if needs_thumbnails; then
    notify-send "Wallpapers" "Loading Wallpapers..."
fi
generate_thumbnails

mapping_file="/tmp/wallpaper_mapping_$$"

selection=$(create_rofi_entries | rofi -dmenu -i \
    -p "  Wallpaper" \
    -show-icons \
    -theme "$ROFI_THEME")

[ -z "$selection" ] && { rm -f "$mapping_file"; exit 0; }

selected_line=$(grep -F "$selection|" "$mapping_file")
selected_path=$(echo "$selected_line" | cut -d'|' -f2)
rm -f "$mapping_file"

[ -f "$selected_path" ] || { echo "Error: File not found - $selected_path"; exit 1; }

sed -i "s|^WALLPAPER=.*|WALLPAPER=\"$selected_path\"|" ~/.config/hypr/shellwrapper.sh

~/.local/bin/wal -i "$selected_path" -q

bash ~/.config/hypr/apply-theme.sh

~/.config/hypr/write-wallpaper-state.sh image "$selected_path"

hyprctl reload
