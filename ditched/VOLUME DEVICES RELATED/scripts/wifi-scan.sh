#!/bin/bash

# wifi-scan.sh
# Usage: wifi-scan.sh scan       — rescan and print raw device list
#        wifi-scan.sh connect    — (later)

case "$1" in
  scan)
    nmcli dev wifi rescan 2>/dev/null
    sleep 1
    nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null | grep -v '^:'
    ;;
  *)
    echo "Usage: $0 scan"
    exit 1
    ;;
esac
