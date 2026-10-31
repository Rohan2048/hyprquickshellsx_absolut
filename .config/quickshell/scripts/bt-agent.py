#!/usr/bin/env python3
import sys, json, threading, queue, os, signal, subprocess
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

BUS_NAME = 'org.bluez'
AGENT_PATH = "/quickshell/agent"
AGENT_IFACE = 'org.bluez.Agent1'

HOME = os.path.expanduser("~")
HIST_SCRIPT = os.path.join(HOME, ".config/quickshell/scripts/bt-history.sh")
PIDFILE = os.path.join(HOME, ".config/quickshell/state/bt-history.pid")

_reply_q = queue.Queue()
_current_pair = {"mac": "", "name": ""}

def emit(obj):
    print(json.dumps(obj), flush=True)

def refresh_history(mac, name):
    """Write the just-paired device into history and kick the monitor to
    re-emit immediately, instead of waiting on a D-Bus PropertiesChanged
    signal that may not arrive in time (or at all) on this process. Mirrors
    the pattern forget_device() already uses in bt-history.sh.
    Runs in a worker thread (not on the GLib main loop) so it's free to
    block until the write actually finishes — the update MUST complete
    before the SIGUSR1 kick, or the monitor re-emits the old file."""
    def worker():
        try:
            subprocess.run(["bash", HIST_SCRIPT, "update", name, mac], check=False,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            emit({"type": "debug", "message": "refresh_history update failed: " + str(e)})
            return
        try:
            with open(PIDFILE) as f:
                pid = int(f.read().strip())
            os.kill(pid, signal.SIGUSR1)
        except Exception as e:
            emit({"type": "debug", "message": "refresh_history SIGUSR1 failed: " + str(e)})
    threading.Thread(target=worker, daemon=True).start()

class Rejected(dbus.DBusException):
    _dbus_error_name = "org.bluez.Error.Rejected"

def device_info(bus, path):
    """Resolve a BlueZ device object path to (mac, display_name).
    Needed for incoming pairing requests, which only ever hand us the
    D-Bus object path - never the mac/name our QML side already tracks
    for outgoing (self-initiated) pairs via startPair()."""
    try:
        props = dbus.Interface(bus.get_object(BUS_NAME, path), "org.freedesktop.DBus.Properties")
        all_props = props.GetAll("org.bluez.Device1")
        mac = str(all_props.get("Address", ""))
        name = str(all_props.get("Alias", all_props.get("Name", mac or path)))
        return mac, name
    except Exception:
        return "", str(path)

class Agent(dbus.service.Object):
    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Release(self):
        pass

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def RequestConfirmation(self, device, passkey):
        mac, name = device_info(self.connection, device)
        emit({"type": "confirm", "mac": mac, "name": name, "passkey": "%06d" % passkey})
        ans = _reply_q.get()
        if ans != "yes":
            raise Rejected("rejected by user")

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="s")
    def RequestPinCode(self, device):
        mac, name = device_info(self.connection, device)
        emit({"type": "pin", "mac": mac, "name": name})
        return _reply_q.get()

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="u")
    def RequestPasskey(self, device):
        mac, name = device_info(self.connection, device)
        emit({"type": "pin", "mac": mac, "name": name})
        return dbus.UInt32(int(_reply_q.get()))

    @dbus.service.method(AGENT_IFACE, in_signature="o", out_signature="")
    def RequestAuthorization(self, device):
        mac, name = device_info(self.connection, device)
        emit({"type": "confirm", "mac": mac, "name": name, "passkey": ""})
        ans = _reply_q.get()
        if ans != "yes":
            raise Rejected("rejected by user")

    @dbus.service.method(AGENT_IFACE, in_signature="os", out_signature="")
    def AuthorizeService(self, device, uuid):
        mac, name = device_info(self.connection, device)
        emit({"type": "confirm", "mac": mac, "name": name, "passkey": ""})
        ans = _reply_q.get()
        if ans != "yes":
            raise Rejected("rejected by user")

    @dbus.service.method(AGENT_IFACE, in_signature="", out_signature="")
    def Cancel(self):
        emit({"type": "cancel", "mac": _current_pair["mac"], "name": _current_pair["name"]})

def find_device_path(bus, mac):
    om = dbus.Interface(bus.get_object(BUS_NAME, "/"), "org.freedesktop.DBus.ObjectManager")
    target = mac.upper().replace(":", "_")
    for path, ifaces in om.GetManagedObjects().items():
        if "org.bluez.Device1" in ifaces and path.endswith(target):
            return path
    return None

def do_pair(bus, mac, name):
    _current_pair["mac"] = mac
    _current_pair["name"] = name
    path = find_device_path(bus, mac)
    if not path:
        emit({"type": "error", "mac": mac, "name": name, "message": "device not found: " + name})
        return
    dev = dbus.Interface(bus.get_object(BUS_NAME, path), "org.bluez.Device1")
    props = dbus.Interface(bus.get_object(BUS_NAME, path), "org.freedesktop.DBus.Properties")

    def current_alias(fallback):
        """BlueZ's Alias defaults to the mac formatted with dashes when it
        doesn't have a real name yet — often still true the instant Pair()
        succeeds. Re-reading it live (here, and again after Connect())
        catches the real name once BlueZ has actually resolved it, instead
        of permanently saving whatever placeholder we captured at scan time."""
        try:
            alias = props.Get("org.bluez.Device1", "Alias")
            return str(alias).rstrip() if alias else fallback
        except Exception:
            return fallback

    def ok():
        emit({"type": "paired", "mac": mac, "name": name})
        # Write history + kick the monitor right away, synchronously with
        # the pairing succeeding — don't wait on a Connected PropertiesChanged
        # signal that may arrive late or not at all on this process.
        refresh_history(mac, current_alias(name))
        try:
            props.Set("org.bluez.Device1", "Trusted", True)
        except Exception:
            pass

        def connected():
            emit({"type": "connected", "mac": mac, "name": current_alias(name)})
            # Alias frequently only resolves to the real name once the
            # profile connection completes, seconds after Pair() — refresh
            # again so the saved entry doesn't keep the placeholder forever.
            refresh_history(mac, current_alias(name))

        dev.Connect(reply_handler=connected,
                    error_handler=lambda e: emit({"type": "error", "mac": mac, "name": name, "message": str(e)}))

    def err(e):
        emit({"type": "error", "mac": mac, "name": name, "message": str(e)})

    dev.Pair(reply_handler=ok, error_handler=err)

def stdin_loop(bus):
    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        parts = line.split(" ", 2)
        cmd = parts[0]
        if cmd in ("yes", "no"):
            _reply_q.put(cmd)
        elif cmd == "pin" and len(parts) >= 2:
            _reply_q.put(parts[1])
        elif cmd == "pair" and len(parts) >= 3:
            GLib.idle_add(do_pair, bus, parts[1], parts[2])

def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    Agent(bus, AGENT_PATH)
    manager = dbus.Interface(bus.get_object(BUS_NAME, "/org/bluez"), "org.bluez.AgentManager1")
    manager.RegisterAgent(AGENT_PATH, "KeyboardDisplay")
    manager.RequestDefaultAgent(AGENT_PATH)
    emit({"type": "ready"})

    threading.Thread(target=stdin_loop, args=(bus,), daemon=True).start()
    GLib.MainLoop().run()

if __name__ == "__main__":
    main()
