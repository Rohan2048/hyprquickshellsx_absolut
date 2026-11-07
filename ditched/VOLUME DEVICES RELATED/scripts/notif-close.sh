#!/usr/bin/env bash
HASH="$1"
dunstctl close "$HASH"
rm -f "/tmp/quickshell-notifs/$HASH"
