#!/bin/bash
TARGET="$1"

# Find the sink name corresponding to the description
SINK_NAME=$(pactl list sinks | awk -v target="$TARGET" '
  $1=="Name:" {name=$2}
  $1=="Description:" {
    desc=substr($0,index($0,$2)); gsub(/^ +| +$/,"",desc)
    if(desc==target) {print name; exit}
  }
')

# Set default if found
[[ -n "$SINK_NAME" ]] && pactl set-default-sink "$SINK_NAME"

# Note: no IPC call needed here (this used to be an `eww update ...` line) —
# not needed here since Services/Volume.qml's volume-listener.sh is already
# subscribed to `pactl subscribe` and picks up the sink change on its own.
