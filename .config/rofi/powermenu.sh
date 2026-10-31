#!/bin/bash

CHOICES="  Shutdown\n  Reboot\n  Suspend\n  Lock\n  Logout"

PICK=~/.config/quickshell/scripts/qs-pick.sh
CHOICE=$(echo -e "$CHOICES" | "$PICK" list powermenu "Power")
if [ $? -eq 3 ]; then
    # menu set to Rofi, or Quickshell is not running: the normal rofi menu
    CHOICE=$(echo -e "$CHOICES" | rofi -dmenu \
        -theme ~/.config/rofi/powermenu.rasi \
        -p "" \
        -lines 5 \
        -no-custom)
fi

case "$CHOICE" in
  *Shutdown) systemctl poweroff ;;
  *Reboot)   systemctl reboot ;;
  *Suspend)  ~/.config/quickshell/scripts/lock-then-suspend ;;
  *Lock)     qs ipc call lock lock ;;
  *Logout)   loginctl terminate-session "$XDG_SESSION_ID" ;;
esac
