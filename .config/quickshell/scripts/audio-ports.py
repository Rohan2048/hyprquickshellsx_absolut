#!/usr/bin/env python3
"""
audio-ports.py — raw output-port enumeration for VolumePopup's settings page.

Why this exists:
  `pactl list sinks` only shows sinks that the *currently active card profile*
  exposes. An HDMI monitor, a dock, or an aux jack usually sits behind a
  profile that isn't active, so it never appears as a sink and never shows up
  in the normal device list. Cards, however, always advertise every port they
  have, along with the port's plug state and the profiles that expose it.
  This script reads that layer directly and can switch to a port on demand.

Scope:
  "ports"  — the overflow settings-page list: HDMI, DisplayPort, aux/headphone
             jacks, line out, S/PDIF, USB cards. Bluetooth cards are skipped
             entirely (already handled by the normal sink list, which updates
             correctly on connect/disconnect since that's real device add/
             remove, not a profile switch).
  "pinned" — built-in speaker ports. ALWAYS present in the JSON regardless of
             which profile is currently active, because switching an ALSA
             card's profile away from analog-stereo makes that sink vanish
             from `pactl list sinks` entirely — there's no way around that at
             the pactl level, so instead of trying to keep it "alive" as a
             sink, we keep it alive as a *pinned, always-clickable entry* the
             main page can always show and use to switch back.

Modes:
  list                 one-shot JSON on stdout
  listen               same JSON, re-emitted on pactl card/sink/server events
                       (trailing-debounced, duplicate payloads suppressed)
  set <card> <port>    activate a port: switch card profile if needed, set the
                       sink's active port, make it the default sink, and move
                       existing streams onto it
  debug                human-readable dump of what the parser sees

JSON shape:
  {
    "defaultSink": "alsa_output.pci-0000_00_1f.3.hdmi-stereo",
    "activeKey": "alsa_card.pci-0000_00_1f.3|hdmi-output-0",
    "ports":  [ {same entry shape as below} ... ],   // settings page
    "pinned": [ {same entry shape as below} ... ]    // main page, always-on
  }
  entry shape:
      {
        "key":       "<card name>|<port name>",   // stable id for QML
        "card":      "alsa_card.pci-0000_00_1f.3",
        "cardIndex": 42,
        "cardLabel": "Built-in Audio",
        "port":      "hdmi-output-0",
        "label":     "HDMI / DisplayPort",
        "type":      "HDMI",
        "avail":     "yes" | "unknown",           // "no" entries are dropped
        "present":   true,                        // active profile exposes it
        "active":    false,                       // it IS the default output
        "sink":      "alsa_output....hdmi-stereo",// "" when not present
        "sinkDesc":  "Built-in Audio Digital Stereo (HDMI)",
        "profiles":  ["output:hdmi-stereo", ...]
      }

A "ports" entry disappears from the JSON when its port reports "not
available" (unplugged) — no manual bookkeeping needed on the QML side.
A "pinned" entry never disappears; only its present/active/sink fields change.
"""

import json
import os
import re
import select
import subprocess
import sys
import time

ENV = {**os.environ, "LC_ALL": "C", "LANG": "C"}

# ── Card/port classification ─────────────────────────────────────────────
# Bluetooth cards are skipped entirely — already handled by the existing
# sink list, which updates correctly on connect/disconnect.
HIDE_CARD_PREFIXES = ("bluez_card.",)

# Built-in speaker ports go to "pinned" instead of "ports" (see module
# docstring) rather than being dropped.
PINNED_PORT_NAMES = {"analog-output-speaker", "analog-output-speaker-always"}

# Direction test. Deliberately name-based: a port's `type:` is unreliable
# ("Headset" is used for both directions on bluez cards), and its
# `Part of profile(s)` list is worse — input ports list *combined* profiles
# like "output:hdmi-stereo+input:analog-stereo" that begin with "output:".
INPUT_NAME_HINTS = ("input", "mic", "capture", "line-in", "linein")
OUTPUT_NAME_HINTS = ("output", "hdmi", "displayport", "speaker", "headphone",
                     "lineout", "line-out", "iec958", "spdif", "digital")
INPUT_TYPES = {"mic", "microphone"}

# "<name>: <description> (<meta>)" — used for both port and profile lines.
# `.*` is greedy on purpose so a description containing parentheses still
# binds the *last* parenthesised group as meta.
ENTRY_RE = re.compile(r"^(?P<name>\S+):\s+(?P<desc>.*)\((?P<meta>[^()]*)\)\s*$")


def pactl(*args):
    try:
        r = subprocess.run(["pactl", *args], capture_output=True, text=True, env=ENV)
        return r.stdout
    except FileNotFoundError:
        return ""


def indent_of(line):
    """pactl indents with tabs; some builds/locales use 4 spaces."""
    t = line.lstrip("\t")
    if len(line) != len(t):
        return len(line) - len(t)
    s = line.lstrip(" ")
    return (len(line) - len(s)) // 4


def _availability(meta):
    for tok in (t.strip().lower() for t in meta.split(",")):
        if tok == "not available":
            return "no"
        if tok == "available":
            return "yes"
        if tok == "availability unknown":
            return "unknown"
    return "unknown"


def _meta_field(meta, key):
    m = re.search(re.escape(key) + r":\s*([^,)]+)", meta)
    return m.group(1).strip() if m else ""


def card_stem(card_name):
    """
    'alsa_card.pci-0000_00_1f.3'        -> 'pci-0000_00_1f.3'
    'bluez_card.41_42_FF_28_65_C4'      -> '41_42_FF_28_65_C4'
    Used to pair a card with its sinks by name when the id route fails.
    """
    return card_name.split(".", 1)[1] if "." in card_name else card_name


# ─────────────────────────────── parsing ────────────────────────────────

def parse_cards():
    cards, cur, section = [], None, None

    for raw in pactl("list", "cards").splitlines():
        if not raw.strip():
            continue
        ind, s = indent_of(raw), raw.strip()

        if ind == 0:
            m = re.match(r"Card\s+#(\d+)", s)
            if m:
                cur = {
                    "index": int(m.group(1)),
                    "name": "",
                    "desc": "",
                    "activeProfile": "",
                    "profiles": {},
                    "ports": [],
                }
                cards.append(cur)
                section = None
            continue

        if cur is None:
            continue

        if ind == 1:
            key, _, val = s.partition(":")
            key, val = key.strip(), val.strip()
            section = None
            if key == "Name":
                cur["name"] = val
            elif key == "Active Profile":
                cur["activeProfile"] = val
            elif key == "Properties":
                section = "cardprops"
            elif key == "Profiles":
                section = "profiles"
            elif key == "Ports":
                section = "ports"
            continue

        if ind == 2:
            if section == "cardprops":
                k, _, v = s.partition("=")
                if k.strip() in ("device.description", "alsa.card_name") and not cur["desc"]:
                    cur["desc"] = v.strip().strip('"')
            elif section == "profiles":
                m = ENTRY_RE.match(s)
                if m:
                    meta = m.group("meta")
                    cur["profiles"][m.group("name").rstrip(":")] = {
                        "desc": m.group("desc").strip(),
                        "priority": int(_meta_field(meta, "priority") or 0),
                        "available": _meta_field(meta, "available").lower() != "no",
                    }
            elif section == "ports":
                m = ENTRY_RE.match(s)
                if m:
                    meta = m.group("meta")
                    cur["ports"].append({
                        "name": m.group("name").rstrip(":"),
                        "desc": m.group("desc").strip(),
                        "type": _meta_field(meta, "type"),
                        "priority": int(_meta_field(meta, "priority") or 0),
                        "avail": _availability(meta),
                        "profiles": [],
                    })
            continue

        if ind == 3 and section == "ports" and cur["ports"]:
            if s.startswith("Part of profile(s):"):
                lst = s.split(":", 1)[1]
                cur["ports"][-1]["profiles"] = [p.strip() for p in lst.split(",") if p.strip()]

    return cards


def parse_sinks():
    """
    PipeWire's pactl does NOT print a `Card:` line for sinks the way PulseAudio
    did — the owning card is only discoverable from the sink's Properties block
    (`device.id`, matching `Card #N`). We read that, and keep `alsa.card` as a
    secondary hint; build() falls back to name matching if both are missing.
    """
    sinks, cur, section = [], None, None

    for raw in pactl("list", "sinks").splitlines():
        if not raw.strip():
            continue
        ind, s = indent_of(raw), raw.strip()

        if ind == 0:
            if re.match(r"Sink\s+#(\d+)", s):
                cur = {"name": "", "desc": "", "card": -1, "alsaCard": -1,
                       "activePort": "", "ports": []}
                sinks.append(cur)
                section = None
            continue

        if cur is None:
            continue

        if ind == 1:
            key, _, val = s.partition(":")
            key, val = key.strip(), val.strip()
            section = None
            if key == "Name":
                cur["name"] = val
            elif key == "Description":
                cur["desc"] = val
            elif key == "Card":                       # PulseAudio only
                digits = re.sub(r"\D", "", val)
                cur["card"] = int(digits) if digits else -1
            elif key == "Active Port":
                cur["activePort"] = val.strip('"')
            elif key == "Ports":
                section = "ports"
            elif key == "Properties":
                section = "sinkprops"
            continue

        if ind >= 2 and section == "sinkprops":
            k, _, v = s.partition("=")
            k, v = k.strip(), v.strip().strip('"')
            if k == "device.id" and cur["card"] == -1 and v.isdigit():
                cur["card"] = int(v)
            elif k == "alsa.card" and v.isdigit():
                cur["alsaCard"] = int(v)
            continue

        if ind >= 2 and section == "ports":
            # tolerate both "name: Desc (meta)" and a bare "name: Desc"
            m = ENTRY_RE.match(s)
            pname = (m.group("name") if m else s.partition(":")[0]).strip().rstrip(":")
            if pname:
                cur["ports"].append(pname)
            continue

    return sinks


# ──────────────────────────────── model ─────────────────────────────────

def is_output_port(port):
    n = port["name"].lower()
    if any(h in n for h in INPUT_NAME_HINTS) and not any(h in n for h in ("output", "lineout")):
        return False
    if port["type"].lower() in INPUT_TYPES:
        return False
    if any(h in n for h in OUTPUT_NAME_HINTS):
        return True
    # last resort: belongs to a profile that is output-only
    return any(p.startswith("output:") and "+input:" not in p for p in port["profiles"])


def profile_parts(card):
    """Active profile as a set: the whole string plus each +-joined half."""
    ap = card["activeProfile"]
    parts = {ap}
    parts.update(p for p in ap.split("+") if p)
    return parts


def sinks_of_card(card, sinks):
    """id match first, then the sink-name-contains-card-stem fallback."""
    owned = [s for s in sinks if s["card"] == card["index"] and s["card"] != -1]
    if owned:
        return owned
    stem = card_stem(card["name"])
    return [s for s in sinks if stem and stem in s["name"]]

def _make_entry(c, p, card_sinks, active_profiles, default_sink):
    present = any(pf in active_profiles for pf in p["profiles"]) if p["profiles"] else False

    sink = next((s for s in card_sinks if p["name"] in s["ports"]), None)
    if sink is None:
        sink = next((s for s in card_sinks if s["activePort"] == p["name"]), None)

    if sink:
        port_is_active = (sink["activePort"] == p["name"]) if sink["activePort"] else (len(sink["ports"]) <= 1)
    else:
        port_is_active = False

    is_active = bool(present and sink and sink["name"] == default_sink and port_is_active)

    return {
        "key": c["name"] + "|" + p["name"],
        "card": c["name"],
        "cardIndex": c["index"],
        "cardLabel": c["desc"],
        "port": p["name"],
        "label": p["desc"] or p["name"],
        "type": p["type"],
        "avail": p["avail"],
        "present": present,
        "active": is_active,
        "sink": sink["name"] if sink else "",
        "sinkDesc": sink["desc"] if sink else "",
        "profiles": p["profiles"],
        "_priority": p["priority"],
    }, is_active

def build():
    cards = parse_cards()
    sinks = parse_sinks()
    default_sink = pactl("get-default-sink").strip()

    ports, pinned = [], []
    active_key = ""

    for c in cards:
        if c["name"].startswith(HIDE_CARD_PREFIXES):
            continue

        card_sinks = sinks_of_card(c, sinks)
        active_profiles = profile_parts(c)

        for p in c["ports"]:
            if p["avail"] == "no" or not is_output_port(p):
                continue

            entry, is_active = _make_entry(c, p, card_sinks, active_profiles, default_sink)
            if is_active:
                active_key = entry["key"]

            if p["name"] in PINNED_PORT_NAMES:
                pinned.append(entry)
            else:
                ports.append(entry)

    # plugged-in things first, then card order, then port priority
    ports.sort(key=lambda e: (e["avail"] != "yes", e["cardIndex"], -e["_priority"]))
    pinned.sort(key=lambda e: (e["cardIndex"], -e["_priority"]))
    for e in ports + pinned:
        del e["_priority"]

    return {"defaultSink": default_sink, "activeKey": active_key, "ports": ports, "pinned": pinned}


# ────────────────────────────── activation ──────────────────────────────

def choose_profile(card, port):
    """Best profile that exposes this port, preserving the current input half."""
    usable = [p for p in port["profiles"] if p in card["profiles"]]
    avail = [p for p in usable if card["profiles"][p]["available"]]
    cands = avail or usable
    if not cands:
        return ""

    # Prefer a pure output profile with the highest priority, then try to
    # re-attach whatever input half the card is currently using so switching
    # to HDMI doesn't silently kill the microphone.
    pure = [p for p in cands if "+input:" not in p] or cands
    pure.sort(key=lambda p: (-card["profiles"][p]["priority"], len(p)))
    best = pure[0]

    inputs = [p for p in card["activeProfile"].split("+") if p.startswith("input:")]
    if inputs and "+input:" not in best:
        combined = best + "+" + inputs[0]
        if combined in card["profiles"] and card["profiles"][combined]["available"]:
            return combined
    return best


def activate(card_name, port_name):
    cards = parse_cards()
    card = next((c for c in cards if c["name"] == card_name), None)
    if card is None:
        print("audio-ports: no such card: " + card_name, file=sys.stderr)
        return 1
    port = next((p for p in card["ports"] if p["name"] == port_name), None)
    if port is None:
        print("audio-ports: no such port: " + port_name, file=sys.stderr)
        return 1

    if not any(pf in profile_parts(card) for pf in port["profiles"]):
        prof = choose_profile(card, port)
        if prof:
            pactl("set-card-profile", card_name, prof)

    # the sink may take a moment to appear after a profile switch
    sink = None
    deadline = time.time() + 3.0
    while time.time() < deadline:
        on_card = sinks_of_card(card, parse_sinks())
        sink = next((s for s in on_card if port_name in s["ports"]), None)
        if sink is None and len(on_card) == 1:
            sink = on_card[0]
        if sink:
            break
        time.sleep(0.1)

    if sink is None:
        print("audio-ports: no sink exposes " + port_name, file=sys.stderr)
        return 1

    pactl("set-sink-port", sink["name"], port_name)
    pactl("set-default-sink", sink["name"])

    # drag anything already playing over to the new output
    for line in pactl("list", "short", "sink-inputs").splitlines():
        sid = line.split("\t")[0].strip()
        if sid.isdigit():
            pactl("move-sink-input", sid, sink["name"])

    return 0


# ─────────────────────────────── entry point ────────────────────────────

def emit():
    sys.stdout.write(json.dumps(build(), separators=(",", ":")) + "\n")
    sys.stdout.flush()


def listen():
    emit()
    proc = subprocess.Popen(["pactl", "subscribe"], stdout=subprocess.PIPE,
                            text=True, env=ENV)
    last = None
    pending = False
    interesting = re.compile(r"\b(card|sink|server)\b")

    while True:
        timeout = 0.2 if pending else None
        r, _, _ = select.select([proc.stdout], [], [], timeout)
        if r:
            line = proc.stdout.readline()
            if not line:
                break
            if interesting.search(line):
                pending = True
        else:
            pending = False
            payload = json.dumps(build(), separators=(",", ":"))
            if payload != last:          # suppress no-op churn
                last = payload
                sys.stdout.write(payload + "\n")
                sys.stdout.flush()


def debug():
    cards = parse_cards()
    sinks = parse_sinks()
    for c in cards:
        hidden = c["name"].startswith(HIDE_CARD_PREFIXES)
        print("Card #%d  %s  (%s)%s" % (c["index"], c["name"], c["desc"],
                                         "  [CARD HIDDEN]" if hidden else ""))
        print("  active profile: " + c["activeProfile"])
        print("  sinks matched : " + (", ".join(s["name"] for s in sinks_of_card(c, sinks)) or "(none)"))
        for p in c["ports"]:
            flags = []
            if not is_output_port(p):
                flags.append("INPUT")
            if p["name"] in PINNED_PORT_NAMES:
                flags.append("PINNED")
            if p["avail"] == "no":
                flags.append("UNPLUGGED")
            print("    %-28s %-26s avail=%-7s type=%-10s %s"
                  % (p["name"], p["desc"], p["avail"], p["type"],
                     ("[" + ",".join(flags) + "]") if flags else "[SHOWN]"))
    print()
    for s in sinks:
        print("Sink card=%-4s alsa=%-3s %-52s activePort=%-26s ports=%s"
              % (s["card"], s["alsaCard"], s["name"], s["activePort"],
                 ",".join(s["ports"]) or "(none parsed)"))
    print()
    print("default sink: " + pactl("get-default-sink").strip())


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "list"
    if mode == "list":
        emit()
    elif mode == "listen":
        try:
            listen()
        except KeyboardInterrupt:
            pass
    elif mode == "set":
        sys.exit(activate(sys.argv[2], sys.argv[3]))
    elif mode == "debug":
        debug()
    else:
        print(__doc__)
        sys.exit(2)
