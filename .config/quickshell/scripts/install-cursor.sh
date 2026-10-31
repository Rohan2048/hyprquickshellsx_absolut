#!/usr/bin/env bash
# install-cursor.sh <folder|archive>  -- Settings > Cursor > Add
# Copies every cursor theme found (a folder that has a "cursors" folder inside) into
# ~/.local/share/icons. The source can be a theme folder, a folder holding several themes, or an
# archive (.tar.gz .tgz .tar.xz .txz .tar.bz2 .tar.zst .tar .zip). Prints the installed names, one per line.
src="$1"
dest="$HOME/.local/share/icons"
mkdir -p "$dest"
[ -e "$src" ] || { echo "not found: $src" >&2; exit 1; }

tmp=""
cleanup() { [ -n "$tmp" ] && rm -rf "$tmp"; }
trap cleanup EXIT

if [ -f "$src" ]; then
    tmp=$(mktemp -d)
    case "${src,,}" in
        *.zip) unzip -q "$src" -d "$tmp" || exit 1 ;;
        *)     tar -xf "$src" -C "$tmp" || exit 1 ;;
    esac
    root="$tmp"
    base=$(basename "$src"); base="${base%.*}"; base="${base%.tar}"
else
    root="$src"
    base=$(basename "$src")
fi

install_one() {
    local from="$1" name="$2"
    [ "$from" = "$dest/$name" ] && { echo "$name"; return; }
    rm -rf "$dest/$name"
    cp -a "$from" "$dest/$name" && echo "$name"
}

if [ -d "$root/cursors" ]; then
    install_one "$root" "$base"
else
    while IFS= read -r c; do
        t=$(dirname "$c")
        install_one "$t" "$(basename "$t")"
    done < <(find "$root" -maxdepth 3 -type d -name cursors 2>/dev/null)
fi
exit 0
