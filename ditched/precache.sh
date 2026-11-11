#!/usr/bin/env bash
# precache.sh
#
# Generic precache runner. Every expensive thing your shell would otherwise
# compute lazily (on Component.onCompleted, on popup open, etc.) gets
# registered here as a JOB. Jobs run in parallel at login, each is
# idempotent (checks its own cache before doing work), so re-running this
# script costs ~nothing once everything is warm.
#
# Add a job to the JOBS array below. That's the only edit needed to
# precache something new — no QML changes required as long as the
# consuming QML reads from the same cache path the job writes to.

set -uo pipefail

QS_DIR="$HOME/.config/quickshell"
STATE_DIR="$QS_DIR/state"
SCRIPTS_DIR="$QS_DIR/scripts"
LOG_FILE="$STATE_DIR/precache.log"
LOCK_DIR="$STATE_DIR/.precache.lock"

mkdir -p "$STATE_DIR"

log() {
    echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# JOBS: name | check_cmd | gen_cmd
#   check_cmd: shell snippet, exit 0 = cache valid, skip gen_cmd
#   gen_cmd:   shell snippet, runs only if check_cmd fails
# Both run via `bash -c`, so use full paths / $HOME, not relative paths.
# ---------------------------------------------------------------------------

declare -a JOB_NAMES=()
declare -a JOB_CHECKS=()
declare -a JOB_GENS=()

add_job() {
    JOB_NAMES+=("$1")
    JOB_CHECKS+=("$2")
    JOB_GENS+=("$3")
}

# Wallpaper: blur/thumb/palette per current wallpaper, keyed by content hash.
add_job "wallpaper" \
    'false' \
    "$SCRIPTS_DIR/wallpaper-precache.sh --all \$HOME/Downloads/WALLPAPERS"

# Screenshot hue ring: regenerate only if missing (static asset, changes
# only if gen_hue_ring.py itself changes).
add_job "hue-ring" \
    "[[ -f \$HOME/.config/quickshell/assets/hue_ring.png ]]" \
    "python3 $SCRIPTS_DIR/gen_hue_ring.py"

# Wallpaper grid thumbnails: reuse the existing generator script, just
# trigger it here instead of on first WallpaperGrid open.

add_job "wallpaper-thumbs" \
    'false' \
    "$SCRIPTS_DIR/wallpaper-thumbs.sh"
# --- add more jobs here ---
# add_job "name" "check_cmd" "gen_cmd"

# ---------------------------------------------------------------------------

run_job() {
    local name="$1" check="$2" gen="$3"
    if bash -c "$check" >/dev/null 2>&1; then
        log "hit:  $name"
        return
    fi
    log "miss: $name -> generating"
    if bash -c "$gen" >>"$LOG_FILE" 2>&1; then
        log "done: $name"
    else
        log "FAIL: $name (see log above)"
    fi
}

main() {
    exec 9>"$LOCK_DIR"
    flock -n 9 || { log "already running, exiting"; exit 0; }

    local pids=()
    for i in "${!JOB_NAMES[@]}"; do
        run_job "${JOB_NAMES[$i]}" "${JOB_CHECKS[$i]}" "${JOB_GENS[$i]}" &
        pids+=($!)
    done

    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    log "precache pass complete"
}

main "$@"
