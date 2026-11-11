#!/usr/bin/env bash
# Usage: apply-rofi-font.sh <family> [font-file] [scale]
# Writes ~/.cache/rofi/font-8.rasi .. font-14.rasi (each: * { font: "<family> <size*scale>"; })
# which the rofi themes import by their base size, and links custom font files
# where fontconfig/Pango can see them.
# Fallback chain: chosen family -> "Satoshi Variable" (if installed) -> sans-serif.
set -u
FAMILY="${1:-}"
FILE="${2:-}"
SCALE="${3:-1.0}"

if [[ -n "$FILE" && -f "$FILE" ]]; then
    dir="$HOME/.local/share/fonts/quickshell-custom"
    mkdir -p "$dir"
    dest="$dir/$(basename "$FILE")"
    [[ -e "$dest" ]] || { ln -sf "$FILE" "$dest" && fc-cache -f "$dir" >/dev/null 2>&1; }
fi

installed() { [[ -n "$1" ]] && fc-list -q "$1" 2>/dev/null; }
if ! installed "$FAMILY"; then
    if installed "Satoshi Variable"; then FAMILY="Satoshi Variable"; else FAMILY="sans-serif"; fi
fi
FAMILY="${FAMILY//\"/}"

out="$HOME/.cache/rofi"
mkdir -p "$out"
for s in 8 9 10 11 12 13 14; do
    awk -v fam="$FAMILY" -v sc="$SCALE" -v s="$s" 'BEGIN {
        v = s * sc; if (v < 6) v = 6
        printf "* {\n    font: \"%s %.1f\";\n}\n", fam, v
    }' > "$out/font-$s.rasi.tmp" && mv "$out/font-$s.rasi.tmp" "$out/font-$s.rasi"
done
rm -f "$out/font.rasi"
