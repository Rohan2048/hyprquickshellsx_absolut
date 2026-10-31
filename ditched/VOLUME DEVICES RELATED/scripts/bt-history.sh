#!/bin/bash
# bt-history.sh — MAC-keyed storage. Names are just display labels; every
# lookup, dedup, and action (connect/disconnect/forget) matches on MAC only.
# Two devices sharing a name (or one name being a substring of another)
# used to be able to resolve to the wrong MAC via `bluetoothctl devices |
# grep -F name` — that's gone. get_mac_from_name below survives only to
# migrate old name-only history entries, once, on first read.

HIST="$HOME/.config/quickshell/state/bt-history.json"
PIDFILE="$HOME/.config/quickshell/state/bt-history.pid"
mkdir -p "$(dirname "$HIST")"

if [ ! -f "$HIST" ] || ! python3 -c "import json; json.load(open('$HIST'))" 2>/dev/null; then
    echo '[]' > "$HIST"
fi

normalize() {
    echo "$1" | sed 's/ *$//'
}

get_mac_from_name() {
    bluetoothctl devices | awk -v n="$1" -F' ' '{
        mac=$2; $1=""; $2=""; sub(/^  */, "");
        if ($0 == n) { print mac; exit }
    }'
}

migrate_and_load() {
    python3 - "$HIST" << 'PY'
import json, sys, subprocess, re

path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = []

def resolve_mac(name):
    try:
        out = subprocess.check_output(['bluetoothctl', 'devices'], text=True)
    except Exception:
        return None
    for line in out.splitlines():
        m = re.match(r'Device ([0-9A-F:]{17}) (.+)', line.strip())
        if m and m.group(2).rstrip() == name:
            return m.group(1)
    return None

out = []
changed = False
seen_macs = set()
for entry in data:
    if isinstance(entry, str):
        name, mac = entry, None
    elif isinstance(entry, dict):
        name, mac = entry.get('name', ''), entry.get('mac')
    else:
        continue
    if not name:
        continue
    if not mac:
        mac = resolve_mac(name)
        changed = True
    if not mac or mac in seen_macs:
        continue
    seen_macs.add(mac)
    out.append({"mac": mac, "name": name})

if changed:
    with open(path, 'w') as f:
        json.dump(out, f)

print(json.dumps(out))
PY
}

list_devices() {
    migrate_and_load
}

update_device() {
    NAME="$1"; MAC="$2"
    [ -z "$NAME" ] && return
    [ -z "$MAC" ] && return
    NAME=$(normalize "$NAME")
    python3 - "$HIST" "$NAME" "$MAC" << 'PY'
import json, sys
path, name, mac = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
    if not (isinstance(data, list) and (not data or (isinstance(data[0], dict) and 'mac' in data[0]))):
        data = []
except Exception:
    data = []
data = [d for d in data if d.get('mac') != mac]
data.insert(0, {"mac": mac, "name": name})
with open(path, 'w') as f:
    json.dump(data, f)
PY
}

remove_from_history() {
    MAC="$1"
    [ -z "$MAC" ] && return
    python3 - "$HIST" "$MAC" << 'PY'
import json, sys
path, mac = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = []
data = [d for d in data if isinstance(d, dict) and d.get('mac') != mac]
with open(path, 'w') as f:
    json.dump(data, f)
PY
}

connect_device() {
    MAC="$1"
    [ -n "$MAC" ] && bluetoothctl connect "$MAC" &>/dev/null &
}

disconnect_device() {
    MAC="$1"
    [ -n "$MAC" ] && bluetoothctl disconnect "$MAC" &>/dev/null &
}

forget_device() {
    MAC="$1"
    [ -z "$MAC" ] && return
    # NOTE: deliberately NOT spawning `bluetoothctl remove` here. bt-scan-listener.sh
    # keeps its own persistent interactive bluetoothctl session open over a FIFO
    # whenever live mode is on; bluetoothctl doesn't support multiple concurrent
    # instances cleanly, and a second one-shot instance issuing a command can
    # disturb the first instance's state — including dropping unrelated
    # connections. Talk to BlueZ directly over D-Bus instead, same as bt-agent.py
    # already does for pairing, so this can't collide with the scan listener.
    python3 - "$MAC" << 'PY'
import sys, dbus

mac = sys.argv[1]
bus = dbus.SystemBus()
om = dbus.Interface(bus.get_object('org.bluez', '/'), 'org.freedesktop.DBus.ObjectManager')
target = mac.upper().replace(':', '_')

device_path = None
for path, ifaces in om.GetManagedObjects().items():
    if 'org.bluez.Device1' in ifaces and path.endswith(target):
        device_path = path
        break

if device_path:
    adapter_path = device_path.rsplit('/', 1)[0]
    try:
        adapter = dbus.Interface(bus.get_object('org.bluez', adapter_path), 'org.bluez.Adapter1')
        adapter.RemoveDevice(device_path)
    except Exception as e:
        print(e, file=sys.stderr)
PY
    remove_from_history "$MAC"
    if [ -f "$PIDFILE" ]; then
        kill -USR1 "$(cat "$PIDFILE")" 2>/dev/null
    fi
}

case "$1" in
    list)       list_devices;             exit ;;
    update)     update_device "$2" "$3";  exit ;;
    connect)    connect_device "$2";      exit ;;
    disconnect) disconnect_device "$2";   exit ;;
    forget)     forget_device "$2";       exit ;;
esac

# --------------------------
# MONITOR — D-Bus subscriber
# Emits {"device":"...","deviceMac":"...","history":[...],"connectedMacs":[...]}
# to stdout on startup and on every connection change. "device" stays a
# name/state string (bar display + Bluetooth-OFF/ON sentinels); "deviceMac"
# is the primary connected device's MAC; "connectedMacs" lists every
# currently connected device so multiple simultaneous connections can be
# shown/highlighted at once.
# Requires: python3-dbus (python3-dbus package)
# --------------------------

echo $$ > "$PIDFILE"

exec python3 - "$HIST" << 'PY'
import sys, json, signal, re, subprocess, dbus, dbus.mainloop.glib
from gi.repository import GLib

HIST = sys.argv[1]

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()

def get_connected_device():
    """Fallback only: returns (mac, name) for *some* connected device, or
    (None, 'Bluetooth-ON'/'Bluetooth-OFF'). Not reliable for picking out a
    specific device when more than one is connected simultaneously — use
    get_device_by_path() when the signal already tells you which one."""
    try:
        mgr = dbus.Interface(
            bus.get_object('org.bluez', '/'),
            'org.freedesktop.DBus.ObjectManager'
        )
        for path, ifaces in mgr.GetManagedObjects().items():
            dev = ifaces.get('org.bluez.Device1', {})
            if dev.get('Connected') and dev.get('Name'):
                mac = str(dev.get('Address', '')) or None
                return mac, str(dev['Name']).rstrip()
    except Exception:
        pass
    try:
        out = subprocess.check_output(['rfkill', 'list', 'bluetooth'], text=True)
        if 'Soft blocked: no' in out:
            return None, 'Bluetooth-ON'
    except Exception:
        pass
    return None, 'Bluetooth-OFF'

def get_all_connected():
    """All currently connected device MACs, not just one — a full
    ObjectManager scan so simultaneous connections (e.g. mouse + earbuds)
    are all counted, not just whichever get_connected_device() happens to
    find first."""
    result = []
    try:
        mgr = dbus.Interface(
            bus.get_object('org.bluez', '/'),
            'org.freedesktop.DBus.ObjectManager'
        )
        for path, ifaces in mgr.GetManagedObjects().items():
            dev = ifaces.get('org.bluez.Device1', {})
            if dev.get('Connected'):
                mac = str(dev.get('Address', '')) or None
                if mac:
                    result.append(mac)
    except Exception:
        pass
    return result

def get_device_by_path(path):
    """Reads mac/name straight off the object path the D-Bus signal gave
    us, so a Connected-property change always resolves to the device that
    actually changed — not whichever device a full rescan finds first."""
    try:
        props = dbus.Interface(bus.get_object('org.bluez', path), 'org.freedesktop.DBus.Properties')
        dev = props.GetAll('org.bluez.Device1')
        mac = str(dev.get('Address', '')) or None
        raw_name = dev.get('Alias') or dev.get('Name')
        name = str(raw_name).rstrip() if raw_name else None
        return mac, name
    except Exception:
        return None, None

def resolve_mac(name):
    try:
        out = subprocess.check_output(['bluetoothctl', 'devices'], text=True)
    except Exception:
        return None
    for line in out.splitlines():
        m = re.match(r'Device ([0-9A-F:]{17}) (.+)', line.strip())
        if m and m.group(2).rstrip() == name:
            return m.group(1)
    return None

def load_history():
    try:
        with open(HIST) as f:
            data = json.load(f)
        out = []
        for d in data:
            if isinstance(d, dict) and d.get('mac') and d.get('name'):
                out.append({"mac": d['mac'], "name": d['name']})
        return out
    except Exception:
        return []

def update_history(mac, name):
    if not mac or not name or name in ('Bluetooth-OFF', 'Bluetooth-ON'):
        return
    data = load_history()
    data = [d for d in data if d.get('mac') != mac]
    data.insert(0, {"mac": mac, "name": name})
    with open(HIST, 'w') as f:
        json.dump(data, f)

def emit(mac, name):
    print(json.dumps({
        "device": name,
        "deviceMac": mac or "",
        "history": load_history(),
        "connectedMacs": get_all_connected()
    }), flush=True)

# Last known (mac, name) as determined by an *authoritative* source: the
# real Connected PropertiesChanged signal, or the initial startup scan.
# SIGUSR1 (fired after a pairing update or a forget) must never recompute
# this itself — get_connected_device() only returns *some* connected
# device, and if two things are connected at once, a kick firing at the
# wrong moment can silently steal the highlight from the device that's
# actually correct. SIGUSR1 exists to say "the history file changed, please
# re-read it" — not "please re-guess who's connected".
_last_mac = None
_last_name = 'Bluetooth-OFF'

def on_properties_changed(interface, changed, invalidated, path=None):
    global _last_mac, _last_name
    if interface == 'org.bluez.Adapter1' and 'Powered' in changed:
        if changed['Powered']:
            mac, name = get_connected_device()
            _last_mac, _last_name = mac, name
            emit(mac, name)
        else:
            _last_mac, _last_name = None, 'Bluetooth-OFF'
            emit(None, 'Bluetooth-OFF')
        return
    if interface == 'org.bluez.Device1' and 'Connected' in changed:
        if changed['Connected']:
            # This exact device just connected — read it by its own path
            # instead of rescanning, so a second already-connected device
            # (mouse, headphones, etc.) can't steal the highlight.
            mac, name = get_device_by_path(path) if path else (None, None)
            if not mac or not name:
                mac, name = get_connected_device()
        else:
            # This device disconnected; see if anything else is still up.
            mac, name = get_connected_device()
        if mac is None and name and name not in ('Bluetooth-OFF', 'Bluetooth-ON'):
            mac = resolve_mac(name)
        update_history(mac, name)
        _last_mac, _last_name = mac, name
        emit(mac, name)

def on_sigusr1():
    # Re-read history from disk and re-emit it, but never touch the
    # connected-device highlight — replay whatever the real signal handler
    # last determined, verbatim.
    emit(_last_mac, _last_name)
    return GLib.SOURCE_CONTINUE

GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGUSR1, on_sigusr1)

mac, name = get_connected_device()
if mac is None and name not in ('Bluetooth-OFF', 'Bluetooth-ON'):
    mac = resolve_mac(name)
update_history(mac, name)
_last_mac, _last_name = mac, name
emit(mac, name)

bus.add_signal_receiver(
    on_properties_changed,
    signal_name='PropertiesChanged',
    dbus_interface='org.freedesktop.DBus.Properties',
    bus_name=None,
    path_keyword='path'
)

GLib.MainLoop().run()
PY
