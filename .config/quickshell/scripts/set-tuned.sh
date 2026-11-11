#!/usr/bin/env bash
# set-tuned.sh <profile>
# Sets tuned-adm profile and writes a trigger file that
# Services/Battery.qml is tail -f-ing to pick up the change live.

PROFILE="$1"
[ -z "$PROFILE" ] && exit 1

mkdir -p /tmp/quickshell

# Apply tuned profile
sudo tuned-adm profile "$PROFILE"

# Update cache and wake deflisten
echo "$PROFILE" > /tmp/quickshell/tuned_profile
echo "$PROFILE" >> /tmp/quickshell/tuned_profile_trigger
