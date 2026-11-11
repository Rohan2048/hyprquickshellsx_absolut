#!/usr/bin/env bash
#tweaks.sh
set -euo pipefail

CONF=/etc/systemd/logind.conf
CHANGED=0

set_conf() {
    local key="$1" value="$2" file="$3"

    if grep -qE "^\s*${key}\s*=\s*${value}\s*$" "$file"; then
        echo "OK: ${key}=${value} already set"
    elif grep -qE "^\s*#?\s*${key}\s*=" "$file"; then
        sudo sed -i -E "s|^\s*#?\s*${key}\s*=.*|${key}=${value}|" "$file"
        echo "UPDATED: ${key}=${value}"
        CHANGED=1
    else
        echo "${key}=${value}" | sudo tee -a "$file" > /dev/null
        echo "APPENDED: ${key}=${value}"
        CHANGED=1
    fi
}

set_conf "HandleLidSwitch" "suspend" "$CONF"
set_conf "HandleLidSwitchExternalPower" "suspend" "$CONF"
set_conf "HandlePowerKey" "ignore" "$CONF"

if [[ "$CHANGED" -eq 1 ]]; then
    # reload, not restart — sends SIGHUP via ExecReload, re-reads config
    # in place without tearing down the daemon or touching active sessions
    sudo systemctl reload systemd-logind
    echo "logind config reloaded"
else
    echo "no changes — logind left untouched"
fi
