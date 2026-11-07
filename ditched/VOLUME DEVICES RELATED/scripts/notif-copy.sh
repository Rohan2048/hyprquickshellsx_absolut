#!/bin/bash
HASH="$1"
NOTIF=$(cat "/tmp/quickshell-notifs/$HASH" 2>/dev/null)
echo "$NOTIF" | tail -n +2 | wl-copy
