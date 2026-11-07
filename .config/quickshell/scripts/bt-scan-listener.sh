#!/usr/bin/env bash
# bt-scan-listener.sh — live "what does my machine actually see" bluetooth list.
# Emits one JSON array per line: [{name, mac, connected}, ...]
# Also caches the latest snapshot to disk so it survives a quickshell restart.

CACHE="$HOME/.config/quickshell/state/bt-scan.json"
RAW="/tmp/quickshell/bt_scan_raw"
FIFO="/tmp/quickshell/bt_scan_ctl.fifo"
mkdir -p "$(dirname "$CACHE")" /tmp/quickshell

BT_PID=""
POWERED=0

start_scan() {
    rm -f "$FIFO"
    mkfifo "$FIFO"
    # Open the fifo read-write on fd 3 so bluetoothctl's stdin never sees EOF
    # (a plain `<"$FIFO"` would block/close as soon as one writer finishes).
    exec 3<>"$FIFO"
    setsid bluetoothctl <&3 >/dev/null 2>&1 &
    BT_PID=$!
    if [ "$POWERED" -eq 0 ]; then
        echo "power on" >&3
        sleep 0.3
        POWERED=1
    fi
    echo "scan on" >&3
}

stop_scan() {
    if [ -n "$BT_PID" ] && kill -0 "$BT_PID" 2>/dev/null; then
        kill "$BT_PID" 2>/dev/null
    fi
    exec 3>&- 2>/dev/null
    rm -f "$FIFO"
}

trap 'stop_scan; bluetoothctl scan off >/dev/null 2>&1; exit 0' EXIT TERM INT

discovering() {
    bluetoothctl show 2>/dev/null | grep -q "Discovering: yes"
}

parse() {
    python3 - "$RAW" "${RAW}.connected" << 'PY'
import sys, re, json
devices_path, connected_path = sys.argv[1], sys.argv[2]

connected_macs = set()
try:
    connected_macs = set(re.findall(r'Device ([0-9A-F:]{17})', open(connected_path).read()))
except FileNotFoundError:
    pass

result = []
try:
    with open(devices_path) as f:
        for line in f:
            m = re.match(r'Device ([0-9A-F:]{17}) (.+)', line.strip())
            if not m:
                continue
            mac, name = m.group(1), m.group(2)
            bare_name = name.strip().upper().replace(':', '').replace('-', '')
            bare_mac = mac.upper().replace(':', '')
            if bare_name == bare_mac:
                continue
            result.append({'name': name, 'mac': mac, 'connected': mac in connected_macs})
except FileNotFoundError:
    pass

result.sort(key=lambda r: (not r['connected'], r['name'].lower()))
print(json.dumps(result))
PY
}

start_scan

MIN_INTERVAL=3
MAX_INTERVAL=15
interval=$MIN_INTERVAL
prev_out=""
fail_count=0

while true; do
    if ! kill -0 "$BT_PID" 2>/dev/null || ! discovering; then
        fail_count=$(( fail_count + 1 ))
    else
        fail_count=0
    fi

    # Only restart after two consecutive bad readings, to ride out BlueZ's
    # normal momentary Discovering:no flicker between inquiry/page-scan windows.
    if [ "$fail_count" -ge 2 ]; then
        stop_scan
        start_scan
        sleep 1
        fail_count=0
    fi

    bluetoothctl devices > "$RAW" 2>/dev/null
    bluetoothctl devices Connected > "${RAW}.connected" 2>/dev/null
    OUT=$(parse)
    if [ -n "$OUT" ]; then
        echo "$OUT" > "$CACHE"
        echo "$OUT"
        if [ "$OUT" = "$prev_out" ]; then
            interval=$(( interval + 2 > MAX_INTERVAL ? MAX_INTERVAL : interval + 2 ))
        else
            interval=$MIN_INTERVAL
        fi
        prev_out="$OUT"
    fi
    sleep "$interval"
done
