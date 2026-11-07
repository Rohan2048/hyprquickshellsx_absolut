#!/bin/bash
# set-sink.sh <sinkOrCardName> <port>
#   port == ""               -> normal sink, just set-default-sink
#   port == "profile:<name>" -> set-card-profile first, then poll for the
#                                new sink to appear and set-default-sink
#
# In both cases, after the new sink is set as default, we also move any
# currently-playing streams onto it explicitly. `set-default-sink` alone
# only affects streams opened AFTER the switch -- anything already
# playing stays bound to the old sink and either goes silent or drops
# out when that sink disappears. Moving existing sink-inputs is what
# makes switching between two live sinks (e.g. onboard <-> a connected
# USB/BT device) seamless instead of cutting audio.
#
# NOTE: switching between mutually-exclusive profiles on the SAME card
# (analog <-> HDMI on this hardware) still causes a brief driver-level
# blip during the profile switch itself -- that's the codec tearing down
# and reinitializing the device, not something userspace can hide. The
# stream-move below just ensures audio resumes on the new sink
# immediately after, rather than staying silently orphaned.

SINK_OR_CARD="$1"
PORT="$2"

[[ -z "$SINK_OR_CARD" ]] && exit 1

_move_streams_to() {
    local target="$1"
    pactl list short sink-inputs | while read -r id _; do
        [[ -n "$id" ]] && pactl move-sink-input "$id" "$target"
    done
}

if [[ "$PORT" == profile:* ]]; then
    PROFILE="${PORT#profile:}"
    pactl set-card-profile "$SINK_OR_CARD" "$PROFILE"

    FRAGMENT="${SINK_OR_CARD#alsa_card.}"

    NEW_SINK=""
    for _ in $(seq 1 20); do
        NEW_SINK=$(pactl list short sinks | awk -v frag="$FRAGMENT" 'index($2, frag) { print $2; exit }')
        [[ -n "$NEW_SINK" ]] && break
        sleep 0.1
    done

    if [[ -n "$NEW_SINK" ]]; then
        pactl set-default-sink "$NEW_SINK"
        _move_streams_to "$NEW_SINK"
    fi
else
    pactl set-default-sink "$SINK_OR_CARD"
    _move_streams_to "$SINK_OR_CARD"
fi
