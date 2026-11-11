#!/usr/bin/env bash
# volume-listener.sh — emits {volume, muted, sink, sinks, label} JSON
# driven by pactl subscribe
#
# Cost notes (this runs for the whole session):
#  * It blocks on stdin while idle. The old loop used `read -t 0.08`
#    unconditionally, which woke bash ~12 times a second forever.
#    The short timeout is now only used while an event burst is pending.
#  * emit() used to fork ~12 processes (wpctl, awk, echo|grep, pactl x2,
#    grep, grep, head, cut, xargs, cat). The sink description lookup is now
#    an in-memory map filled by the same pactl call that builds the sink
#    list, so emit() only runs wpctl and pactl get-default-sink.

mkdir -p /tmp/quickshell

# Sinks that should never show up in the UI
# (PipeWire's fallback when no real sink exists)
is_dummy() {
    [[ "$1" == "auto_null" || "$1" == "Dummy Output" ]]
}

declare -A SINK_DESC=()     # sink name -> description
SINKS_JSON="[]"

# One `pactl list sinks` parse feeds both the JSON list and the name map.
_refresh_sinks_cache() {
    local name desc sep="" json="" kind
    SINK_DESC=()
    while IFS=$'\t' read -r kind name desc; do
        [[ "$kind" == "S" ]] || continue
        SINK_DESC["$name"]="$desc"
        if [[ "$name" == "auto_null" || "$desc" == "Dummy Output" ]]; then
            continue
        fi
        json+="${sep}\"${desc}\""
        sep=","
    done < <(pactl list sinks 2>/dev/null | awk '
        /^[ \t]+Name:/ {
            name=$0; sub(/^[ \t]+Name:[ \t]*/,"",name)
        }
        /^[ \t]+Description:/ {
            desc=$0; sub(/^[ \t]+Description:[ \t]*/,"",desc)
            gsub(/"/,"",desc)
            printf "S\t%s\t%s\n", name, desc
        }')
    SINKS_JSON="[${json}]"
    # Keep the cache file other tools may read in sync.
    printf '%s\n' "$SINKS_JSON" > /tmp/quickshell/sinks_cache
}

_refresh_sinks_cache

emit() {
    local RAW VOL MUTED LABEL DEFAULT SINK

    RAW=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
    # "Volume: 0.55" or "Volume: 0.55 [MUTED]"
    VOL=${RAW#Volume: }
    VOL=${VOL%% *}
    if [[ "$VOL" =~ ^[0-9]+\.[0-9]{2}$ ]]; then
        VOL=$(( 10#${VOL/./} ))
    else
        VOL=$(awk -v v="$VOL" 'BEGIN {printf "%d", v*100}')
    fi
    MUTED=false
    LABEL="ON"
    if [[ "$RAW" == *MUTED* ]]; then
        MUTED=true
        LABEL="MUTED"
    fi

    DEFAULT=$(pactl get-default-sink)
    SINK=""
    if [[ -n "$DEFAULT" ]]; then
        SINK="${SINK_DESC[$DEFAULT]-}"
        if [[ -z "$SINK" ]]; then
            # A default sink we haven't seen yet (hot-plug race): re-read once.
            _refresh_sinks_cache
            SINK="${SINK_DESC[$DEFAULT]-}"
        fi
    fi
    SINK=${SINK:-Unknown}

    # Don't advertise the fallback as the active device
    if is_dummy "$DEFAULT" || is_dummy "$SINK"; then
        SINK="Unknown"
    fi
    echo "$SINK" > /tmp/quickshell/active_sink

    printf '{"volume":%s,"muted":%s,"label":"%s","sink":"%s","sinks":%s}\n' \
        "$VOL" "$MUTED" "$LABEL" "$SINK" "$SINKS_JSON"
}

emit

# Trailing debounce: collect events, act once things go quiet for 80ms.
# Topology events (new/remove/server) are never dropped, so the cache
# always reflects the final state after a profile switch.
#   idle    -> blocking read (no timer, no wakeups)
#   pending -> read with an 80ms timeout to detect the end of the burst
dirty=0
topo=0
while true; do
    if (( dirty )); then
        IFS= read -r -t 0.08 EVENT
    else
        IFS= read -r EVENT
    fi
    rc=$?
    if (( rc == 0 )); then
        dirty=1
        if [[ "$EVENT" =~ (new|remove|server) ]]; then
            topo=1
        fi
    elif (( rc > 128 )); then
        # timeout: the burst is over
        if (( dirty )); then
            if (( topo )); then
                _refresh_sinks_cache
                topo=0
            fi
            dirty=0
            emit
        fi
    else
        break        # EOF: pactl subscribe died
    fi
done < <(pactl subscribe 2>/dev/null | grep --line-buffered -E "sink|server")
