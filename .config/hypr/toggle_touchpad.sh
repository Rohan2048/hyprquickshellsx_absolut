#!/bin/bash
STATUS_FILE="/tmp/touchpad_status"

if [ -f "$STATUS_FILE" ] && [ "$(cat $STATUS_FILE)" = "disabled" ]; then
    hyprctl eval 'hl.device({ name = "syna2ba6:00-06cb:ce2c-touchpad", enabled = true })'
    notify-send "Touchpad" "Enabled"
    qs msg osd show touchpad_on ""
    echo "enabled" > "$STATUS_FILE"
else
    hyprctl eval 'hl.device({ name = "syna2ba6:00-06cb:ce2c-touchpad", enabled = false })'
    notify-send "Touchpad" "Disabled"
    qs msg osd show touchpad_off ""
    echo "disabled" > "$STATUS_FILE"
fi
