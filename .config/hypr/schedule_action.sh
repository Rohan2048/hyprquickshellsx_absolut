
#!/bin/bash

PICK=~/.config/quickshell/scripts/qs-pick.sh
ACTIONS="Shutdown\nSuspend\nReboot\nCancel Scheduled"

# Settings > Popups > Power & display: Quickshell style, else (or if the shell is not running) rofi
ACTION=$(echo -e "$ACTIONS" | "$PICK" list schedule "Schedule Action")
if [ $? -eq 3 ]; then
    ACTION=$(echo -e "$ACTIONS" | rofi -dmenu -p "Schedule Action" \
        -theme ~/.config/rofi/powermenu.rasi \
        -theme-str 'window { width: 300px; height: 220px; }' \
        -theme-str 'listview { lines: 4; scrollbar: false; }' \
        -theme-str 'element-text { horizontal-align: 0.5; }' \
        -no-custom)
fi

[ -z "$ACTION" ] && exit 0

if [ "$ACTION" = "Cancel Scheduled" ]; then
    JOBS=$(atq | awk '{print $1}')
    if [ -z "$JOBS" ]; then
        notify-send "Schedule" "No scheduled actions"
    else
        echo "$JOBS" | xargs atrm
        notify-send "Schedule" "All scheduled actions cancelled"
    fi
    exit 0
fi

TIME=$("$PICK" input schedule "Perform action at (HH:MM)" "e.g. 23:30")
if [ $? -eq 3 ]; then
    TIME=$(rofi -dmenu -p "Perform action at (HH:MM):" \
        -theme ~/.config/rofi/rofi-timeinput.rasi \
        -theme-str 'listview { enabled: false; }' \
        -theme-str 'mainbox { children: [ inputbar ]; }' \
        -theme-str 'entry { placeholder: "e.g. 23:30"; placeholder-color: rgba(255,255,255,0.4); text-color: rgba(255,255,255,1); background-color: transparent; }' \
        -theme-str 'window { width: 300px; height: 80px; }')
fi

[ -z "$TIME" ] && exit 0

if ! echo "$TIME" | grep -qE '^[0-2][0-9]:[0-5][0-9]$'; then
    notify-send "Schedule" "Incorrect time format. Use HH:MM"
    exit 1
fi

TIME_2MIN=$(date -d "$TIME today - 2 minutes" +"%H:%M")
TIME_1MIN=$(date -d "$TIME today - 1 minute" +"%H:%M")

DBUS="DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus"

case "$ACTION" in
    "Shutdown")
        echo "env $DBUS notify-send -u critical 'Scheduled Shutdown' 'System will shutdown in 2 minutes'" | at "$TIME_2MIN" today
        echo "env $DBUS notify-send -u critical 'Scheduled Shutdown' 'System will shutdown in 1 minute'" | at "$TIME_1MIN" today
        echo "sudo systemctl poweroff" | at "$TIME" today
        ;;
    "Suspend")
        echo "env $DBUS notify-send -u critical 'Scheduled Suspend' 'System will suspend in 2 minutes'" | at "$TIME_2MIN" today
        echo "env $DBUS notify-send -u critical 'Scheduled Suspend' 'System will suspend in 1 minute'" | at "$TIME_1MIN" today
        echo "hyprlock & sudo systemctl suspend" | at "$TIME" today
        ;;
    "Reboot")
        echo "env $DBUS notify-send -u critical 'Scheduled Reboot' 'System will reboot in 2 minutes'" | at "$TIME_2MIN" today
        echo "env $DBUS notify-send -u critical 'Scheduled Reboot' 'System will reboot in 1 minute'" | at "$TIME_1MIN" today
        echo "sudo systemctl reboot" | at "$TIME" today
        ;;
esac

notify-send "Scheduled" "$ACTION at $TIME"
