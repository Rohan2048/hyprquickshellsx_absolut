#!/usr/bin/env bash

LOCK_FILE="/tmp/battery_suspend_triggered"

# Prevent running multiple times
if [ -f "$LOCK_FILE" ]; then
  exit 0
fi
touch "$LOCK_FILE"

CAP=$(cat /sys/class/power_supply/BAT0/capacity)
STATUS=$(cat /sys/class/power_supply/BAT0/status)

# Only run if still discharging and at/below 5%
if [ "$STATUS" = "Charging" ] || [ "$CAP" -gt 5 ]; then
  rm -f "$LOCK_FILE"
  exit 0
fi

# Notify at 60 seconds
notify-send -u critical "Battery Critical" "Battery at ${CAP}%. System will suspend in 60 seconds."
paplay ~/.config/sounds/battery-critical.mp3 2>/dev/null &

sleep 50

# Check if charging started
STATUS=$(cat /sys/class/power_supply/BAT0/status)
if [ "$STATUS" = "Charging" ] || [ ! -f "$LOCK_FILE" ]; then
  rm -f "$LOCK_FILE"
  exit 0
fi

# Notify at 10 seconds
CAP=$(cat /sys/class/power_supply/BAT0/capacity)
notify-send -u critical "Battery Critical" "Battery at ${CAP}%. System will suspend in 10 seconds."
paplay ~/.config/sounds/battery-critical.mp3 2>/dev/null &

sleep 10

# Final check before suspending
STATUS=$(cat /sys/class/power_supply/BAT0/status)
if [ "$STATUS" != "Charging" ] && [ -f "$LOCK_FILE" ]; then
  notify-send -u critical "Battery Critical" "Suspending now!"
  hyprlock &
  sleep 2
  systemctl suspend
  # Lock file stays — prevents re-triggering on resume
  # On resume - kill any lingering notifications
  sleep 1
  dunstctl close-all
fi
