#!/usr/bin/env bash
# resolve-icon.sh <appId>
set -uo pipefail

app_id="${1:-}"
[[ -z "$app_id" ]] && { echo "[]"; exit 0; }

data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
data_dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
IFS=':' read -ra dirs_arr <<< "$data_home:$data_dirs"

lower="${app_id,,}"
tail="${app_id##*.}"
tail_lower="${tail,,}"
# Search priority: Exact appId, lowercase appId, class name tail
id_variants=("$app_id" "$lower" "$tail" "$tail_lower")

desktop_file=""
# Step 1: Look for exact desktop file matches first
for dir in "${dirs_arr[@]}"; do
    app_dir="$dir/applications"
    [[ -d "$app_dir" ]] || continue
    for id in "${id_variants[@]}"; do
        if [[ -f "$app_dir/$id.desktop" ]]; then
            desktop_file="$app_dir/$id.desktop"
            break 2
        fi
    done
done

# Step 2: Fallback to fuzzy search if no exact match
if [[ -z "$desktop_file" ]]; then
    for dir in "${dirs_arr[@]}"; do
        app_dir="$dir/applications"
        [[ -d "$app_dir" ]] || continue
        for id in "${id_variants[@]}"; do
            match=$(find "$app_dir" -iname "*${id}*.desktop" 2>/dev/null | head -n1)
            if [[ -n "$match" ]]; then desktop_file="$match"; break 2; fi
        done
    done
fi

icon_name=""
[[ -n "$desktop_file" ]] && icon_name=$(grep -m1 '^Icon=' "$desktop_file" | cut -d= -f2-)
[[ -z "$icon_name" ]] && icon_name="$app_id"

candidates=()
if [[ "$icon_name" == /* ]]; then
    [[ -f "$icon_name" ]] && candidates+=("file://$icon_name")
else
    # Common icon locations
    icon_dirs=("$HOME/.icons")
    for d in "${dirs_arr[@]}"; do icon_dirs+=("$d/icons" "$d/pixmaps"); done

    for name in "$icon_name" "$lower" "$tail"; do
        [[ -z "$name" ]] && continue
        for d in "${icon_dirs[@]}"; do
            [[ -d "$d" ]] || continue
            # Find icons, prioritize SVGs and larger PNGs
            while IFS= read -r f; do
                candidates+=("file://$f")
            done < <(find "$d" -xtype f \( -name "${name}.svg" -o -name "${name}.png" \) 2>/dev/null | \
                awk '{ print length, $0 }' | sort -rn | cut -d" " -f2- | head -n5)
        done
    done
fi

# Unique results
declare -A seen; uniq=()
for c in "${candidates[@]}"; do [[ -z "${seen[$c]:-}" ]] && { seen[$c]=1; uniq+=("$c"); }; done

# Output as JSON
json="["; first=1
for c in "${uniq[@]}"; do
    esc=${c//\"/\\\"}
    [[ $first -eq 1 ]] && first=0 || json+=","
    json+="\"$esc\""
done
json+="]"
echo "$json"
