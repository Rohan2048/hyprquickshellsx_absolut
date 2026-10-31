#!/usr/bin/env bash
FILE="$HOME/.config/quickshell/state/commands.json"
[ ! -f "$FILE" ] && exit 1

GROUP="$1"
CMD="$2"
TERMINAL="$3"

[ -z "$GROUP" ] || [ -z "$CMD" ] && exit 1

python3 - <<PYEOF
import json

FILE = '$FILE'
GROUP = '$GROUP'
CMD = '$CMD'
TERMINAL = '$TERMINAL' == 'true'

with open(FILE) as f:
    data = json.load(f)

for entry in data:
    if entry['group'] == GROUP:
        entry['commands'] = [c for c in entry['commands'] if not (c['cmd'] == CMD and c['terminal'] == TERMINAL)]
        break

data = [e for e in data if len(e['commands']) > 0]

with open(FILE, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
