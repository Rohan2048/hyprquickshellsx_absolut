#!/usr/bin/env bash
FILE="$HOME/.config/quickshell/state/commands.json"
[ ! -f "$FILE" ] && echo "[]" > "$FILE"

EXISTING_GROUPS=$(python3 -c "
import json
data = json.load(open('$FILE'))
for g in data:
    print(g['group'])
")

GROUP=$(echo "$EXISTING_GROUPS" | rofi -dmenu \
    -p "Group (select or type new)" \
    -i \
    -theme ~/.config/rofi/commands-add.rasi)

[ -z "$GROUP" ] && exit 0

CMD=$(rofi -dmenu \
    -p "" \
    -theme ~/.config/rofi/command-input.rasi \
    < /dev/null)

[ -z "$CMD" ] && exit 0

LAUNCH=$(printf "direct\nterminal" | rofi -dmenu \
    -p "  How do you want to launch?   " \
    -theme ~/.config/rofi/config-commands.rasi)
[ -z "$LAUNCH" ] && exit 0

TERMINAL=$( [ "$LAUNCH" = "terminal" ] && echo "true" || echo "false" )

python3 - <<PYEOF
import json

FILE = '$FILE'
GROUP = '$GROUP'
CMD = '$CMD'
TERMINAL = '$TERMINAL' == 'true'

with open(FILE) as f:
    data = json.load(f)

entry = {"cmd": CMD, "terminal": TERMINAL}

for g in data:
    if g['group'] == GROUP:
        if entry not in g['commands']:
            g['commands'].append(entry)
        break
else:
    data.append({'group': GROUP, 'commands': [entry]})

with open(FILE, 'w') as f:
    json.dump(data, f, indent=2)
PYEOF

notify-send "Commands" "Added to group: $GROUP"
