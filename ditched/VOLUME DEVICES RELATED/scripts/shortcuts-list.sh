#!/usr/bin/env bash
FILE="$HOME/.config/quickshell/state/shortcuts.json"
mkdir -p "$(dirname "$FILE")"
[ ! -f "$FILE" ] && echo "[]" > "$FILE"
stdbuf -oL python3 -c "import json; print(json.dumps(json.load(open('$FILE'))))"
