#!/usr/bin/env python3
"""
sound-devices.py -- Settings > Sounds. Stdlib only; talks to PipeWire/PulseAudio through pactl.

  list                                  JSON: every output (sink) and input (source) with its card's profiles
  set-profile <card> <profile>          pactl set-card-profile
  set-port <sink|source> <name> <port>  pactl set-sink-port / set-source-port
  set-default <sink|source> <name>      pactl set-default-sink / -source   (moves playing streams too)
  volume <sink|source> <name> <pct>...  one value = all channels, N values = per channel (left, right, ...)
  mute <sink|source> <name> <0|1|toggle>
  combine on <sink>...                  play to several outputs at once (module-combine-sink named qs_combined)
  combine off                           stop combining; sound goes back to where it was before combining
  delay <ms>                            delay of the WIRED outputs, -10..500 ms, inside the combined output
  restore                               re-create the combined output saved in ~/.config/quickshell/state/sound-combine.txt
  sync-loop                             (started by `combine on`) keeps the Bluetooth outputs in step

Delays inside the combined output (nothing outside it is touched):
  * Wired outputs (speakers, headphone jack, HDMI, USB ...) are all delayed by the slider value, together.
    A negative delay cannot exist without delaying everything else, so every delayed output carries
    DELAY_BASE_MS of buffer: real delay = slider + 10 ms (slider -10 = no buffer, +500 = 510 ms).
  * Bluetooth outputs do NOT follow the slider. With two or more of them, each one is held back by
    (slowest Bluetooth latency - its own latency), so they all arrive together with the slowest one.
    The latencies are measured again every SYNC_EVERY seconds, because Bluetooth links drift, and a delay is
    corrected live whenever it is off by SYNC_STEP_MS or more.
Each delayed output goes through a small PipeWire filter-chain (one `pipewire -c` process, one hidden sink
"qs_delay_<n>" per output) that holds the sound back and plays it on the real device.
"""
import json
import os
import re
import signal
import subprocess
import sys
import time

ENV = dict(os.environ, LC_ALL="C", LANG="C")
STATE = os.path.join(os.environ.get("HOME", "."), ".config/quickshell/state/sound-combine.txt")
STATE_DIR = os.path.dirname(STATE)
PREV = os.path.join(STATE_DIR, "sound-combine-prev.txt")      # the output sound came from before combining
DELAY_FILE = os.path.join(STATE_DIR, "sound-delay.txt")       # slider value in ms (wired outputs)
DELAY_CONF = os.path.join(STATE_DIR, "qs-speaker-delay.conf")
DELAY_MAP = os.path.join(STATE_DIR, "sound-delay-map.json")   # [{node, target, kind, s}]: what is delayed, by how much
BT_STATUS = os.path.join(STATE_DIR, "sound-bt-sync.json")     # what the sync loop measured (shown in Settings)
COMB = "qs_combined"
DELAY_PREFIX = "qs_delay_"
OLD_MONO = "qs_mono."      # leftovers of the removed Mono mode
DELAY_MIN, DELAY_MAX, DELAY_BASE_MS = -10, 500, 10
DELAY_BUFFER_S = 0.6       # filter-chain buffer: bigger than (DELAY_MAX + DELAY_BASE_MS) / 1000
SYNC_EVERY = 10            # seconds between Bluetooth latency checks
SYNC_STEP_MS = 15          # only correct a Bluetooth delay when it is off by at least this much (no clicks)


def pactl(*args, js=False):
    cmd = ["pactl"] + (["-f", "json"] if js else []) + list(args)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, env=ENV)
    except FileNotFoundError:
        return None if js else ""
    if js:
        try:
            return json.loads(r.stdout or "[]")
        except ValueError:
            return []
    return r.stdout


def pct_of(v):
    p = v.get("value_percent")
    if isinstance(p, str) and p.strip().endswith("%"):
        try:
            return int(p.strip()[:-1])
        except ValueError:
            pass
    return int(round(v.get("value", 0) * 100 / 65536))


def channels_of(dev):
    vol = dev.get("volume") or {}
    order = [c for c in (dev.get("channel_map") or "").split(",") if c]
    names = [c for c in order if c in vol] or list(vol.keys())
    return [{"ch": c, "pct": pct_of(vol[c])} for c in names]


def avail(p):
    a = (p.get("availability") or "").lower()
    if "not" in a:
        return "no"
    if a == "available":
        return "yes"
    return "unknown"


def kind_of(dev, card, active_port):
    props = dev.get("properties") or {}
    blob = " ".join([dev.get("name", ""), props.get("device.api", ""), props.get("device.bus", ""),
                     props.get("device.form_factor", ""), active_port or ""]).lower()
    if "bluez" in blob or "bluetooth" in blob:
        return "bluetooth"
    if "hdmi" in blob or "displayport" in blob:
        return "hdmi"
    if "usb" in blob:
        return "usb"
    if "headphone" in blob or "headset" in blob:
        return "headphones"
    if "speaker" in blob or "internal" in blob:
        return "speaker"
    if "lineout" in blob or "line-out" in blob or "linein" in blob or "line-in" in blob:
        return "line"
    if "mic" in blob:
        return "mic"
    return "audio"


def card_of(dev, cards):
    props = dev.get("properties") or {}
    did = props.get("device.id")
    for c in cards:
        if did is not None and str(c.get("index")) == str(did):
            return c
    name = dev.get("name", "")
    for c in cards:
        cn = c.get("name", "")
        stem = cn.split(".", 1)[1] if "." in cn else cn
        if stem and stem in name:
            return c
    return None


def profiles_of(card):
    if not card:
        return []
    out = []
    for n, p in (card.get("profiles") or {}).items():
        if n == "off":
            continue
        out.append({"name": n, "desc": p.get("description", n), "avail": p.get("available", True) is not False,
                    "prio": p.get("priority", 0)})
    out.sort(key=lambda p: (not p["avail"], -p["prio"]))
    for p in out:
        del p["prio"]
    return out


def entry(dev, cards, default):
    card = card_of(dev, cards)
    ports = [{"name": p.get("name", ""), "desc": p.get("description", p.get("name", "")), "avail": avail(p)}
             for p in (dev.get("ports") or [])]
    ap = dev.get("active_port") or ""
    return {
        "name": dev.get("name", ""),
        "desc": dev.get("description", dev.get("name", "")),
        "kind": kind_of(dev, card, ap),
        "card": card.get("name", "") if card else "",
        "cardDesc": ((card.get("properties") or {}).get("device.description", "") if card else ""),
        "activeProfile": card.get("active_profile", "") if card else "",
        "profiles": profiles_of(card),
        "ports": ports,
        "activePort": ap,
        "channels": channels_of(dev),
        "muted": bool(dev.get("mute")),
        "isDefault": dev.get("name") == default,
        "state": dev.get("state", ""),
    }


def drop_old_mono(sinks):
    """Mono mode is gone: unload any qs_mono.* sinks an earlier version left behind."""
    old = [x["name"] for x in sinks if x.get("name", "").startswith(OLD_MONO)]
    if not old:
        return False
    dflt = pactl("get-default-sink").strip()
    for n in old:
        master = n[len(OLD_MONO):]
        if dflt == n:
            pactl("set-default-sink", master)
            move_streams(n, master)
        for line in pactl("list", "short", "modules").splitlines():
            f = line.split("\t")
            if len(f) > 2 and f[1] == "module-remap-sink" and ("sink_name=" + n) in f[2]:
                pactl("unload-module", f[0])
    remove(os.path.join(STATE_DIR, "sound-mono.txt"))
    return True


def hidden(name):
    return name == COMB or name.startswith(DELAY_PREFIX) or name.startswith(OLD_MONO)


def is_bt(dev):
    props = dev.get("properties") or {}
    return dev.get("name", "").startswith("bluez_output.") or "bluez" in props.get("device.api", "").lower()


def do_list():
    sinks = pactl("list", "sinks", js=True)
    if sinks and drop_old_mono(sinks):
        sinks = pactl("list", "sinks", js=True)
    sources = pactl("list", "sources", js=True)
    cards = pactl("list", "cards", js=True)
    if sinks is None:
        print(json.dumps({"error": "pactl not found", "outputs": [], "inputs": []}))
        return 0
    dsink = pactl("get-default-sink").strip()
    dsrc = pactl("get-default-source").strip()
    comb = next((x for x in sinks if x.get("name") == COMB), None)
    real = [x for x in sinks if not hidden(x.get("name", ""))]
    outs = [entry(x, cards, dsink) for x in real]
    ins = [entry(x, cards, dsrc) for x in sources
           if not x.get("monitor_of_sink") and not x.get("name", "").endswith(".monitor")]
    combined = {"active": comb is not None, "isDefault": dsink == COMB, "members": read_state(),
                "channels": channels_of(comb) if comb else [], "muted": bool(comb and comb.get("mute"))}
    wired = [x for x in real if not is_bt(x)]
    bt = read_json(BT_STATUS, {}).get("devices", []) if comb is not None else []
    delay = {"available": len(wired) > 0, "wired": len(wired), "ms": read_delay(),
             "running": any(x.get("name", "").startswith(DELAY_PREFIX) for x in sinks), "bt": bt}
    print(json.dumps({"outputs": outs, "inputs": ins, "combined": combined, "delay": delay,
                      "defaultSink": dsink, "defaultSource": dsrc}))
    return 0


# ───────────────────────────── actions ──────────────────────────────

def move_streams(src, dst):
    for line in pactl("list", "short", "sink-inputs").splitlines():
        f = line.split("\t")
        if len(f) > 1 and f[1] == src_index(src):
            pactl("move-sink-input", f[0], dst)


def src_index(sink_name):
    for line in pactl("list", "short", "sinks").splitlines():
        f = line.split("\t")
        if len(f) > 1 and f[1] == sink_name:
            return f[0]
    return ""


def read_lines(path):
    try:
        with open(path) as fh:
            return [l.strip() for l in fh if l.strip()]
    except OSError:
        return []


def read_json(path, default):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def write_json(path, data):
    os.makedirs(STATE_DIR, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh)
    os.replace(tmp, path)


def remove(path):
    try:
        os.remove(path)
    except OSError:
        pass


def read_state():
    return read_lines(STATE)


def write_state(names):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(STATE, "w") as fh:
        fh.write("\n".join(sorted(set(names))) + ("\n" if names else ""))


# ── finding and unloading the combined output ──

def sink_names():
    return {x.get("name") for x in (pactl("list", "sinks", js=True) or [])}


def combine_module_ids():
    """Every loaded module-combine-sink that belongs to qs_combined. PipeWire does not always print the
    arguments the way we gave them, so look at three things: the sink's owner module, the module arguments
    (with or without quotes), and -- if nothing else matches -- the only combine module there is."""
    mods = {}
    for line in pactl("list", "short", "modules").splitlines():
        f = line.split("\t")
        if len(f) > 1 and f[1] == "module-combine-sink":
            mods[f[0]] = f[2] if len(f) > 2 else ""
    found = []
    for s in (pactl("list", "sinks", js=True) or []):
        if s.get("name") == COMB:
            om = str(s.get("owner_module"))
            if om in mods:
                found.append(om)
    for mid, args in mods.items():
        if re.search(r"sink_name=[\"']?" + re.escape(COMB) + r"([\"'\s]|$)", args) and mid not in found:
            found.append(mid)
    if not found and COMB in sink_names() and len(mods) == 1:
        found = list(mods)
    return found


def unload_combine():
    for _ in range(3):
        ids = combine_module_ids()
        if not ids:
            break
        for mid in ids:
            pactl("unload-module", mid)
        for _ in range(10):                      # wait until the sink is really gone
            if COMB not in sink_names():
                return True
            time.sleep(0.05)
    return COMB not in sink_names()


# ── delays ──

def clamp_delay(ms):
    return max(DELAY_MIN, min(DELAY_MAX, int(round(ms))))


def read_delay():
    try:
        return clamp_delay(float(read_lines(DELAY_FILE)[0]))
    except (IndexError, ValueError):
        return 0


def wired_delay_s(ms):
    return max(0, ms + DELAY_BASE_MS) / 1000.0


def proc_pids(needle):
    me = os.getpid()
    out = []
    for d in os.listdir("/proc"):
        if not d.isdigit() or int(d) == me:
            continue
        try:
            with open("/proc/%s/cmdline" % d, "rb") as fh:
                cmd = fh.read().decode(errors="ignore").replace("\0", " ")
        except OSError:
            continue
        if needle in cmd:
            out.append(int(d))
    return out


def kill_all(needle):
    for pid in proc_pids(needle):
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass


def stop_delay_chain():
    kill_all(DELAY_CONF)
    for _ in range(20):
        if not proc_pids(DELAY_CONF) and not any(n.startswith(DELAY_PREFIX) for n in sink_names()):
            break
        time.sleep(0.05)
    remove(DELAY_MAP)


def stop_sync():
    kill_all("sound-devices.py sync-loop")
    remove(BT_STATUS)


def delay_conf(targets):
    """targets: [(real sink name, delay in seconds)] -> one filter-chain module per output."""
    node = """
                    {
                        type    = builtin
                        name    = %s
                        label   = delay
                        config  = { "max-delay" = %.2f }
                        control = { "Delay (s)" = %.4f }
                    }"""
    mods = ""
    for i, (target, secs) in enumerate(targets):
        mods += """    { name = libpipewire-module-filter-chain
        args = {
            node.description = "Delayed output %d"
            media.name       = "Delayed output %d"
            filter.graph = {
                nodes = [%s%s
                ]
                inputs  = [ "dl:In" "dr:In" ]
                outputs = [ "dl:Out" "dr:Out" ]
            }
            capture.props = {
                node.name      = "%s%d"
                media.class    = "Audio/Sink"
                audio.position = [ FL FR ]
            }
            playback.props = {
                node.name         = "%s%d_out"
                audio.position    = [ FL FR ]
                target.object     = "%s"
                stream.dont-remix = true
                node.passive      = true
            }
        }
    }
""" % (i, i, node % ("dl", DELAY_BUFFER_S, secs), node % ("dr", DELAY_BUFFER_S, secs),
       DELAY_PREFIX, i, DELAY_PREFIX, i, target)
    return """# generated by sound-devices.py -- delays single outputs inside the combined output
context.properties = {
    log.level = 0
}

context.spa-libs = {
    audio.convert.* = audioconvert/libspa-audioconvert
    support.*       = support/libspa-support
}

context.modules = [
    { name = libpipewire-module-rt
        args = { }
        flags = [ ifexists nofail ]
    }
    { name = libpipewire-module-protocol-native }
    { name = libpipewire-module-client-node }
    { name = libpipewire-module-adapter }
%s]
""" % mods


def start_delay_chain(plan):
    """plan: [{target, kind, s}] -> starts the chain; returns {real sink: hidden sink} (empty on failure)."""
    stop_delay_chain()
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(DELAY_CONF, "w") as fh:
        fh.write(delay_conf([(p["target"], p["s"]) for p in plan]))
    try:
        subprocess.Popen(["pipewire", "-c", DELAY_CONF], env=ENV, stdin=subprocess.DEVNULL,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return {}
    want = ["%s%d" % (DELAY_PREFIX, i) for i in range(len(plan))]
    for _ in range(60):                          # up to 6 s for the hidden sinks to show up
        time.sleep(0.1)
        if all(n in sink_names() for n in want):
            write_json(DELAY_MAP, [dict(p, node=want[i]) for i, p in enumerate(plan)])
            return {p["target"]: want[i] for i, p in enumerate(plan)}
    stop_delay_chain()
    return {}


def node_ids():
    """PipeWire node.name -> node id (pw-dump)."""
    out = {}
    try:
        r = subprocess.run(["pw-dump"], capture_output=True, text=True, env=ENV)
        for o in json.loads(r.stdout or "[]"):
            props = (o.get("info") or {}).get("props") or {}
            if o.get("type") == "PipeWire:Interface:Node" and props.get("node.name"):
                out[props["node.name"]] = o.get("id")
    except (OSError, ValueError):
        pass
    return out


def push_delays(changes):
    """changes: [(hidden sink name, seconds)] -> live parameter change on the running chain."""
    if not changes:
        return
    ids = node_ids()
    for node, secs in changes:
        nid = ids.get(node)
        if nid is None:
            continue
        d = "%.4f" % secs
        params = '{ params = [ "dl:Delay (s)" %s "dr:Delay (s)" %s ] }' % (d, d)
        subprocess.run(["pw-cli", "s", str(nid), "Props", params], capture_output=True, text=True, env=ENV)


def set_delay(ms):
    """The slider: every wired output inside the combined output, together. Bluetooth is left to the sync loop."""
    ms = clamp_delay(ms)
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(DELAY_FILE, "w") as fh:
        fh.write(str(ms) + "\n")
    m = read_json(DELAY_MAP, [])
    secs = wired_delay_s(ms)
    wired = [e for e in m if e.get("kind") == "wired"]
    if wired:
        push_delays([(e["node"], secs) for e in wired])
        for e in wired:
            e["s"] = secs
        write_json(DELAY_MAP, m)
    return 0


# ── Bluetooth latency ──

def bt_delay_report_ms(sink):
    """The speaker's own reported playback delay (AVDTP delay reporting, via BlueZ), if it reports one."""
    m = re.search(r"bluez_output\.([0-9A-Fa-f_]{17})", sink)
    if not m:
        return None
    dev = "dev_" + m.group(1).upper()
    try:
        r = subprocess.run(["busctl", "--system", "--json=short", "call", "org.bluez", "/",
                            "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"],
                           capture_output=True, text=True, env=ENV, timeout=5)
        objs = json.loads(r.stdout)["data"][0]
    except (OSError, ValueError, KeyError, IndexError, subprocess.SubprocessError):
        return None
    best = None
    for path, ifaces in objs.items():
        t = ifaces.get("org.bluez.MediaTransport1")
        if dev in path and t and "Delay" in t:
            v = t["Delay"].get("data")
            if isinstance(v, (int, float)):
                best = v / 10.0                  # BlueZ reports 1/10 ms
    return best


def bt_latency_ms(sink, sinks):
    """Best estimate of how late this Bluetooth output plays: the speaker's own delay report when it gives
    one, plus what PipeWire says is queued in the sink right now."""
    queued = 0.0
    for s in sinks:
        if s.get("name") == sink:
            lat = s.get("latency")
            if isinstance(lat, dict):
                lat = lat.get("actual", lat.get("current", 0))
            if isinstance(lat, (int, float)):
                queued = lat / 1000.0            # usec -> ms
    return (bt_delay_report_ms(sink) or 0.0) + queued


def plan_for(sinks, members, lat):
    """What gets a delay chain, and how long each is held back (seconds)."""
    by = {s.get("name"): s for s in sinks}
    wired = [m for m in members if m in by and not is_bt(by[m])]
    bts = [m for m in members if m in by and is_bt(by[m])]
    plan = [{"target": w, "kind": "wired", "s": wired_delay_s(read_delay())} for w in wired]
    if len(bts) >= 2:
        slowest = max(lat.get(b, 0.0) for b in bts)
        for b in bts:
            plan.append({"target": b, "kind": "bt", "s": (DELAY_BASE_MS + slowest - lat.get(b, 0.0)) / 1000.0})
    return plan


def sync_loop():
    """Runs while the combined output exists: re-measures the Bluetooth latencies and corrects the delays."""
    ema = {}
    while True:
        sinks = pactl("list", "sinks", js=True) or []
        if COMB not in {s.get("name") for s in sinks}:
            break
        m = read_json(DELAY_MAP, [])
        bts = [e for e in m if e.get("kind") == "bt"]
        changes, devices = [], []
        if bts:
            for e in bts:
                now = bt_latency_ms(e["target"], sinks)
                ema[e["target"]] = now if e["target"] not in ema else 0.6 * ema[e["target"]] + 0.4 * now
            slowest = max(ema[e["target"]] for e in bts)
            for e in bts:
                want = (DELAY_BASE_MS + slowest - ema[e["target"]]) / 1000.0
                if abs(want - e.get("s", 0.0)) * 1000.0 >= SYNC_STEP_MS:
                    changes.append((e["node"], want))
                    e["s"] = want
                devices.append({"name": e["target"], "latencyMs": int(round(ema[e["target"]])),
                                "delayMs": int(round(e["s"] * 1000 - DELAY_BASE_MS))})
        wired_s = wired_delay_s(read_delay())
        for e in m:
            if e.get("kind") == "wired" and abs(e.get("s", 0.0) - wired_s) > 0.0005:
                changes.append((e["node"], wired_s))
                e["s"] = wired_s
        if changes:
            push_delays(changes)
            write_json(DELAY_MAP, m)
        write_json(BT_STATUS, {"devices": devices})
        time.sleep(SYNC_EVERY)
    remove(BT_STATUS)
    return 0


# ── combine on / off ──

def combine_on(members):
    sinks = pactl("list", "sinks", js=True) or []
    have = {x.get("name") for x in sinks}
    members = [m for m in members if m in have and not hidden(m)]
    if len(members) < 2:
        print("sound-devices: pick at least two outputs", file=sys.stderr)
        return 1
    old = pactl("get-default-sink").strip()
    if old and old != COMB and not hidden(old):
        os.makedirs(STATE_DIR, exist_ok=True)
        with open(PREV, "w") as fh:
            fh.write(old + "\n")
    unload_combine()
    stop_sync()
    stop_delay_chain()

    by = {s.get("name"): s for s in sinks}
    lat = {m: bt_latency_ms(m, sinks) for m in members if is_bt(by[m])}
    plan = plan_for(sinks, members, lat)
    slave_of = {}
    if plan:
        slave_of = start_delay_chain(plan)
        if not slave_of:
            print("sound-devices: output delay unavailable, combining without it", file=sys.stderr)
    slaves = [slave_of.get(m, m) for m in members]

    out = pactl("load-module", "module-combine-sink", "sink_name=" + COMB,
                "slaves=" + ",".join(slaves), "sink_properties=device.description=Combined-output").strip()
    if not out.isdigit():
        stop_delay_chain()
        print("sound-devices: could not combine the outputs", file=sys.stderr)
        return 1
    pactl("set-default-sink", COMB)
    if old and old != COMB:
        move_streams(old, COMB)
    write_state(members)
    if slave_of and any(p["kind"] == "bt" for p in plan):
        subprocess.Popen([sys.executable, os.path.abspath(__file__), "sync-loop"], env=ENV,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    return 0


def combine_off():
    members = read_state()
    have = sink_names()
    prev = (read_lines(PREV) or [""])[0]
    back = prev if prev in have and not hidden(prev) else next((m for m in members if m in have and not hidden(m)), "")
    if not back:
        back = next((n for n in have if n and not hidden(n)), "")
    if pactl("get-default-sink").strip() == COMB and back:
        pactl("set-default-sink", back)
        move_streams(COMB, back)
    stop_sync()
    unload_combine()
    stop_delay_chain()
    remove(STATE)
    remove(PREV)
    return 0


def main(a):
    if not a:
        return 2
    cmd = a[0]
    if cmd == "list":
        return do_list()
    if cmd == "set-profile" and len(a) >= 3:
        pactl("set-card-profile", a[1], a[2])
    elif cmd == "set-port" and len(a) >= 4:
        pactl("set-%s-port" % a[1], a[2], a[3])
    elif cmd == "set-default" and len(a) >= 3:
        name = a[2]
        old = pactl("get-default-sink").strip() if a[1] == "sink" else ""
        pactl("set-default-" + a[1], name)
        if a[1] == "sink" and old and old != name:
            move_streams(old, name)
        elif a[1] == "source":
            for line in pactl("list", "short", "source-outputs").splitlines():
                f = line.split("\t")
                if f:
                    pactl("move-source-output", f[0], name)
    elif cmd == "volume" and len(a) >= 4:
        vals = [v.rstrip("%") + "%" for v in a[3:]]
        pactl("set-%s-volume" % a[1], a[2], *vals)
    elif cmd == "mute" and len(a) >= 4:
        pactl("set-%s-mute" % a[1], a[2], a[3])
    elif cmd == "combine" and len(a) >= 2:
        if a[1] == "on":
            return combine_on(a[2:])
        return combine_off()
    elif cmd == "delay" and len(a) >= 2:
        try:
            return set_delay(float(a[1]))
        except ValueError:
            return 2
    elif cmd == "sync-loop":
        return sync_loop()
    elif cmd == "restore":
        if read_state() and COMB not in sink_names():
            combine_on(read_state())
    else:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
