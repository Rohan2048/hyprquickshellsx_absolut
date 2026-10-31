#!/usr/bin/env bash
# notif-listener.sh — emits NOTIF_LIST JSON
#
# The original approach here dbus-monitor'd for dunst's "Notify" call as a
# *signal*. That never actually worked: Notify is a method call a client
# sends TO dunst (unicast), not a broadcast signal, so a `type='signal'`
# filter can never see it — that match was dead code. Only
# NotificationClosed (a real signal, fired when something *closes*) ever
# matched, which is why a brand-new notification didn't show up until it
# later timed out or got dismissed.
#
# Simple, reliable fix: just poll `dunstctl history` every 1.5s. It's cheap,
# and there's no dbus method-call-vs-signal subtlety left to get wrong.

emit() {
    bash ~/.config/quickshell/scripts/notif-history.sh
}

while true; do
    emit
    sleep 1.5
done
