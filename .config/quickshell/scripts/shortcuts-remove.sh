#!/usr/bin/env bash
ID="$1"
FILE="${2:-$HOME/.config/quickshell/state/shortcuts.json}"
mkdir -p "$(dirname "$FILE")"
[ ! -s "$FILE" ] && exit

python3 - <<PYEOF
import json
with open('$FILE') as f:
    data = json.load(f)
data = [x for x in data if x['id'] != '$ID']
with open('$FILE', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

# No eww update call needed — QuickShell's FileView watches shortcuts.json
# directly and picks up this write on its own.
