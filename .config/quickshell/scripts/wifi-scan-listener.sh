#!/usr/bin/env bash
# wifi-scan-listener.sh — live "what does my machine actually see" list.
# Emits one JSON array per line: [{ssid, signal, security, connected}, ...]
# Also caches the latest snapshot to disk so it survives a quickshell restart.
# Idle backoff: scan interval grows from 4s to 20s if results are unchanged,
# to avoid hammering the wifi radio when nothing's actively watching.
#
# Backoff comparison ignores exact signal dBm/percent jitter (±noise on an
# unchanged network shouldn't reset the interval back to MIN_INTERVAL every
# cycle — that was the up/down/up/down bug burning battery at ~4s forever).

CACHE="$HOME/.config/quickshell/state/wifi-scan.json"
mkdir -p "$(dirname "$CACHE")"
RAW="/tmp/quickshell/wifi_scan_raw"
mkdir -p /tmp/quickshell

# Refuse to run twice in parallel (e.g. leftover instance from a Quickshell
# hot-reload that didn't die cleanly) — stacked instances were doubling up
# the nmcli rescan cadence on top of the backoff bug above.
LOCKFILE="/tmp/quickshell/wifi-scan-listener.lock"
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    exit 0
fi

parse() {
    python3 - "$RAW" << 'PY'
import sys, json, re

def unescape(s):
    return re.sub(r'\\(.)', r'\1', s)

def split_terse(line):
    return [unescape(p) for p in re.split(r'(?<!\\):', line)]

best = {}
with open(sys.argv[1]) as f:
    for raw in f:
        raw = raw.rstrip('\n')
        if not raw:
            continue
        fields = split_terse(raw)
        if len(fields) < 4:
            continue
        in_use, ssid, signal, security = fields[0], fields[1], fields[2], fields[3]
        if not ssid:
            continue
        signal_n = int(signal) if signal.isdigit() else 0
        entry = {
            'ssid': ssid,
            'signal': signal_n,
            'security': security if security else 'Open',
            'connected': in_use.strip() == '*'
        }
        if ssid not in best or entry['signal'] > best[ssid]['signal'] or entry['connected']:
            best[ssid] = entry

out = sorted(best.values(), key=lambda r: (not r['connected'], -r['signal']))
print(json.dumps(out))
PY
}

# Coarse fingerprint used ONLY for the backoff decision — signal bucketed
# to the nearest 10 so normal jitter doesn't count as "changed". SSID set,
# security, and connected state still count exactly.
fingerprint() {
    python3 -c "
import json, sys
data = json.loads(sys.argv[1])
buckets = [(d['ssid'], round(d['signal'] / 10) * 10, d['security'], d['connected']) for d in data]
print(json.dumps(sorted(buckets)))
" "$1"
}

MIN_INTERVAL=4
MAX_INTERVAL=20
interval=$MIN_INTERVAL
prev_fingerprint=""

while true; do
    nmcli device wifi rescan 2>/dev/null
    nmcli --terse --fields IN-USE,SSID,SIGNAL,SECURITY device wifi list 2>/dev/null > "$RAW"
    OUT=$(parse)
    if [ -n "$OUT" ]; then
        echo "$OUT" > "$CACHE"
        echo "$OUT"
        FP=$(fingerprint "$OUT")
        if [ "$FP" = "$prev_fingerprint" ]; then
            interval=$(( interval + 2 > MAX_INTERVAL ? MAX_INTERVAL : interval + 2 ))
        else
            interval=$MIN_INTERVAL
        fi
        prev_fingerprint="$FP"
    fi
    sleep "$interval"
done
