#!/usr/bin/env python3
"""
battery-info.py -- Settings > Battery. Stdlib only, reads /sys/class/power_supply directly.

  info             JSON: percentage, status, power (W), energy (Wh), design capacity, health, cycles,
                   manufacturer, model, voltage, time left and the charge-limit capability of this laptop
  sample           log one sample (battery %, watts, status) and update the daily totals; also re-applies the
                   saved charge limit if the firmware forgot it (some laptops do after suspend). Run every ~2 min.
  history          JSON: the last 24 h of samples + a summary (used / charged Wh, average and peak draw) and
                   the last 30 days (energy used, health, cycle count)
  limit on|off     stop charging above 80 % (on) or charge to 100 % (off) and remember the choice

Files (~/.config/quickshell/state/):
  battery-history.jsonl   one sample per line, the last 48 h
  battery-daily.json      per-day totals, the last 60 days
  battery-limit.json      the charge-limit choice made in Settings

Charge limit: the kernel exposes it as  charge_control_end_threshold  (ThinkPad, ASUS, Framework, System76,
Huawei, LG, Samsung, Tuxedo ... -- Intel or AMD, it does not depend on the CPU) or, on Lenovo IdeaPad / Legion,
as  conservation_mode.  If neither file exists the laptop only offers it in the BIOS / vendor tool.
Writing needs root, so it goes through `sudo -n tee <file>` (same idea as set-governor.sh). `info` prints the
exact sudoers line to add when that is not set up yet.

For testing: QS_BATTERY_SYSFS=<dir> replaces /sys/class/power_supply, QS_STATE_DIR=<dir> the state folder.
"""
import glob
import getpass
import json
import os
import shutil
import subprocess
import sys
import time

PS = os.environ.get("QS_BATTERY_SYSFS", "/sys/class/power_supply")
STATE_DIR = os.environ.get("QS_STATE_DIR", os.path.join(os.environ.get("HOME", "."), ".config/quickshell/state"))
HIST = os.path.join(STATE_DIR, "battery-history.jsonl")
DAILY = os.path.join(STATE_DIR, "battery-daily.json")
LIMIT = os.path.join(STATE_DIR, "battery-limit.json")
KEEP_SAMPLES_S = 48 * 3600
KEEP_DAYS = 60
GAP_S = 900                 # a hole in the samples longer than this is not counted as use
LIMIT_PCT = 80

STATUS_CODE = {"charging": "c", "discharging": "d", "full": "f", "not charging": "n"}


# ───────────────────────────── sysfs helpers ──────────────────────────────

def rd(path):
    try:
        with open(path) as fh:
            return fh.read().strip()
    except (OSError, ValueError):
        return None


def num(path):
    v = rd(path)
    try:
        return float(v) if v is not None else None
    except ValueError:
        return None


def battery_dir():
    """The laptop's own battery. Mains adapters and the batteries of wireless mice / keyboards / headsets
    (type Battery but scope Device) do not count; a desktop has none, so this returns None."""
    forced = os.environ.get("QS_BATTERY")
    if forced:
        return os.path.join(PS, forced)
    try:
        names = sorted(os.listdir(PS))
    except OSError:
        return None
    cands = []
    for n in names:
        d = os.path.join(PS, n)
        kind = rd(os.path.join(d, "type")) or ("Battery" if n.startswith("BAT") else "")
        if kind != "Battery":
            continue
        if (rd(os.path.join(d, "scope")) or "System").lower() == "device":
            continue
        cands.append(d)
    pref = [d for d in cands if os.path.basename(d).startswith("BAT")]
    return (pref or cands or [None])[0]


def state_dir():
    os.makedirs(STATE_DIR, exist_ok=True)
    return STATE_DIR


def read_json(path, default):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return default


def write_json(path, data):
    state_dir()
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh)
    os.replace(tmp, path)


# ───────────────────────────── battery reading ──────────────────────────────

def read_battery(bat):
    """Everything the page and the logger need, in Wh / W / V."""
    g = lambda n: os.path.join(bat, n)
    vnow = num(g("voltage_now"))
    vmin = num(g("voltage_min_design")) or vnow
    v = (vnow or 0) / 1e6
    vref = (vmin or 0) / 1e6

    def energy(name_e, name_c):
        e = num(g(name_e))
        if e is not None:
            return e / 1e6
        c = num(g(name_c))                       # µAh -> Wh with the design voltage
        if c is not None and vref:
            return c / 1e6 * vref
        return None

    now = energy("energy_now", "charge_now")
    full = energy("energy_full", "charge_full")
    design = energy("energy_full_design", "charge_full_design")

    p = num(g("power_now"))
    if p is not None:
        watts = abs(p) / 1e6
    else:
        i = num(g("current_now"))
        watts = abs(i) / 1e6 * v if (i is not None and v) else 0.0

    status = (rd(g("status")) or "Unknown")
    pct = num(g("capacity"))
    if pct is None and now is not None and full:
        pct = now / full * 100
    health = round(full / design * 100, 1) if (full and design) else None
    cycles = num(g("cycle_count"))

    left = None                                  # minutes
    if watts > 0.5 and now is not None:
        if status.lower() == "discharging":
            left = int(now / watts * 60)
        elif status.lower() == "charging" and full:
            left = int(max(0.0, full - now) / watts * 60)

    return {
        "path": bat,
        "name": os.path.basename(bat),
        "percent": int(round(pct)) if pct is not None else None,
        "status": status,
        "code": STATUS_CODE.get(status.lower(), "u"),
        "watts": round(watts, 2),
        "voltage": round(v, 2) if v else None,
        "energyNow": round(now, 2) if now is not None else None,
        "energyFull": round(full, 2) if full is not None else None,
        "energyDesign": round(design, 2) if design is not None else None,
        "health": health,
        "cycles": int(cycles) if cycles is not None else None,
        "manufacturer": rd(g("manufacturer")),
        "model": rd(g("model_name")),
        "technology": rd(g("technology")),
        "minutesLeft": left,
    }


# ───────────────────────────── charge limit ──────────────────────────────

def limit_paths(bat):
    out = []
    for name in ("charge_control_end_threshold", "charge_stop_threshold"):
        p = os.path.join(bat, name)
        if os.path.exists(p):
            out.append(("threshold", p))
    for p in sorted(glob.glob("/sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode")):
        out.append(("conservation", p))
    return out


def limit_info(bat):
    paths = limit_paths(bat) if bat else []
    saved = read_json(LIMIT, {})
    info = {"supported": False, "kind": "", "path": "", "value": None, "on": False,
            "target": LIMIT_PCT, "saved": saved.get("on"), "error": saved.get("error", ""), "sudoers": ""}
    if not paths:
        return info
    kind, path = paths[0]
    v = num(path)
    info.update(supported=True, kind=kind, path=path, value=int(v) if v is not None else None)
    if v is not None:
        info["on"] = (v >= 1) if kind == "conservation" else (v < 100)
    tee = shutil.which("tee") or "/usr/bin/tee"
    info["sudoers"] = "%s ALL=(root) NOPASSWD: %s %s" % (getpass.getuser(), tee, path)
    return info


def write_sysfs(path, value):
    """Write a sysfs file: directly if we may, otherwise through passwordless sudo."""
    try:
        with open(path, "w") as fh:
            fh.write(str(value))
        return ""
    except OSError:
        pass
    tee = shutil.which("tee") or "/usr/bin/tee"
    try:
        r = subprocess.run(["sudo", "-n", tee, path], input=str(value) + "\n", capture_output=True, text=True,
                           timeout=15)
    except (OSError, subprocess.SubprocessError) as e:
        return str(e)
    if r.returncode != 0:
        return (r.stderr or "").strip().splitlines()[-1] if (r.stderr or "").strip() else "sudo failed"
    return ""


def set_limit(on, remember=True):
    bat = battery_dir()
    info = limit_info(bat)
    if not info["supported"]:
        return {"ok": False, "error": "This laptop does not expose a charge limit to Linux."}
    if info["kind"] == "conservation":
        value = 1 if on else 0
    else:
        value = LIMIT_PCT if on else 100
    err = write_sysfs(info["path"], value)
    after = num(info["path"])
    ok = err == "" and after is not None and int(after) == value
    if err == "" and not ok:
        err = "The laptop did not accept the value (it reads %s)." % (int(after) if after is not None else "nothing")
    if "password" in err.lower() or "a terminal is required" in err.lower():
        err = "Needs passwordless sudo for this one file."
    if remember:
        write_json(LIMIT, {"on": bool(on), "error": "" if ok else err})
    return {"ok": ok, "error": "" if ok else err}


def reapply_limit():
    """Some laptops forget the threshold after suspend / a BIOS update: put it back (quietly)."""
    saved = read_json(LIMIT, None)
    if not isinstance(saved, dict) or "on" not in saved:
        return
    info = limit_info(battery_dir())
    if info["supported"] and info["value"] is not None and info["on"] != bool(saved["on"]):
        set_limit(bool(saved["on"]))


# ───────────────────────────── history ──────────────────────────────

def read_samples():
    out = []
    try:
        with open(HIST) as fh:
            for line in fh:
                try:
                    s = json.loads(line)
                    if isinstance(s, dict) and "t" in s:
                        out.append(s)
                except ValueError:
                    pass
    except OSError:
        pass
    return out


def day_of(ts):
    return time.strftime("%Y-%m-%d", time.localtime(ts))


def do_sample():
    bat = battery_dir()
    if not bat:
        return 0
    b = read_battery(bat)
    if b["percent"] is None:
        return 0
    now = int(time.time())
    samples = read_samples()
    prev = samples[-1] if samples else None
    samples.append({"t": now, "p": b["percent"], "w": b["watts"], "s": b["code"]})
    samples = [s for s in samples if s["t"] >= now - KEEP_SAMPLES_S]
    state_dir()
    tmp = HIST + ".tmp"
    with open(tmp, "w") as fh:
        for s in samples:
            fh.write(json.dumps(s, separators=(",", ":")) + "\n")
    os.replace(tmp, HIST)

    # daily totals
    d = read_json(DAILY, {})
    days = d.get("days", {}) if isinstance(d, dict) else {}
    today = days.setdefault(day_of(now), {"used_wh": 0.0, "charged_wh": 0.0})
    if prev and 0 < now - prev["t"] <= GAP_S:
        wh = prev["w"] * (now - prev["t"]) / 3600.0
        if prev["s"] == "d":
            today["used_wh"] = round(today.get("used_wh", 0.0) + wh, 3)
        elif prev["s"] == "c":
            today["charged_wh"] = round(today.get("charged_wh", 0.0) + wh, 3)
    if b["cycles"] is not None:
        today["cycles"] = b["cycles"]
    if b["health"] is not None:
        today["health"] = b["health"]
    if b["energyFull"] is not None:
        today["full_wh"] = b["energyFull"]
    keep = sorted(days)[-KEEP_DAYS:]
    write_json(DAILY, {"days": {k: days[k] for k in keep}})

    reapply_limit()
    return 0


def summarize(points):
    used = charged = 0.0
    dis_s = 0.0
    peak = 0.0
    for a, b in zip(points, points[1:]):
        dt = b["t"] - a["t"]
        if dt <= 0 or dt > GAP_S:
            continue
        wh = a["w"] * dt / 3600.0
        if a["s"] == "d":
            used += wh
            dis_s += dt
            peak = max(peak, a["w"])
        elif a["s"] == "c":
            charged += wh
    avg = used / (dis_s / 3600.0) if dis_s > 0 else 0.0
    return {"usedWh": round(used, 2), "chargedWh": round(charged, 2), "avgW": round(avg, 1),
            "peakW": round(peak, 1), "samples": len(points)}


def do_history():
    now = int(time.time())
    pts = [s for s in read_samples() if s["t"] >= now - 24 * 3600]
    d = read_json(DAILY, {})
    days = d.get("days", {}) if isinstance(d, dict) else {}
    daily = [dict(date=k, **days[k]) for k in sorted(days)[-30:]]
    daily.reverse()                                          # newest first
    print(json.dumps({"now": now, "points": pts, "summary": summarize(pts), "daily": daily},
                     separators=(",", ":")))
    return 0


def do_info():
    bat = battery_dir()
    if not bat:
        print(json.dumps({"present": False}))
        return 0
    b = read_battery(bat)
    b["present"] = True
    b["limit"] = limit_info(bat)
    print(json.dumps(b))
    return 0


def main(a):
    if not a:
        return 2
    if a[0] == "info":
        return do_info()
    if a[0] == "sample":
        return do_sample()
    if a[0] == "history":
        return do_history()
    if a[0] == "limit" and len(a) >= 2 and a[1] in ("on", "off"):
        print(json.dumps(set_limit(a[1] == "on")))
        return 0
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
