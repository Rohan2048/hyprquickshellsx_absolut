#!/bin/bash
# wifi-history.sh
HIST="$HOME/.config/quickshell/state/wifi-history.json"
mkdir -p "$(dirname "$HIST")"
if [ ! -f "$HIST" ] || ! python3 -c "import json; json.load(open('$HIST'))" 2>/dev/null; then
    echo '[]' > "$HIST"
fi
normalize_ssid() {
    echo "$1" | sed 's/ *$//'
}
update_ssid() {
    SSID="$1"
    [ -z "$SSID" ] || [ "$SSID" = "Disconnected" ] && return
    SSID=$(normalize_ssid "$SSID")
    python3 - "$HIST" "$SSID" << 'PY'
import json, sys
path, ssid = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = list(data.keys())
except:
    data = []
if ssid in data:
    data.remove(ssid)
data.insert(0, ssid)
data = data[:10]
with open(path, 'w') as f:
    json.dump(data, f)
PY
}
list_ssid() {
    python3 - "$HIST" << 'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = list(data.keys())
except:
    data = []
print(json.dumps([{"ssid": s} for s in data]))
PY
}
connect_ssid() {
    # No trailing '&' — this must run synchronously so its exit code is
    # real. wifi-history.sh is invoked as `connect ... && update ...` from
    # Wifi.qml; backgrounding this made the script always report success
    # immediately, so `update` would fire (and save to history) even when
    # the actual nmcli connect failed.
    nmcli device wifi connect "$1" &>/dev/null
}
forget_ssid() {
    SSID=$(normalize_ssid "$1")
    nmcli -t -f NAME,TYPE connection show | while IFS=: read -r name type; do
        [ "$type" = "wifi" ] || continue
        profile_ssid=$(nmcli -g 802-11-wireless.ssid connection show "$name" 2>/dev/null)
        if [ "$profile_ssid" = "$SSID" ]; then
            nmcli connection delete "$name"
        fi
    done
    python3 - "$HIST" "$SSID" << 'PY'
import json, sys
path, ssid = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = list(data.keys())
except:
    data = []
if ssid in data:
    data.remove(ssid)
with open(path, 'w') as f:
    json.dump(data, f)
PY
}
case "$1" in
    list)       list_ssid;          exit ;;
    update)     update_ssid "$2";   exit ;;
    connect)    connect_ssid "$2";  exit $? ;;
    forget)     forget_ssid "$2";   exit ;;
esac
# --------------------------
# MONITOR — pure bash, uses nmcli monitor (no GI/Python version issues)
# --------------------------
_wifi_emit() {
    local ssid hist
    if nmcli -t -f WIFI radio 2>/dev/null | grep -q '^enabled$'; then
        ssid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null \
               | awk -F: '$1=="yes"{print $2; exit}')
        ssid="${ssid:-Disconnected}"
    else
        ssid="WiFi-OFF"
    fi
    hist=$(python3 - "$HIST" << 'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
    if isinstance(data, dict):
        data = list(data.keys())
except:
    data = []
print(json.dumps([{"ssid": s} for s in data]))
PY
)
    printf '{"ssid":"%s","history":%s}\n' "$ssid" "$hist"
}
# Emit immediately on start
_wifi_emit
# Watch nmcli monitor for any connectivity/radio changes
nmcli monitor 2>/dev/null | while IFS= read -r line; do
    if echo "$line" | grep -qiE '(connectivity|wireless|connected|disconnected|unavailable|removed|deleted)'; then
        sleep 0.5  # brief settle so nmcli dev wifi reflects new state
        _wifi_emit
    fi
done
