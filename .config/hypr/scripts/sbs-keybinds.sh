#!/usr/bin/env bash
# SBS mode keybind toggle.
#
# Comments/uncomments the lines between "-- SBS:BEGIN <name>" and
# "-- SBS:END <name>" marker pairs in hyprland.lua, then reloads Hyprland.
# Operates purely on those markers (not on bind syntax), so it stays correct
# even if the wrapped binds are edited/reformatted later — see hyprland.lua
# for the marker pairs: shift-w, mod-a, mod-w, mod-r, mod-p.
#
# Usage: sbs-keybinds.sh enable|disable
#   enable  -> comment out the marked binds (entering SBS mode)
#   disable -> uncomment them (leaving SBS mode)
set -euo pipefail

CONF="$HOME/.config/hypr/hyprland.lua"
ACTION="${1:-}"

if [[ "$ACTION" != "enable" && "$ACTION" != "disable" ]]; then
  echo "usage: $0 enable|disable" >&2
  exit 1
fi

if [ ! -f "$CONF" ]; then
  echo "sbs-keybinds.sh: $CONF not found" >&2
  exit 1
fi

python3 - "$CONF" "$ACTION" <<'PYEOF'
import re
import sys

path, action = sys.argv[1], sys.argv[2]
with open(path) as f:
    lines = f.readlines()

out = []
in_block = False
for line in lines:
    if re.search(r"--\s*SBS:BEGIN\s+\S+", line):
        in_block = True
        out.append(line)
        continue
    if re.search(r"--\s*SBS:END\s+\S+", line):
        in_block = False
        out.append(line)
        continue

    if in_block:
        stripped = line.lstrip()
        indent = line[:len(line) - len(stripped)]
        is_commented = stripped.startswith("-- ") or stripped == "--\n"

        if action == "enable" and not is_commented and stripped.strip():
            line = indent + "-- " + stripped
        elif action == "disable" and is_commented:
            # strip exactly one "-- " we added; leave any pre-existing
            # comment markers (there aren't any inside these blocks today,
            # but this keeps the toggle non-destructive either way)
            if stripped.startswith("-- "):
                line = indent + stripped[3:]

    out.append(line)

with open(path, "w") as f:
    f.writelines(out)
PYEOF

hyprctl reload >/dev/null 2>&1 || true
