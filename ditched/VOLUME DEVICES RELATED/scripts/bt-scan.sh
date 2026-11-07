#!/bin/bash

# bt-scan.sh
# Usage:
#   bt-scan.sh scan         — power on, scan 10s, write to cache
#   bt-scan.sh list         — read cache, print raw device list
#   bt-scan.sh pair <MAC>   — pair, prompt via dunst if needed, trust + connect

CACHE='/tmp/quickshell/bt_scan_cache'
mkdir -p /tmp/quickshell

case "$1" in

  scan)
    bluetoothctl power on 2>/dev/null
    sleep 1

    # Scan for 10 seconds in background
    bluetoothctl scan on &
    SCAN_PID=$!
    sleep 10
    kill $SCAN_PID 2>/dev/null
    bluetoothctl scan off 2>/dev/null

    # Write raw device list to cache
    bluetoothctl devices > "$CACHE"

    # Notify scan complete
    COUNT=$(wc -l < "$CACHE")
    dunstify -u low -i bluetooth "Bluetooth Scan" "Found $COUNT device(s)"
    ;;

  list)
    # Just read the cache — fast, no scanning
    if [ -f "$CACHE" ]; then
      cat "$CACHE"
    else
      echo "No scan results yet. Run: bt-scan.sh scan"
    fi
    ;;

  pair)
    MAC="$2"
    if [ -z "$MAC" ]; then
      echo "Usage: bt-scan.sh pair <MAC>"
      exit 1
    fi

    # Get device name for notifications
    NAME=$(bluetoothctl devices | grep "$MAC" | cut -d' ' -f3-)
    [ -z "$NAME" ] && NAME="$MAC"

    dunstify -u low -i bluetooth "Bluetooth" "Pairing with $NAME..."

    # Drive bluetoothctl pair, capture output line by line
    bluetoothctl pair "$MAC" 2>&1 | while IFS= read -r line; do

      # Passkey confirmation — "Confirm passkey XXXXXX (yes/no)"
      if echo "$line" | grep -qi "confirm passkey"; then
        CODE=$(echo "$line" | grep -oP '\d{6}')

        # dunstify blocks until user clicks an action
        ACTION=$(dunstify -u critical -i bluetooth \
          "Bluetooth Pairing" "Does this code match on $NAME?  $CODE" \
          --action="yes,Confirm" \
          --action="no,Reject")

        if [ "$ACTION" = "yes" ]; then
          bluetoothctl confirm "$MAC" yes
        else
          bluetoothctl confirm "$MAC" no
          dunstify -u normal -i bluetooth "Bluetooth" "Pairing rejected for $NAME"
          exit 1
        fi

      # PIN entry request
      elif echo "$line" | grep -qi "enter pin\|pin code"; then
        PIN=$(rofi -dmenu -p "PIN for $NAME:" -lines 0)
        if [ -n "$PIN" ]; then
          bluetoothctl pin-code "$MAC" "$PIN"
        else
          dunstify -u normal -i bluetooth "Bluetooth" "Pairing cancelled for $NAME"
          exit 1
        fi

      # Pair succeeded
      elif echo "$line" | grep -qi "pairing successful"; then
        dunstify -u low -i bluetooth "Bluetooth" "Paired with $NAME — connecting..."
        bluetoothctl trust "$MAC"
        bluetoothctl connect "$MAC"
        dunstify -u low -i bluetooth "Bluetooth" "Connected to $NAME"

      # Already paired
      elif echo "$line" | grep -qi "already paired"; then
        dunstify -u low -i bluetooth "Bluetooth" "$NAME already paired — connecting..."
        bluetoothctl trust "$MAC"
        bluetoothctl connect "$MAC"
        dunstify -u low -i bluetooth "Bluetooth" "Connected to $NAME"

      # Pair failed
      elif echo "$line" | grep -qi "failed\|error"; then
        dunstify -u critical -i bluetooth "Bluetooth" "Failed to pair with $NAME"
        exit 1
      fi

    done
    ;;

  *)
    echo "Usage: $0 scan | list | pair <MAC>"
    exit 1
    ;;

esac
