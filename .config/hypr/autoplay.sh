#!/bin/bash

PLAY="/home/rohan/Downloads/MISC/MUSIC/"
TARGET_FILE="$HOME/.config/quickshell/state/music_target"
if [[ -s "$TARGET_FILE" ]]; then
    T=$(<"$TARGET_FILE")
    [[ "$T" =~ ^[a-zA-Z][a-zA-Z0-9+.-]*:// || -e "$T" ]] && PLAY=$T
fi
FIRST_RUN="/tmp/autoplay_first_run"
WATCHER_PID="/tmp/autoplay_watcher_pid"

if pgrep -x "mpv" > /dev/null; then
    killall mpv
    [ -f "$WATCHER_PID" ] && kill $(cat "$WATCHER_PID") 2>/dev/null && rm -f "$WATCHER_PID"
    notify-send -h string:x-dunst-stack-tag:music-now-playing "Music" "Stopped"
else
    mpv --loop-playlist --no-video --volume=60 --input-ipc-server=/tmp/mpvsocket "$PLAY" &

    # wait for mpv's MPRIS name to actually register on dbus before
    # anything downstream (this watcher, the shell's playerctl follow)
    # tries to query it — avoids the ambiguous/nondeterministic window
    # right after launch
    for i in $(seq 1 20); do
        playerctl --player=mpv status &>/dev/null && break
        sleep 0.1
    done

    if [ ! -f "$FIRST_RUN" ]; then
        touch "$FIRST_RUN"
    else
        notify-send -h string:x-dunst-stack-tag:music-now-playing "Music" "Playing"
    fi
    (
        PREV=""
        while pgrep -x mpv > /dev/null; do
            CURRENT=$(playerctl --player=mpv metadata title 2>/dev/null)
            if [ -n "$CURRENT" ] && [ "$CURRENT" != "$PREV" ]; then
                notify-send -h string:x-dunst-stack-tag:music-now-playing "Music" "Now Playing:$CURRENT"
                PREV="$CURRENT"
            fi
            sleep 2
        done
    ) &
    echo $! > "$WATCHER_PID"
fi
