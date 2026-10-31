#!/usr/bin/env bash
# wifi-speed.sh — live throughput of the wifi interface for WifiPopup.
# Emits one JSON object per second: {"down": <bytes/s>, "up": <bytes/s>}
# The interface is found with nmcli (same tool the other wifi scripts use) and
# re-detected if it disappears, so a driver reload / dongle swap self-heals.
# Counters come straight from /sys/class/net, so there's nothing to install.
# Wifi.qml only runs this while the popup is open AND connected, and kills it
# when either stops being true.

mkdir -p /tmp/quickshell
exec 9>"/tmp/quickshell/wifi-speed.lock"
if ! flock -n 9; then
    exit 0
fi

detect() {
    nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'
}

IFACE=""
prev_rx=""
prev_tx=""

while true; do
    if [ -z "$IFACE" ] || [ ! -r "/sys/class/net/$IFACE/statistics/rx_bytes" ]; then
        IFACE=$(detect)
        prev_rx=""
        echo '{"down":0,"up":0}'
        if [ -z "$IFACE" ]; then sleep 5; else sleep 1; fi
        continue
    fi

    rx=$(<"/sys/class/net/$IFACE/statistics/rx_bytes")
    tx=$(<"/sys/class/net/$IFACE/statistics/tx_bytes")

    if [ -n "$prev_rx" ]; then
        d=$(( rx - prev_rx ))
        u=$(( tx - prev_tx ))
        [ "$d" -lt 0 ] && d=0   # counter reset (interface bounced)
        [ "$u" -lt 0 ] && u=0
        echo "{\"down\":$d,\"up\":$u}"
    else
        echo '{"down":0,"up":0}'
    fi

    prev_rx=$rx
    prev_tx=$tx
    sleep 1
done
