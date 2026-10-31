#!/usr/bin/env bash
# battery-listener.sh — sysfs only, no subprocesses
BAT=/sys/class/power_supply/BAT0

# ── Early exit if no battery (desktop) ────────────────────────────────────
if [ ! -d "$BAT" ]; then
    printf '{"capacity":100,"time":"On Power","icon":"AC","status":"on_power"}\n'
    exit 0
fi

NOTIFY_FILE='/tmp/quickshell/battery_notify_state'
CAP_FILE='/tmp/quickshell/battery_cap_prev'
ENERGY_FULL_CACHE='/tmp/quickshell/battery_energy_full_cache'
mkdir -p /tmp/quickshell
capacity=$(cat "$BAT/capacity")
status=$(cat "$BAT/status")      # Charging, Discharging, Full
energy_now=$(cat "$BAT/energy_now")
power_now=$(cat "$BAT/power_now")

# ── energy_full cache ─────────────────────────────────────────────────────
# energy_full only changes during battery calibration. Cache it so we don't
# read the sysfs node on every poll cycle.
if [ ! -f "$ENERGY_FULL_CACHE" ]; then
    cat "$BAT/energy_full" > "$ENERGY_FULL_CACHE"
fi
energy_full=$(cat "$ENERGY_FULL_CACHE")

# ── Time remaining ────────────────────────────────────────────────────────
time="---"
if [[ "$power_now" -gt 0 ]]; then
    if [[ "$status" == "Discharging" ]]; then
        total_mins=$(( energy_now * 60 / power_now ))
    else
        remaining=$(( energy_full - energy_now ))
        total_mins=$(( remaining * 60 / power_now ))
    fi
    h=$(( total_mins / 60 ))
    m=$(( total_mins % 60 ))
    time=$(printf "%d:%02d" "$h" "$m")
fi

# ── Icon ──────────────────────────────────────────────────────────────────
charging=false
[[ "$status" == "Charging" || "$status" == "Full" ]] && charging=true

if $charging; then
    if   (( capacity >= 85 )); then icon="ABOVE85_CHG"
    elif (( capacity >= 70 )); then icon="HIGH_CHG"
    elif (( capacity >= 50 )); then icon="MED_CHG"
    elif (( capacity >= 40 )); then icon="HALF_CHG"
    elif (( capacity >= 20 )); then icon="BELOW_HALF_CHG"
    elif (( capacity >= 10 )); then icon="LOW_CHG"
    else                           icon="VERY_LOW_CHG"
    fi
else
    if   [[ "$status" == "Full" ]];  then icon="FULL"
    elif (( capacity >= 85 )); then icon="ABOVE85"
    elif (( capacity >= 70 )); then icon="HIGH"
    elif (( capacity >= 50 )); then icon="MED"
    elif (( capacity >= 40 )); then icon="HALF"
    elif (( capacity >= 20 )); then icon="BELOW_HALF"
    elif (( capacity >= 10 )); then icon="LOW"
    else                           icon="VERY_LOW"
    fi
fi

# ── Notifications (state-tracked across poll cycles) ──────────────────────
PREV_STATE=$(cat "$NOTIFY_FILE" 2>/dev/null || echo 'NONE')
PREV_CAP=$(cat "$CAP_FILE" 2>/dev/null || echo '0')
echo "$capacity" > "$CAP_FILE"

if [[ "$status" == "Charging" || "$status" == "Full" ]]; then
    rm -f /tmp/quickshell/battery_suspend_triggered
    if [[ "$capacity" -eq 100 && "$PREV_CAP" -lt 100 ]]; then
        notify-send 'Battery Full' 'Battery at 100% — Fully charged' &
        paplay ~/.config/sounds/battery-full.mp3 2>/dev/null &
        echo 'FULL' > "$NOTIFY_FILE"
    elif [[ "$capacity" -ge 80 && "$capacity" -lt 85 ]] && { [[ "$PREV_CAP" -lt 80 ]] || [[ "$PREV_STATE" != '80PCT' ]]; }; then
        notify-send 'Battery 80%' "Battery at ${capacity}% — Consider unplugging" &
        paplay ~/.config/sounds/battery-full.mp3 2>/dev/null &
        echo '80PCT' > "$NOTIFY_FILE"
    elif [[ "$PREV_STATE" != 'CHG' && "$PREV_STATE" != '80PCT' && "$PREV_STATE" != 'FULL' ]]; then
        # notify-send 'Battery Charging' "Battery at ${capacity}% — Charging started" &
        paplay ~/.config/sounds/charging.mp3 2>/dev/null &
        echo 'CHG' > "$NOTIFY_FILE"
    fi

    # Refresh energy_full cache when charging — it may recalibrate
    cat "$BAT/energy_full" > "$ENERGY_FULL_CACHE"
else
    [[ "$PREV_STATE" == 'CHG' || "$PREV_STATE" == '80PCT' || "$PREV_STATE" == 'FULL' ]] && echo 'NONE' > "$NOTIFY_FILE"
    if [[ "$capacity" -ge 10 && "$capacity" -lt 20 ]] && { [[ "$PREV_CAP" -ge 20 ]] || [[ "$PREV_STATE" != 'LOW' ]]; }; then
        notify-send -u critical 'Battery Low' "Battery at ${capacity}%" &
        paplay ~/.config/sounds/battery-low.mp3 2>/dev/null &
        echo 'LOW' > "$NOTIFY_FILE"
    elif [[ "$capacity" -le 9 ]]; then
        [[ ! -f /tmp/quickshell/battery_suspend_triggered ]] && bash ~/.config/hypr/battery-suspend.sh &
        if [[ "$PREV_CAP" -ge 10 || "$PREV_STATE" != 'CRIT' ]]; then
            notify-send -u critical 'Battery Critical' "Battery at ${capacity}% — Plug in NOW!" &
            paplay ~/.config/sounds/battery-critical.mp3 2>/dev/null &
            echo 'CRIT' > "$NOTIFY_FILE"
        fi
    fi
fi

power_watts=$(awk "BEGIN {printf \"%.1f\", $power_now / 1000000}")
printf '{"capacity":%d,"time":"%s","icon":"%s","status":"%s","power_watts":%s}\n' \
    "$capacity" "$time" "$icon" "${status,,}" "$power_watts"
