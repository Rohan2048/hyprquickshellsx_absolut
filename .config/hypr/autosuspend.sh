#!/bin/bash

# Wait for hyprlock to appear
sleep 2

while pidof hyprlock >/dev/null; do
    # Reset timer on activity — wait 60s of inactivity
    sleep 60
    if pidof hyprlock >/dev/null; then
        systemctl suspend -i
    fi
done
