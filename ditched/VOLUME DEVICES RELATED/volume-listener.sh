#!/usr/bin/env bash
# volume-listener.sh — emits {volume, muted, sink, sinks, label} JSON
# driven by pactl subscribe

mkdir -p /tmp/quickshell

# Sinks that should never show up in the UI
# (PipeWire's fallback when no real sink exists)
is_dummy() {
    [[ "$1" == "auto_null" || "$1" == "Dummy Output" ]]
}

_refresh_sinks_cache() {
    pactl list sinks 2>/dev/null | awk '
    /^[ \t]+Name:/ {
        name=$0; sub(/^[ \t]+Name:[ \t]*/,"",name)
    }
    /^[ \t]+Description:/ {
        desc=$0; sub(/^[ \t]+Description:[ \t]*/,"",desc)
        gsub(/"/,"",desc)
        if (name == "auto_null" || desc == "Dummy Output") next
        printf "%s\"%s\"", sep, desc
        sep=","
    }
    END { print "" }' | awk '{print "["$0"]"}' > /tmp/quickshell/sinks_cache
}

[ ! -f /tmp/quickshell/sinks_cache ] && _refresh_sinks_cache

emit() {
    RAW=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
    VOL=$(echo "$RAW" | awk '{printf "%d", $2*100}')
    MUTED=false
    LABEL="ON"
    if echo "$RAW" | grep -q MUTED; then
        MUTED=true
        LABEL="MUTED"
    fi

    DEFAULT=$(pactl get-default-sink)
    SINK=$(pactl list sinks 2>/dev/null \
        | grep -A15 "Name: $DEFAULT" \
        | grep 'Description:' | head -n1 \
        | cut -d: -f2- | xargs)
    SINK=${SINK:-Unknown}

    # Don't advertise the fallback as the active device
    if is_dummy "$DEFAULT" || is_dummy "$SINK"; then
        SINK="Unknown"
    fi
    echo "$SINK" > /tmp/quickshell/active_sink

    SINKS=$(cat /tmp/quickshell/sinks_cache 2>/dev/null || echo "[]")

    printf '{"volume":%s,"muted":%s,"label":"%s","sink":"%s","sinks":%s}\n' \
        "$VOL" "$MUTED" "$LABEL" "$SINK" "$SINKS"
}

emit

# Trailing debounce: collect events, act once things go quiet for 80ms.
# Topology events (new/remove/server) are never dropped, so the cache
# always reflects the final state after a profile switch.
dirty=0
topo=0
while true; do
    if IFS= read -r -t 0.08 EVENT; then
        dirty=1
        if [[ "$EVENT" =~ (new|remove|server) ]]; then
            topo=1
        fi
    else
        rc=$?
        (( rc == 1 )) && break        # EOF: pactl subscribe died
        if (( dirty )); then
            if (( topo )); then
                _refresh_sinks_cache
                topo=0
            fi
            dirty=0
            emit
        fi
    fi
done < <(pactl subscribe 2>/dev/null | grep --line-buffered -E "sink|server")
