#!/usr/bin/env bash
# stress-test-toasts.sh
# Usage: ./stress-test-toasts.sh [duplicates|distinct|mixed]

mode="${1:-mixed}"

case "$mode" in
  duplicates)
    # Same app+summary repeated fast - should coalesce into ONE toast with
    # a rising ×N count instead of spawning N separate cards.
    for i in $(seq 1 8); do
      notify-send -a "StressTest" "Build Status" "Compiling... ($i/8)"
      sleep 0.15
    done
    ;;

  distinct)
    # Different summaries - these can't merge, so this hits the leader-only
    # blur + sample-budget path instead (only rawDepth 0 ever blurs, samples
    # step down as count rises).
    for i in $(seq 1 6); do
      notify-send -a "StressTest" "Notification $i" "This is a distinct message #$i"
      sleep 0.1
    done
    ;;

  mixed)
    # Real-world-ish burst: some duplicates, some distinct, arriving close
    # together - exercises both paths at once.
    notify-send -a "Spotify" "Now Playing" "Track One"
    sleep 0.1
    notify-send -a "StressTest" "Sync" "File 1 uploaded"
    sleep 0.1
    notify-send -a "StressTest" "Sync" "File 2 uploaded"
    sleep 0.1
    notify-send -a "StressTest" "Sync" "File 3 uploaded"
    sleep 0.1
    notify-send -a "Discord" "New message" "Someone pinged you"
    sleep 0.1
    notify-send -a "StressTest" "Sync" "File 4 uploaded"
    sleep 0.1
    notify-send -a "Mail" "New email" "From: someone@example.com......blyaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaat"
    ;;

  *)
    echo "Usage: $0 [duplicates|distinct|mixed]"
    exit 1
    ;;
esac
