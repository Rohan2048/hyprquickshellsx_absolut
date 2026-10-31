#!/usr/bin/env bash

# ~/.config/hypr/preload.sh
# Quickshell Architectural Warmup (NO UI TOGGLING)
#
# PURPOSE:
# This script explicitly AVOIDS opening/closing popups.
# "Open/close" preloading is a cheap tactic that inflates idle RSS,
# forces unnecessary object creation/destruction, and violates
# the requirement for minimal memory overhead.
#
# True transient optimization is achieved via:
# 1. QML Loader { asynchronous: true }
# 2. Binding { when: root.visible }
# 3. Offloading animations to Hyprland layer rules.
#
# This script only performs safe, non-UI environment checks.

set -e

# 1. Ensure Quickshell directories exist (prevents first-run mkdir stutter)
mkdir -p ~/.cache/quickshell
mkdir -p ~/.config/quickshell/.qmlcache

# 2. Wait for the 'qs' CLI to be responsive (indicates core daemon is ready)
# We do NOT interact with UI components here.
timeout 15 bash -c 'until qs list 2>/dev/null | grep -q "^Instance"; do sleep 0.5; done' || true

# 3. Optional: Pre-warm system-level caches that QML might use later.
# This does not touch Quickshell's object tree.
# Example: Touch fontconfig cache to ensure first font render is fast
fc-cache -f -s >/dev/null 2>&1 || true

# 4. Explicitly exit. No UI components are instantiated.
# The transient spikes will be eliminated by the QML changes
# (asynchronous loading + deferred bindings) described in the optimization plan.
exit 0
