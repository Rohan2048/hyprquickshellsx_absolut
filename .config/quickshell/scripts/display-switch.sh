#!/usr/bin/env bash
# -----------------------------------------------
# display-switch.sh <only|extend|mirror> <output> [scale]
#
# Non-interactive version of ~/.config/hypr/hdmi.sh (no rofi). Called detached
# by Settings > Display from an output's three-dot menu.
#
#   only    <output>  show ONLY <output>   (hdmi.sh "Laptop Only" / "External Only")
#   extend  <output>  laptop panel at 0x0, <output> to its right   (hdmi.sh "Extend")
#   mirror  <output>  laptop panel at 0x0, <output> mirrors it     (hdmi.sh "Mirror")
#
# For extend / mirror <output> is the EXTERNAL display; the laptop panel is
# detected the same way hdmi.sh does (eDP-* / LVDS-*). [scale] is the scale for
# <output> (default: 1 for an external, 1.5 for the laptop panel, like hdmi.sh).
# The laptop panel keeps its current scale if it is already on, else 1.5.
#
# Same safety rules as hdmi.sh, copied on purpose:
#  * Quickshell is killed BEFORE any output is touched and relaunched after.
#    A live HyprlandFocusGrab on an output that is being disabled SEGVs
#    Hyprland (that is what crashed it into safe mode on "External Only").
#  * "only": other outputs are DISABLED first, the target is ENABLED second.
#  * mode is "preferred", never a hand-picked res@refresh (EDID order is not
#    safe-mode-first order).
#  * Extend positions the external at the laptop panel's LOGICAL width
#    (read from hyprctl -j, needs jq) instead of a hardcoded 1280.
#  * Shares /tmp/.hdmi-script.lock with hdmi.sh and its hotplug watcher.
#  * Any failure falls back to the laptop panel so we never end with every
#    output off.
#  * Windows are CONSERVED: before an output is disabled, its workspaces (and the
#    windows on them) are moved onto the output that stays on, so the apps keep
#    running AND stay visible in thumbnails / the workspace overview. If the
#    target is currently off it is first brought up to the right of everything
#    that is on (no overlap, no moment with zero outputs), then moved to 0x0
#    after the others are off.
# Uses `hyprctl eval` (Lua config); `hyprctl keyword` does not work there.
# -----------------------------------------------

MODE="$1"
TARGET="$2"
SCALE="${3:-}"
LOCKFILE="/tmp/.hdmi-script.lock"

case "$MODE" in only|extend|mirror) ;; *) notify-send "Display" "Unknown display mode"; exit 1 ;; esac

# Both values end up inside a Lua string / number: refuse anything odd.
if ! [[ "$TARGET" =~ ^[A-Za-z0-9-]+$ ]]; then
    notify-send "Display" "Refusing odd output name"
    exit 1
fi
[[ "$SCALE" =~ ^[0-9]+(\.[0-9]+)?$ ]] || SCALE=""

set_monitor() {
    # $1=output $2=mode $3=position $4=scale
    [ -z "$1" ] && { echo "set_monitor: refusing empty output" >&2; return 1; }
    timeout 5 hyprctl eval "hl.monitor({ output = \"$1\", mode = \"$2\", position = \"$3\", scale = $4, disabled = false, mirror = \"none\" })"
}

disable_monitor() {
    [ -z "$1" ] && { echo "disable_monitor: refusing empty output" >&2; return 1; }
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

get_logical_width() {
    # Logical width (post-scale) of $1, e.g. 1920 physical @ scale 1.5 -> 1280.
    local output="$1"
    timeout 2 hyprctl -j monitors all | jq -er --arg name "$output" \
        '.[] | select(.name == $name) | ((.width / .scale) | floor)' 2>/dev/null
}

rightmost_edge() {
    # Logical right edge of the furthest-right ENABLED output.
    timeout 2 hyprctl -j monitors | jq -r '[.[] | ((.x + (.width / .scale)) | floor)] | max // empty' 2>/dev/null
}

move_workspaces() {
    # $1=from-output $2=to-output. Moves every workspace on $1 that holds windows
    # (plus its active one, moved LAST so it stays the visible workspace on $2)
    # onto $2. The apps are not touched, only which output their workspace is on.
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

get_state() {
    # $1=output $2=disabled|scale  (from the human-readable table, like hdmi.sh)
    echo "$MONITORS" | awk -v mon="$1" -v key="$2" '
        $0 ~ "^Monitor "mon"[ (]" {found=1}
        found && key == "disabled" && /^[[:space:]]*disabled:/ {print $2; exit}
        found && key == "scale" && /^[[:space:]]*scale:/ {print $2; exit}
    '
}

MONITORS="$(timeout 3 hyprctl monitors all)"

INTERNAL=$(echo "$MONITORS" | grep -oE "^Monitor (eDP-[0-9]+|LVDS-[0-9]+)" | awk '{print $2}' | head -n1)
[ -z "$INTERNAL" ] && INTERNAL="eDP-1"

# Every connected output, minus the phantom "Unknown-*" monitor a known
# Hyprland/kernel bug can surface (never touch it).
ALL=$(echo "$MONITORS" | grep -oE "^Monitor [A-Za-z0-9-]+" | awk '{print $2}' | grep -v -iE "^Unknown-")

if ! echo "$ALL" | grep -qx "$TARGET"; then
    notify-send "Display" "$TARGET is not connected"
    exit 1
fi
if [ "$MODE" != "only" ]; then
    if [ "$TARGET" = "$INTERNAL" ]; then
        notify-send "Display" "Extend / Mirror need an external display"
        exit 1
    fi
    if ! echo "$ALL" | grep -qx "$INTERNAL"; then
        notify-send "Display" "Laptop panel $INTERNAL not found"
        exit 1
    fi
fi

# Scales. Target: what the page passed, else hdmi.sh's defaults (laptop 1.5,
# external 1). The laptop panel keeps its scale if it is currently on.
if [ -z "$SCALE" ]; then
    if [ "$TARGET" = "$INTERNAL" ]; then SCALE="1.5"; else SCALE="1"; fi
fi
INTERNAL_SCALE="1.5"
if [ "$(get_state "$INTERNAL" disabled)" = "false" ]; then
    s="$(get_state "$INTERNAL" scale)"
    [[ "$s" =~ ^[0-9]+(\.[0-9]+)?$ ]] && INTERNAL_SCALE="$s"
fi

fail_safe() {
    local reason="$1"
    notify-send "Display" "$reason - reverting to laptop screen"
    set_monitor "$INTERNAL" "preferred" "0x0" "1.5"
    if ! wait_for_monitor_state "$INTERNAL" "false" 3; then
        set_monitor "$INTERNAL" "preferred" "0x0" "1.5"
        wait_for_monitor_state "$INTERNAL" "false" 3
    fi
    flock -u 9 2>/dev/null
    exec 9>&- 2>/dev/null
    qs -d >/dev/null 2>&1 &
    disown
    exit 1
}

# Mutex shared with hdmi.sh (interactive picker + hotplug watcher).
exec 9>"$LOCKFILE"
if ! flock -n 9; then
    notify-send "Display" "Display change already in progress - try again in a moment"
    exit 1
fi

timeout 5 qs kill 2>/dev/null
if ! wait_for_exit "qs" 3; then
    notify-send "Display" "Quickshell didn't exit in time - aborting, not touching monitors"
    exit 1
fi

case "$MODE" in
    only)
        # 0. target currently off: bring it up to the right of everything that is
        #    on (same trick as Extend) so there is somewhere to put the windows
        #    before the others are disabled.
        if [ "$(get_state "$TARGET" disabled)" = "true" ]; then
            RIGHT="$(rightmost_edge)"
            [ -z "$RIGHT" ] && RIGHT=1280
            set_monitor "$TARGET" "preferred" "${RIGHT}x0" "$SCALE" || fail_safe "set_monitor($TARGET) call failed"
            wait_for_monitor_state "$TARGET" "false" 3 || fail_safe "$TARGET didn't come up in time (cable pulled?)"
        fi
        # 1. every other enabled output: move its workspaces (and windows) to the
        #    target, then disable it
        for out in $ALL; do
            [ "$out" = "$TARGET" ] && continue
            [ "$(get_state "$out" disabled)" = "true" ] && continue
            move_workspaces "$out" "$TARGET"
            wait_for_monitors_settled 1
            disable_monitor "$out" || fail_safe "disable_monitor($out) call failed"
            wait_for_monitor_state "$out" "true" 3 || fail_safe "$out didn't disable in time"
        done
        # 2. target to its final place
        set_monitor "$TARGET" "preferred" "0x0" "$SCALE" || fail_safe "set_monitor($TARGET) call failed"
        wait_for_monitor_state "$TARGET" "false" 3 || fail_safe "$TARGET didn't come up in time (cable pulled?)"
        DONE="Now showing: $TARGET"
        ;;
    mirror)
        set_monitor "$INTERNAL" "preferred" "0x0" "$INTERNAL_SCALE" || fail_safe "set_monitor($INTERNAL) call failed"
        wait_for_monitor_state "$INTERNAL" "false" 3 || fail_safe "$INTERNAL didn't come up in time"
        mirror_monitor "$TARGET" "preferred" "0x0" "$SCALE" "$INTERNAL" || fail_safe "mirror_monitor($TARGET) call failed"
        wait_for_monitor_state "$TARGET" "false" 3 || fail_safe "$TARGET didn't come up in time (cable pulled?)"
        DONE="Mirroring $INTERNAL on $TARGET"
        ;;
    extend)
        # 1. laptop panel first, at 0x0
        set_monitor "$INTERNAL" "preferred" "0x0" "$INTERNAL_SCALE" || fail_safe "set_monitor($INTERNAL) call failed"
        wait_for_monitor_state "$INTERNAL" "false" 3 || fail_safe "$INTERNAL didn't come up in time"
        # 2. external exactly to its right (logical width, post-scale)
        INTERNAL_WIDTH="$(get_logical_width "$INTERNAL")"
        if [ -z "$INTERNAL_WIDTH" ]; then
            notify-send "Display" "Couldn't read $INTERNAL's logical width, falling back to 1280"
            INTERNAL_WIDTH=1280
        fi
        set_monitor "$TARGET" "preferred" "${INTERNAL_WIDTH}x0" "$SCALE" || fail_safe "set_monitor($TARGET) call failed"
        wait_for_monitor_state "$TARGET" "false" 3 || fail_safe "$TARGET didn't come up in time (cable pulled?)"
        DONE="Extended $INTERNAL to $TARGET"
        ;;
esac

wait_for_monitors_settled 3

# Release the mutex BEFORE relaunching qs (see hdmi.sh: a qs that doesn't
# daemonize promptly would otherwise hold it forever).
flock -u 9
exec 9>&-

qs -d >/dev/null 2>&1 &
disown
notify-send "Display" "$DONE"
