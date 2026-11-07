#!/usr/bin/env bash
# volume-listener.sh — emits {volume, muted, sink, sinks, label} JSON
# driven by pactl subscribe

mkdir -p /tmp/quickshell

# ── Sink list cache ───────────────────────────────────────────────────────
# Re-fetching pactl list sinks/cards on every volume event is expensive.
# We cache it and only refresh on sink add/remove/server/card events.
#
# Two kinds of entries, one row per real output DEVICE (not per port):
#   kind="sink"    -> a real, currently-instantiated pactl sink -- the
#                      currently active output for its card. Switching to
#                      it is just `pactl set-default-sink`.
#   kind="profile" -> a valid output on some card that ISN'T currently
#                      active, so it has no sink object right now
#                      (PipeWire only instantiates a sink for whichever
#                      profile is active -- see e.g. `aplay -l` seeing
#                      HDMI subdevices the sink list doesn't). This is
#                      NOT HDMI-specific: if you're on hdmi-surround,
#                      your analog output is JUST AS invisible from
#                      `pactl list sinks` as an idle HDMI port would be
#                      -- so every valid, currently-inactive profile
#                      on every card gets listed here, generically.
#                      Switching requires `pactl set-card-profile` first
#                      (see set-sink.sh), then set-default-sink once the
#                      new sink appears.
#
# Each cache entry:
#   {"sink":"<name>","port":"<port>","label":"<label>","kind":"sink|profile","active":true|false}
# "sink" is the pactl sink name (kind=sink) or card name (kind=profile) to
# act on. "port" is "" for kind=sink, or "profile:<profileName>" for
# kind=profile. "active" is computed here (not guessed client-side from
# string matching) -- exactly one entry should be active at a time.

_refresh_sinks_cache() {
    local sinks_raw cards_raw default_sink
    sinks_raw=$(pactl list sinks 2>/dev/null)
    cards_raw=$(pactl list cards 2>/dev/null)
    default_sink=$(pactl get-default-sink 2>/dev/null)

    # ── Real, currently-instantiated sinks ──────────────────────────────
    SINKS_JSON=$(echo "$sinks_raw" | awk -v default="$default_sink" '
    BEGIN { RS=""; FS="\n"; first=1 }
    {
        name=""; desc=""
        for (i=1; i<=NF; i++) {
            line=$i
            if (line ~ /^[[:space:]]*Name:/) {
                name=line; sub(/^[[:space:]]*Name:[[:space:]]*/,"",name)
            }
            if (line ~ /^[[:space:]]*Description:/) {
                desc=line; sub(/^[[:space:]]*Description:[[:space:]]*/,"",desc)
            }
        }
        if (name != "" && desc != "") {
            gsub(/\\/,"\\\\",desc); gsub(/"/,"\\\"",desc)
            gsub(/\\/,"\\\\",name); gsub(/"/,"\\\"",name)
            active = (name == default) ? "true" : "false"
            if (!first) printf ","
            printf "{\"sink\":\"%s\",\"port\":\"\",\"label\":\"%s\",\"kind\":\"sink\",\"active\":%s}", name, desc, active
            first=0
        }
    }
    ')

    # ── Every valid, currently-INACTIVE output profile, on every card ──
    # Criteria for a "valid output profile" line inside a card's Profiles:
    # block, e.g. "output:hdmi-stereo: Digital Stereo (HDMI) Output
    # (sinks: 1, sources: 0, priority: 5900, available: yes)":
    #   - id starts with "output:"     (excludes off:, pro-audio:, input:*)
    #   - id has no "+input"           (excludes duplex variants -- same
    #                                    physical output, just also wired
    #                                    as a mic input; would duplicate
    #                                    the plain output: profile)
    #   - "sinks: [1-9]"               (profile actually produces an output)
    #   - "available: yes"             (port physically present/plugged in)
    #   - profile id != this card's current Active Profile (that one is
    #     already listed above via the real sink entry)
    PROFILES_JSON=$(echo "$cards_raw" | awk '
    BEGIN { RS=""; FS="\n"; first=1 }
    {
        cardname=""; activeprof=""
        for (i=1; i<=NF; i++) {
            line=$i
            if (line ~ /^[[:space:]]*Name:/) {
                cardname=line; sub(/^[[:space:]]*Name:[[:space:]]*/,"",cardname)
            }
            if (line ~ /^[[:space:]]*Active Profile:/) {
                activeprof=line; sub(/^[[:space:]]*Active Profile:[[:space:]]*/,"",activeprof)
            }
        }
        for (i=1; i<=NF; i++) {
            line=$i
            trimmed=line
            sub(/^[[:space:]]+/,"",trimmed)

            if (trimmed !~ /^output:/) continue
            if (trimmed ~ /\+input/) continue
            if (trimmed !~ /sinks: [1-9]/) continue
            if (trimmed !~ /available: yes/) continue

            idx = index(trimmed, ": ")
            if (idx == 0) continue
            profid = substr(trimmed, 1, idx-1)

            if (profid == activeprof) continue   # already shown as kind=sink

            label = substr(trimmed, idx+2)
            sub(/[[:space:]]*\(.*$/,"",label)
            sub(/ Output$/,"",label)

            gsub(/\\/,"\\\\",label);    gsub(/"/,"\\\"",label)
            gsub(/\\/,"\\\\",profid);   gsub(/"/,"\\\"",profid)
            gsub(/\\/,"\\\\",cardname); gsub(/"/,"\\\"",cardname)

            if (!first) printf ","
            printf "{\"sink\":\"%s\",\"port\":\"profile:%s\",\"label\":\"%s\",\"kind\":\"profile\",\"active\":false}", cardname, profid, label
            first=0
        }
    }
    ')

    if [ -n "$SINKS_JSON" ] && [ -n "$PROFILES_JSON" ]; then
        echo "[${SINKS_JSON},${PROFILES_JSON}]" > /tmp/quickshell/sinks_cache
    else
        echo "[${SINKS_JSON}${PROFILES_JSON}]" > /tmp/quickshell/sinks_cache
    fi
}

# Warm up on start if not already done (preload.sh may have done this)
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
    echo "$SINK" > /tmp/quickshell/active_sink

    SINKS=$(cat /tmp/quickshell/sinks_cache 2>/dev/null || echo "[]")

    printf '{"volume":%s,"muted":%s,"label":"%s","sink":"%s","sinks":%s}\n' \
        "$VOL" "$MUTED" "$LABEL" "$SINK" "$SINKS"
}

emit

LAST_EMIT=0
while IFS= read -r EVENT; do
    NOW=$(date +%s%3N)
    if (( NOW - LAST_EMIT > 100 )); then
        LAST_EMIT=$NOW

        if echo "$EVENT" | grep -qE "sink #|server|card #"; then
            _refresh_sinks_cache
        fi

        emit
    fi
done < <(pactl subscribe 2>/dev/null | grep --line-buffered -E "sink|server|card")
