#hdmi.sh

#!/usr/bin/env bash
# -----------------------------------------------
# HDMI/EXTERNAL OUTPUT SCRIPT
# Run: bash ~/.config/hypr/hdmi.sh
# Requires: ~/.config/rofi/hdmi.rasi (place hdmi.rasi there)
# Uses `hyprctl eval` (Lua config provider) - `hyprctl keyword` does not
# work under a Lua-based hyprland.lua config.
# -----------------------------------------------

set_monitor() {
    # $1=output $2=mode(res@refresh or "preferred") $3=position $4=scale
    if [ -z "$1" ]; then
        echo "set_monitor: refusing empty output (would be a wildcard hl.monitor rule)" >&2
        return 1
    fi
    timeout 5 hyprctl eval "hl.monitor({ output = \"$1\", mode = \"$2\", position = \"$3\", scale = $4, disabled = false, mirror = \"none\" })"
}

disable_monitor() {
    # $1=output
    # Empty output = no external ever detected. An hl.monitor call with
    # output="" is (as far as we can tell) treated as a wildcard/default
    # rule for ANY monitor lacking an explicit one - not "disable nothing".
    # That can end up disabling INTERNAL too and out-precedence the explicit
    # set_monitor("$INTERNAL", ...) call that follows, which is exactly the
    # "Laptop Only never turns the laptop screen on" bug. Refuse instead.
    if [ -z "$1" ]; then
        echo "disable_monitor: refusing empty output (would be a wildcard hl.monitor rule)" >&2
        return 1
    fi
    timeout 5 hyprctl eval "hl.monitor({ output = \"$1\", disabled = true })"
}

mirror_monitor() {
    # $1=output $2=mode $3=position $4=scale $5=mirror-target-output
    if [ -z "$1" ] || [ -z "$5" ]; then
        echo "mirror_monitor: refusing empty output/mirror-target" >&2
        return 1
    fi
    timeout 5 hyprctl eval "hl.monitor({ output = \"$1\", mode = \"$2\", position = \"$3\", scale = $4, mirror = \"$5\", disabled = false })"
}

# Shared mutex between this interactive flow and the background watcher, so
# an unplug that happens mid-selection can't make both fire qs kill/qs -d
# at the same time.
LOCKFILE="/tmp/.hdmi-script.lock"

# Last-resort fallback: force the laptop panel back on. Called from every
# abort path below. If a cable gets pulled mid-sequence (e.g., right after we
# disable INTERNAL for "External Only" but before EXTERNAL confirms), just
# exiting leaves BOTH outputs off - not a hang, just nothing displaying
# anywhere. This guarantees we never abort into a state with zero active
# outputs, regardless of which step failed or why.
fail_safe() {
    local reason="$1"
    notify-send "Display" "$reason - reverting to laptop screen"
    set_monitor "$INTERNAL" "preferred" "0x0" "1.5"
    if ! wait_for_monitor_state "$INTERNAL" "false" 3; then
        set_monitor "$INTERNAL" "preferred" "0x0" "1.5"
        wait_for_monitor_state "$INTERNAL" "false" 3
    fi
    # Release before qs -d, same reasoning as the main flow below - don't
    # hold the mutex through a call that might not return promptly.
    flock -u 9 2>/dev/null
    exec 9>&- 2>/dev/null
    # Explicitly backgrounded - don't trust qs -d to daemonize itself.
    qs -d >/dev/null 2>&1 &
    disown
    exit 1
}

# Poll instead of blind sleep. Waits up to $2 seconds (checked every 0.1s)
# for `pgrep -x "$1"` to report the process gone. Returns 1 on timeout
# instead of just barrelling ahead - the caller decides whether that's fatal.
wait_for_exit() {
    local name="$1" timeout="$2" waited=0
    local max=$(( timeout * 10 ))
    while pgrep -x "$name" > /dev/null 2>&1; do
        sleep 0.1
        waited=$((waited + 1))
        [ "$waited" -ge "$max" ] && return 1
    done
    return 0
}

# Poll instead of blind sleep. Waits up to $3 seconds for `hyprctl monitors
# all` to report the given output's `disabled:` field as $2 ("true"/"false").
# Returns 1 on timeout. This is the actual ready-signal for "did the monitor
# reconfig land" instead of guessing a sleep duration.
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

# Poll until `hyprctl monitors all` returns two consecutive IDENTICAL reads.
# wait_for_monitor_state only confirms one field (disabled:) on one output -
# it says nothing about whether Hyprland has finished propagating the full
# layout (positions, workspace assignment) to Wayland clients over
# wlr-output-manager. That propagation lags the internal state flip by up
# to a few hundred ms, more so right after a disabled->enabled transition
# and worse still in Extend, where two outputs are being reconciled into
# one layout instead of one. Launching qs -d inside that lag window hands
# Quickshell a screen list that's stale or still mutating - which is what
# was showing up as a missing wallpaper on one output (its background
# window built off a screen list that didn't include it yet) and,
# intermittently, a duplicate bar (the screen list changed again right
# after Quickshell had already built windows for the old one). Best
# effort only: on timeout we proceed anyway rather than fail_safe, since
# worst case here is a cosmetic re-render, not a broken monitor state.
get_logical_width() {
    # Logical width (post-scale) of $1, e.g. 1920 physical @ scale 1.5 -> 1280.
    # Extend needs this for EXTERNAL's x-position - hardcoding it (as the
    # old "1280x0" did) assumes every panel is 1920 wide at scale 1.5,
    # which produced Hyprland's "Monitor eDP-1 overlaps" warning on a
    # panel where that assumption doesn't hold. Read it from `hyprctl -j
    # monitors` instead of scraping the human-readable table, so this
    # works for whatever panel is actually attached. Requires jq.
    local output="$1"
    timeout 2 hyprctl -j monitors all | jq -er --arg name "$output" \
        '.[] | select(.name == $name) | ((.width / .scale) | floor)' 2>/dev/null
}

wait_for_monitors_settled() {
    local timeout_s="${1:-3}" waited=0
    local max=$(( timeout_s * 10 ))
    local prev="" cur
    while true; do
        cur=$(timeout 2 hyprctl monitors all)
        if [ -n "$cur" ] && [ "$cur" = "$prev" ]; then
            return 0
        fi
        prev="$cur"
        sleep 0.1
        waited=$((waited + 1))
        [ "$waited" -ge "$max" ] && return 1
    done
}

# --- keep the apps when an output is switched off ----------------------------
# "Laptop Only" / "External Only" disable an output. Windows on the workspaces
# of that output used to be left behind: still running (the taskbar shows them)
# but on a workspace no enabled output shows, so they were missing from window
# thumbnails and the workspace overview. So before an output is disabled its
# workspaces are moved onto the output that stays on. The processes are never
# touched - only which output their workspace lives on.
monitor_disabled() {
    # $1=output -> prints true|false from the startup snapshot
    echo "$MONITORS" | awk -v mon="$1" '
        $0 ~ "^Monitor "mon"[ (]" {found=1}
        found && /^[[:space:]]*disabled:/ {print $2; exit}
    '
}

rightmost_edge() {
    # Logical right edge of the furthest-right ENABLED output.
    timeout 2 hyprctl -j monitors | jq -r '[.[] | ((.x + (.width / .scale)) | floor)] | max // empty' 2>/dev/null
}

move_workspaces() {
    # $1=from-output $2=to-output. Moves every workspace on $1 that holds windows
    # (plus its active one, moved LAST so it stays the visible workspace on $2).
    local from="$1" to="$2" active ids ws
    [ -z "$from" ] && return 0
    [ -z "$to" ] && return 0
    [ "$from" = "$to" ] && return 0
    command -v jq >/dev/null 2>&1 || return 0
    active=$(timeout 2 hyprctl -j monitors all | jq -r --arg n "$from" '.[] | select(.name == $n) | .activeWorkspace.id // empty' 2>/dev/null)
    ids=$(timeout 2 hyprctl -j workspaces | jq -r --arg n "$from" '.[] | select(.monitor == $n and .id > 0 and .windows > 0) | .id' 2>/dev/null)
    for ws in $(echo "$ids" | grep -vx "${active:-none}") $active; do
        [[ "$ws" =~ ^[0-9]+$ ]] || continue
        timeout 5 hyprctl dispatch "hl.dsp.workspace.move({ workspace = \"$ws\", monitor = \"$to\" })" >/dev/null 2>&1
    done
}

# Snapshot monitor state ONCE up front. Everything below decides from this
# single snapshot instead of re-querying hyprctl repeatedly.
MONITORS="$(timeout 3 hyprctl monitors all)"

# INTERNAL = the laptop panel, whatever it's actually named (eDP-*, LVDS-*).
INTERNAL=$(echo "$MONITORS" | grep -oE "^Monitor (eDP-[0-9]+|LVDS-[0-9]+)" | awk '{print $2}' | head -n1)
[ -z "$INTERNAL" ] && INTERNAL="eDP-1"

# EXTERNAL = the first connected monitor that ISN'T the internal panel.
# Connector-agnostic: HDMI-A-*, DP-*, DVI-*, whatever.
# Excludes "Unknown-*" - a known Hyprland/kernel bug can surface a phantom
# monitor under that name when a real one is plugged/unplugged, and treating
# it as real leads to a full compositor/GPU lockup.
EXTERNAL=$(echo "$MONITORS" | grep -oE "^Monitor [A-Za-z0-9-]+" | awk '{print $2}' | grep -v -x "$INTERNAL" | grep -v -iE "^Unknown-" | head -n1)

# NOTE: we no longer hand-parse a res@refresh string out of `availableModes`.
# That line lists modes in EDID order, NOT "safe mode first" order - picking
# $2 off it can hand hl.monitor a mode the panel/GPU combo can't actually
# drive, which is a full modeset lockup (hard-shutdown-only), not a soft
# glitch. We use the "preferred" keyword instead and let Hyprland pick the
# EDID-preferred mode itself.

INTERNAL_CONNECTED=$(echo "$MONITORS" | grep -c "^Monitor $INTERNAL")

if [ -n "$EXTERNAL" ]; then
    EXTERNAL_CONNECTED=1
else
    EXTERNAL_CONNECTED=0
fi

# Background monitor event watcher (only start if not already running)
if ! pgrep -f "socket2.sock" > /dev/null; then
    socat - UNIX-CONNECT:/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock | while read -r line; do
        NOW=$(date +%s)
        LAST=$(cat /tmp/.hdmi-watcher-last 2>/dev/null || echo 0)
        # Debounce: ignore events within 3s of the last handled one. Without
        # this, an HPD interrupt storm (flapping hotplug signal) makes
        # Hyprland fire a burst of monitoradded/monitorremoved events, and
        # each one used to trigger another hyprctl eval + qs kill/qs -d -
        # hammering the compositor while the connector itself is unstable,
        # which is a solid way to wedge it. One reaction per storm is enough.
        if [ "$((NOW - LAST))" -lt 3 ]; then
            continue
        fi
        if echo "$line" | grep -q "monitoradded"; then
            echo "$NOW" > /tmp/.hdmi-watcher-last
            notify-send "Display" "Monitor connected - press Alt+S to configure"
        elif echo "$line" | grep -q "monitorremoved"; then
            echo "$NOW" > /tmp/.hdmi-watcher-last
            # Same mutex as the interactive picker. If it's currently running
            # (you were mid-selection when the cable came out), let it own
            # the recovery - its own wait_for_monitor_state/fail_safe path
            # already handles a disconnect. Don't pile another qs kill/qs -d
            # on top of it.
            exec 8>"$LOCKFILE"
            if ! flock -n 8; then
                exec 8>&-
                continue
            fi
            timeout 5 qs kill 2>/dev/null
            if ! wait_for_exit "qs" 3; then
                notify-send "Display" "Quickshell didn't exit in time - skipping revert"
                flock -u 8
                exec 8>&-
                continue
            fi
            set_monitor "$INTERNAL" "preferred" "0x0" "1.5"
            if ! wait_for_monitor_state "$INTERNAL" "false" 3; then
                # One retry - $INTERNAL is never empty so this isn't the
                # wildcard-rule issue, just a slow/missed apply. Worth one
                # more shot before giving up.
                set_monitor "$INTERNAL" "preferred" "0x0" "1.5"
                wait_for_monitor_state "$INTERNAL" "false" 3
            fi
            wait_for_monitors_settled 3
            # Always relaunch Quickshell regardless of whether the state
            # check above confirmed - leaving it dead is strictly worse than
            # launching it against a monitor state we merely couldn't verify.
            flock -u 8
            exec 8>&-
            qs -d >/dev/null 2>&1 &
            disown
            notify-send "Display" "Monitor disconnected - reverted to laptop screen"
        fi
    done &
fi

if [ "$INTERNAL_CONNECTED" -eq 0 ] && [ "$EXTERNAL_CONNECTED" -eq 0 ]; then
    notify-send "Display" "No display detected"
    exit 0
fi

# Build options based on what's connected
OPTIONS="Laptop Only"
if [ "$EXTERNAL_CONNECTED" -gt 0 ]; then
    OPTIONS="$OPTIONS\nExternal Only\nMirror\nExtend"
fi
LINE_COUNT=$(echo -e "$OPTIONS" | wc -l)

CHOICE=$(echo -e "$OPTIONS" | ~/.config/quickshell/scripts/qs-pick.sh list hdmi "Display Mode")
if [ $? -eq 3 ]; then
    # menu set to Rofi, or Quickshell is not running: the normal rofi menu
    CHOICE=$(echo -e "$OPTIONS" | rofi -dmenu \
        -theme ~/.config/rofi/hdmi.rasi \
        -mesg "Display Mode" \
        -theme-str "listview { lines: ${LINE_COUNT}; }" \
        -no-custom)
fi

[ -z "$CHOICE" ] && exit 0

# Mutex against the background watcher below. If you unplug the cable while
# actively picking a mode in rofi, both this flow and the watcher's
# monitorremoved handler could fire qs kill/qs -d concurrently - held for
# the rest of this process's life, auto-released on exit (any exit path,
# including fail_safe's `exit 1`), no manual unlock needed here.
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    notify-send "Display" "Display change already in progress - try again in a moment"
    exit 1
fi

# Kill Quickshell BEFORE reconfiguring monitors, not after. If any popup
# (Battery/Calendar/Volume/Wifi/Bluetooth/Commands/Music) has a live
# HyprlandFocusGrab when we disable the output it's anchored to, Hyprland's
# CFocusGrab::finish() runs against a surface that's mid-teardown - SEGV.
# This is what crashed Hyprland into safe mode on "External Only".
timeout 5 qs kill 2>/dev/null
if ! wait_for_exit "qs" 3; then
    notify-send "Display" "Quickshell didn't exit in time - aborting, not touching monitors"
    exit 1
fi

case "$CHOICE" in
    "Laptop Only")
        # Laptop panel currently off: bring it up to the right of the external
        # first (same as Extend, no overlap) so the windows have somewhere to go.
        if [ "$(monitor_disabled "$INTERNAL")" = "true" ]; then
            RIGHT="$(rightmost_edge)"
            [ -z "$RIGHT" ] && RIGHT=1280
            set_monitor "$INTERNAL" "preferred" "${RIGHT}x0" "1.5" || fail_safe "set_monitor(\$INTERNAL) call failed"
            wait_for_monitor_state "$INTERNAL" "false" 3 || fail_safe "$INTERNAL didn't come up in time"
        fi
        if [ -n "$EXTERNAL" ]; then
            move_workspaces "$EXTERNAL" "$INTERNAL"
            wait_for_monitors_settled 1
            disable_monitor "$EXTERNAL" || fail_safe "disable_monitor(\$EXTERNAL) call failed"
            wait_for_monitor_state "$EXTERNAL" "true" 3 || fail_safe "$EXTERNAL didn't disable in time"
        fi
        set_monitor "$INTERNAL" "preferred" "0x0" "1.5" || fail_safe "set_monitor(\$INTERNAL) call failed"
        wait_for_monitor_state "$INTERNAL" "false" 3 || fail_safe "$INTERNAL didn't come up in time"
        ;;
    "External Only")
        # External currently off: bring it up to the right of the laptop panel
        # first (same as Extend, no overlap, never zero outputs) so the laptop's
        # windows have somewhere to go before the panel is disabled.
        if [ "$(monitor_disabled "$EXTERNAL")" = "true" ]; then
            RIGHT="$(rightmost_edge)"
            [ -z "$RIGHT" ] && RIGHT=1280
            set_monitor "$EXTERNAL" "preferred" "${RIGHT}x0" "1" || fail_safe "set_monitor(\$EXTERNAL) call failed"
            wait_for_monitor_state "$EXTERNAL" "false" 3 || fail_safe "$EXTERNAL didn't come up in time (cable pulled?)"
        fi
        move_workspaces "$INTERNAL" "$EXTERNAL"
        wait_for_monitors_settled 1
        disable_monitor "$INTERNAL" || fail_safe "disable_monitor(\$INTERNAL) call failed"
        wait_for_monitor_state "$INTERNAL" "true" 3 || fail_safe "$INTERNAL didn't disable in time"
        set_monitor "$EXTERNAL" "preferred" "0x0" "1" || fail_safe "set_monitor(\$EXTERNAL) call failed"
        wait_for_monitor_state "$EXTERNAL" "false" 3 || fail_safe "$EXTERNAL didn't come up in time (cable pulled?)"
        ;;
    "Mirror")
        set_monitor "$INTERNAL" "preferred" "0x0" "1.5" || fail_safe "set_monitor(\$INTERNAL) call failed"
        wait_for_monitor_state "$INTERNAL" "false" 3 || fail_safe "$INTERNAL didn't come up in time"
        mirror_monitor "$EXTERNAL" "preferred" "0x0" "1" "$INTERNAL" || fail_safe "mirror_monitor(\$EXTERNAL) call failed"
        wait_for_monitor_state "$EXTERNAL" "false" 3 || fail_safe "$EXTERNAL didn't come up in time (cable pulled?)"
        ;;
    "Extend")
        # 1. Enable internal monitor first at 0x0
        set_monitor "$INTERNAL" "preferred" "0x0" "1.5" || fail_safe "set_monitor(\$INTERNAL) call failed"
        wait_for_monitor_state "$INTERNAL" "false" 3 || fail_safe "$INTERNAL didn't come up in time"

        # 2. Calculate logical width of internal monitor to position external exactly to its right
        INTERNAL_WIDTH="$(get_logical_width "$INTERNAL")"
        if [ -z "$INTERNAL_WIDTH" ]; then
            notify-send "Display" "Couldn't read $INTERNAL's logical width, falling back to 1280"
            INTERNAL_WIDTH=1280
        fi

        # 3. Enable external monitor to the right of the internal monitor.
        # Note: Scale is hardcoded to "1" here. If your external monitor is high-DPI (e.g., 4K),
        # you may want to change "1" to "1.5" or "2" to match your preference.
        set_monitor "$EXTERNAL" "preferred" "${INTERNAL_WIDTH}x0" "1" || fail_safe "set_monitor(\$EXTERNAL) call failed"
        wait_for_monitor_state "$EXTERNAL" "false" 3 || fail_safe "$EXTERNAL didn't come up in time (cable pulled?)"
        ;;
esac

# Give Hyprland a moment to finish propagating the full layout (positions,
# workspace reassignment) to Wayland clients before Quickshell re-enumerates
# screens. See wait_for_monitors_settled for why this matters - best effort,
# proceed either way.
wait_for_monitors_settled 3

# Release the mutex now, BEFORE launching Quickshell - not after. If
# `qs -d` doesn't return immediately (foregrounds instead of properly
# daemonizing, or is just slow), holding the lock through it means this
# script's process never reaches exit, the fd 9 lock never releases, and
# every subsequent run reports "already in progress" forever even though
# nothing is actually happening. The risky monitor-reconfig section is
# done and confirmed by this point - there's no reason to still be
# holding the mutex through the shell relaunch.
flock -u 9
exec 9>&-

qs -d >/dev/null 2>&1 &
disown
notify-send "Display" "Applied: $CHOICE"
