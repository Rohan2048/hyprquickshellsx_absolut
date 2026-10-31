#!/usr/bin/env bash
# wallpaper-precache.sh
#
# Sits underneath wallpaper-apply.sh / wallpaper-thumbs.sh, doesn't
# replace either. Two modes:
#
#   --all <dir>    warm thumbnails for every wallpaper in <dir>.
#                  Just triggers wallpaper-thumbs.sh, which already
#                  skips anything whose thumb is newer than the source
#                  — safe to call every login, costs ~nothing when warm.
#
#   --current      warm pywal for whichever wallpaper is currently
#                  active (read from ~/.cache/quickshell_wallpaper),
#                  but ONLY if its content hash changed since the last
#                  time this ran. This is the one that actually saves
#                  CPU on weak hardware: pywal's quantization is the
#                  most expensive step in the whole login sequence,
#                  and today it reruns unconditionally every login even
#                  when you haven't touched your wallpaper in months.
#
# No QML touched, no changes to wallpaper-apply.sh's behavior when the
# user actually switches wallpapers — this only dedupes the case where
# nothing changed.

set -uo pipefail

WALLPAPER_DIR_DEFAULT="$HOME/Downloads/WALLPAPERS"
CURRENT_WALLPAPER_FILE="$HOME/.cache/quickshell_wallpaper"
STATE_DIR="$HOME/.config/quickshell/state"
LAST_HASH_FILE="$STATE_DIR/wallpaper-precache.hash"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAL_BIN="/home/rohan/.local/bin/wal"

mkdir -p "$STATE_DIR"

mode="${1:-}"

warm_thumbs() {
    local dir="${1:-$WALLPAPER_DIR_DEFAULT}"
    [ -d "$dir" ] || { echo "wallpaper dir not found: $dir" >&2; return 1; }
    bash "$SCRIPTS_DIR/wallpaper-thumbs.sh"
}

warm_current() {
    [ -f "$CURRENT_WALLPAPER_FILE" ] || { echo "no current wallpaper recorded yet" >&2; return 0; }
    local img hash
    img=$(<"$CURRENT_WALLPAPER_FILE")
    [ -f "$img" ] || { echo "current wallpaper missing on disk: $img" >&2; return 1; }

    hash=$(sha256sum "$img" | cut -d' ' -f1)

    if [ -f "$LAST_HASH_FILE" ] && [ "$(<"$LAST_HASH_FILE")" = "$hash" ]; then
        return 0   # unchanged since last login — pywal cache already reflects this image
    fi

    "$WAL_BIN" -i "$img" -q
    echo "$hash" > "$LAST_HASH_FILE"
}

case "$mode" in
    --all)
        warm_thumbs "${2:-$WALLPAPER_DIR_DEFAULT}"
        ;;
    --current)
        warm_current
        ;;
    *)
        echo "usage: $(basename "$0") --all [dir] | --current" >&2
        exit 1
        ;;
esac
