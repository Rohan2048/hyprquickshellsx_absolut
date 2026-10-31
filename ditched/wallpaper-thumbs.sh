#!/bin/bash
#wallpaper-thumbs.sh

WALLPAPER_DIR="$HOME/Downloads/WALLPAPERS"
THUMB_DIR="$HOME/.cache/wallpaper_thumbs"
MANIFEST="$HOME/.cache/wallpaper_manifest.json"
mkdir -p "$THUMB_DIR"

if ! command -v convert &>/dev/null && ! command -v magick &>/dev/null; then
    echo "ImageMagick is required for thumbnail generation."
    exit 1
fi

convert_cmd=$(command -v magick || command -v convert)

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

write_manifest() {
    {
        echo "["
        first=1
        for ext in jpg jpeg png webp bmp gif; do
            shopt -s nullglob
            for img in "$WALLPAPER_DIR"/*."$ext"; do
                [ -f "$img" ] || continue
                filename=$(basename "$img")
                name="${filename%.*}"
                thumb="$THUMB_DIR/${name}_thumb.png"
                [ -f "$thumb" ] || continue

                esc_name=$(printf '%s' "$name" | sed 's/\\/\\\\/g; s/"/\\"/g')
                esc_path=$(printf '%s' "$img" | sed 's/\\/\\\\/g; s/"/\\"/g')
                esc_thumb=$(printf '%s' "$thumb" | sed 's/\\/\\\\/g; s/"/\\"/g')

                [ "$first" -eq 0 ] && echo ","
                first=0
                printf '{"name":"%s","path":"%s","thumb":"%s"}' "$esc_name" "$esc_path" "$esc_thumb"
            done
            shopt -u nullglob
        done
        echo ""
        echo "]"
    } > "$MANIFEST"
}

generate_thumbnails
write_manifest
