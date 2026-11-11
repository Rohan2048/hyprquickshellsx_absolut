#!/usr/bin/env bash

LOG="$HOME/.cache/lock-before-suspend.log"
mkdir -p "$(dirname "$LOG")"

systemd-inhibit \
    --what=sleep \
    --who="quickshell-lock" \
    --why="Lock screen before suspend" \
    --mode=delay \
bash -c '

echo "[$(date +%H:%M:%S.%3N)] Inhibitor started" >> "'"$LOG"'"

stdbuf -oL dbus-monitor --system \
"type='\''signal'\'',interface='\''org.freedesktop.login1.Manager'\'',member='\''PrepareForSleep'\''" |
while IFS= read -r line; do
    case "$line" in
        *"boolean true"*)
            echo "[$(date +%H:%M:%S.%3N)] PrepareForSleep(true)" >> "'"$LOG"'"

            if qs ipc call lock lock; then
                echo "[$(date +%H:%M:%S.%3N)] Lock requested" >> "'"$LOG"'"
            else
                echo "[$(date +%H:%M:%S.%3N)] Lock request failed" >> "'"$LOG"'"
            fi
            ;;

        *"boolean false"*)
            echo "[$(date +%H:%M:%S.%3N)] Resume" >> "'"$LOG"'"
            ;;
    esac
done
'
