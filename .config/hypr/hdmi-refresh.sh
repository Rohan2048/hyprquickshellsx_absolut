#!/usr/bin/env bash
# -----------------------------------------------
# LOGIN DISPLAY DEFAULT
# Forces laptop-only at Hyprland startup, regardless of what's plugged in.
# Does NOT launch Quickshell - call this from your session-start script
# BEFORE the `quickshell` line, so monitor layout is settled first (avoids
# Quickshell enumerating a screen that's about to get disabled and
# creating a duplicate bar for it).
# -----------------------------------------------

# Poll instead of blind sleep - matters more here than anywhere else, since
# outputs may not be fully settled the instant this runs at startup.
# hyprctl calls are wrapped in `timeout` throughout: if Hyprland's IPC is
# ever slow to respond (e.g. right after a crash), an unbounded hyprctl
# call would hang this whole script indefinitely instead of just failing.
wait_for_monitor_state() {
    local output="$1" want="$2" timeout_s="$3" waited=0
    local max=$(( timeout_s * 10 ))
    while true; do
        state=$(timeout 2 hyprctl monitors all | awk -v mon="$output" '
            $0 ~ "^Monitor "mon"[ (]" {found=1}
            found && /^[[:space:]]*disabled:/ {print $2; exit}
        ')
        [ "$state" = "$want" ] && return 0
        sleep 0.1
        waited=$((waited + 1))
        [ "$waited" -ge "$max" ] && return 1
    done
}

MONITORS="$(timeout 3 hyprctl monitors all)"

INTERNAL=$(echo "$MONITORS" | grep -oE "^Monitor (eDP-[0-9]+|LVDS-[0-9]+)" | awk '{print $2}' | head -n1)
[ -z "$INTERNAL" ] && INTERNAL="eDP-1"

EXTERNAL=$(echo "$MONITORS" | grep -oE "^Monitor [A-Za-z0-9-]+" | awk '{print $2}' | grep -v -x "$INTERNAL" | grep -v -iE "^Unknown-" | head -n1)

# Disable EXTERNAL *before* enabling INTERNAL at 0x0 - not after. If the
# prior session was "External Only", EXTERNAL is still live at 0x0 right
# now; enabling INTERNAL into that same position first (the old order)
# is the exact transient-overlap that segfaulted Hyprland in hdmi.sh
# before that got reordered. Same fix applies here.
if [ -n "$EXTERNAL" ]; then
    timeout 5 hyprctl eval "hl.monitor({ output = \"$EXTERNAL\", disabled = true })"
    if ! wait_for_monitor_state "$EXTERNAL" "true" 3; then
        # Retry once, then proceed regardless - still attempt to bring up
        # INTERNAL rather than leaving the session with nothing enabled.
        timeout 5 hyprctl eval "hl.monitor({ output = \"$EXTERNAL\", disabled = true })"
        wait_for_monitor_state "$EXTERNAL" "true" 3
    fi
fi

# See hdmi.sh for why: don't hand-parse a res@refresh string out of
# `availableModes` (EDID order != safe-mode-first order). Use "preferred".
# mirror = "none" clears any mirror relationship INTERNAL could in theory
# carry over (hl.monitor fields appear to persist across calls otherwise -
# same reason hdmi.sh's set_monitor() explicitly clears it).
timeout 5 hyprctl eval "hl.monitor({ output = \"$INTERNAL\", mode = \"preferred\", position = \"0x0\", scale = 1.5, disabled = false, mirror = \"none\" })"
if ! wait_for_monitor_state "$INTERNAL" "false" 3; then
    timeout 5 hyprctl eval "hl.monitor({ output = \"$INTERNAL\", mode = \"preferred\", position = \"0x0\", scale = 1.5, disabled = false, mirror = \"none\" })"
    wait_for_monitor_state "$INTERNAL" "false" 3
fi
