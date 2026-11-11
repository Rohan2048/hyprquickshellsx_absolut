#!/bin/bash
#video-wallaper-selector.sh
VIDEO_DIR="$HOME/Downloads/Videos"
THUMB_DIR="$HOME/.cache/video_wallpaper_thumbs"
FRAME_DIR="$HOME/.cache/video_wallpaper_frames"
mkdir -p "$VIDEO_DIR" "$THUMB_DIR" "$FRAME_DIR"

ROFI_THEME="$HOME/.config/rofi/wallpaper-selector.rasi"

for cmd in rofi ffmpeg; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "$cmd is not installed."
        exit 1
    fi
done

if ! command -v convert &>/dev/null && ! command -v magick &>/dev/null; then
    echo "ImageMagick is required for pywal frame compositing."
    exit 1
fi
convert_cmd=$(command -v magick || command -v convert)

shopt -s nullglob
video_files=("$VIDEO_DIR"/*.mp4 "$VIDEO_DIR"/*.mkv "$VIDEO_DIR"/*.webm "$VIDEO_DIR"/*.mov)
shopt -u nullglob
if [ "${#video_files[@]}" -eq 0 ]; then
    notify-send "Video Wallpapers" "No videos found in $VIDEO_DIR"
    exit 0
fi

# A video needs (re)processing if either its thumbnail or its pywal
# composite is missing/stale.
needs_processing() {
    for vid in "${video_files[@]}"; do
        filename=$(basename "$vid")
        name="${filename%.*}"
        thumb_path="$THUMB_DIR/${name}_thumb.png"
        composite_path="$FRAME_DIR/${name}_composite.png"
        if [ ! -f "$thumb_path" ] || [ "$vid" -nt "$thumb_path" ] \
            || [ ! -f "$composite_path" ] || [ "$vid" -nt "$composite_path" ]; then
            return 0
        fi
    done
    return 1
}

# Pull frames at 1s/5s/10s and composite them — done here, at load time,
# so selection later is just a file read, not an ffmpeg run.
extract_pywal_frame() {
    local vid="$1"
    local name
    name=$(basename "${vid%.*}")
    local composite_path="$FRAME_DIR/${name}_composite.png"

    [ -f "$composite_path" ] && [ "$composite_path" -nt "$vid" ] && return

    local frames=()
    for ts in 1 5 10; do
        local frame_path="$FRAME_DIR/${name}_f${ts}.png"
        ffmpeg -y -ss "$ts" -i "$vid" -vframes 1 "$frame_path" &>/dev/null
        [ -f "$frame_path" ] && frames+=("$frame_path")
    done

    if [ "${#frames[@]}" -eq 0 ]; then
        ffmpeg -y -i "$vid" -vframes 1 "$composite_path" &>/dev/null
    else
        "$convert_cmd" "${frames[@]}" +append "$composite_path" 2>/dev/null
        rm -f "${frames[@]}"
    fi
}

generate_thumbnails() {
    for vid in "${video_files[@]}"; do
        filename=$(basename "$vid")
        name="${filename%.*}"
        thumb_path="$THUMB_DIR/${name}_thumb.png"

        if [ ! -f "$thumb_path" ] || [ "$vid" -nt "$thumb_path" ]; then
            ffmpeg -y -ss 1 -i "$vid" -vframes 1 \
                -vf "scale=500:500:force_original_aspect_ratio=increase,crop=500:500" \
                "$thumb_path" &>/dev/null
        fi

        extract_pywal_frame "$vid"
    done
}

create_rofi_entries() {
    mapping_file="/tmp/video_wallpaper_mapping_$$"
    > "$mapping_file"

    for vid in "${video_files[@]}"; do
        filename=$(basename "$vid")
        name="${filename%.*}"
        thumb="$THUMB_DIR/${name}_thumb.png"

        echo "$name|$vid" >> "$mapping_file"

        if [ -f "$thumb" ]; then
            printf "%s\x00icon\x1f%s\n" "$name" "$thumb"
        else
            echo "$name"
        fi
    done
}

if needs_processing; then
    notify-send "Video Wallpapers" "Loading Video Wallpapers..."
    generate_thumbnails
fi

mapping_file="/tmp/video_wallpaper_mapping_$$"

selection=$(create_rofi_entries | rofi -dmenu -i \
    -p "  Video Wallpaper" \
    -show-icons \
    -theme "$ROFI_THEME")

[ -z "$selection" ] && { rm -f "$mapping_file"; exit 0; }

selected_line=$(grep -F "$selection|" "$mapping_file")
selected_path=$(echo "$selected_line" | cut -d'|' -f2)
rm -f "$mapping_file"

[ -f "$selected_path" ] || { echo "Error: File not found - $selected_path"; exit 1; }

selected_name=$(basename "${selected_path%.*}")
frame_path="$FRAME_DIR/${selected_name}_composite.png"

# Composite was already built during the loading pass above — just in case
# it's somehow missing (e.g. a video dropped in after the last scan), build
# it on the spot as a fallback.
[ -f "$frame_path" ] || extract_pywal_frame "$selected_path"

~/.local/bin/wal -i "$frame_path" -q

bash ~/.config/hypr/apply-theme.sh

# Set wallpaper + mode (single atomic write, preserves the image path)
~/.config/hypr/write-wallpaper-state.sh video "$selected_path"

hyprctl reload
