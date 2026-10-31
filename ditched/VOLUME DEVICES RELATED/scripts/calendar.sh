#!/usr/bin/env python3
# calendar.sh — fast cached calendar JSON for QuickShell
#
# Unchanged from the eww version except for one thing: the "wake up, I
# finished a background sync" signal file now lives under
# ~/.cache/quickshell/cal_trigger instead of /tmp/eww/cal_trigger. QuickShell
# watches that file directly with FileView { watchChanges: true }, so nothing
# needs to inotifywait on it anymore — this script just needs to touch it.
#
# Invocation is identical to before:
#   calendar.sh                 -> current month, cached if fresh
#   calendar.sh <year> <month>  -> that month, cached if fresh
#   calendar.sh --refresh       -> force a synchronous vdirsyncer sync + rebuild

import sys, json, subprocess, calendar, os, time
from datetime import date, datetime

try:
    import holidays as hol_lib
    HAS_HOLIDAYS = True
except ImportError:
    HAS_HOLIDAYS = False

CACHE_FILE    = os.path.expanduser("~/.cache/quickshell/cal_cache.json")
TRIGGER_FILE  = os.path.expanduser("~/.cache/quickshell/cal_trigger")
CACHE_MAX_AGE = 3600
today         = date.today()

# ── holidays — built once, covers both years in one shot ──────────────────
def get_holiday_map():
    if not HAS_HOLIDAYS:
        return {}
    hm = {}
    try:
        for yr in (today.year, today.year + 1):
            for d, name in hol_lib.country_holidays('IN', years=yr).items():
                hm[(d.year, d.month, d.day)] = name
    except Exception:
        pass
    return hm

# ── khal — single subprocess call, parse all events at once ───────────────
def get_event_map():
    em = {}
    try:
        end_year  = today.year + (2 if today.month > 6 else 1)
        end_month = (today.month + 17) % 12 or 12
        end_day   = calendar.monthrange(end_year, end_month)[1]
        r = subprocess.run(
            ['khal', 'list', '--format', '{start-date}|{title}',
             today.strftime('%d/%m/%Y'),
             date(end_year, end_month, end_day).strftime('%d/%m/%Y')],
            capture_output=True, text=True, timeout=5
        )
        for line in r.stdout.splitlines():
            if '|' not in line:
                continue
            ds, _, title = line.strip().partition('|')
            try:
                d = datetime.strptime(ds.strip(), '%d/%m/%Y').date()
                em.setdefault((d.year, d.month, d.day), []).append(title.strip())
            except ValueError:
                pass
    except Exception:
        pass
    return em

# ── month builder ──────────────────────────────────────────────────────────
FILLER = {"date":0,"weekday":0,"today":False,"has_event":False,
          "has_holiday":False,"holiday_name":"","events":[],"filler":True}

def build_month(year, month, holiday_map, event_map):
    flat = []
    for week in calendar.monthcalendar(year, month):
        for day in week:
            if day == 0:
                flat.append(FILLER)
            else:
                d   = date(year, month, day)
                key = (year, month, day)
                flat.append({
                    "date":         day,
                    "weekday":      d.weekday(),
                    "today":        d == today,
                    "has_event":    key in event_map,
                    "has_holiday":  key in holiday_map,
                    "holiday_name": holiday_map.get(key, ""),
                    "events":       event_map.get(key, []),
                    "filler":       False
                })
    while len(flat) < 42:
        flat.append(FILLER)
    prev = {"year": year-1, "month": 12} if month == 1 else {"year": year, "month": month-1}
    nxt  = {"year": year+1, "month": 1}  if month == 12 else {"year": year, "month": month+1}
    return {
        "year": year, "month": month,
        "month_name": calendar.month_name[month],
        "today_day":  today.day if (today.year == year and today.month == month) else -1,
        "week0": flat[0:7],  "week1": flat[7:14],
        "week2": flat[14:21],"week3": flat[21:28],
        "week4": flat[28:35],"week5": flat[35:42],
        "prev": prev, "next": nxt,
    }

def build_cache():
    hm = get_holiday_map()
    em = get_event_map()
    cache = {}
    y, m = today.year, today.month
    for _ in range(18):
        cache[f"{y}-{m}"] = build_month(y, m, hm, em)
        m += 1
        if m > 12:
            m, y = 1, y + 1
    os.makedirs(os.path.dirname(CACHE_FILE), exist_ok=True)
    with open(CACHE_FILE, 'w') as f:
        json.dump(cache, f, separators=(',', ':'))
    return cache

# ── cache check — stat once, no repeated calls ─────────────────────────────
def load_cache():
    try:
        st = os.stat(CACHE_FILE)
        if (time.time() - st.st_mtime) <= CACHE_MAX_AGE:
            with open(CACHE_FILE) as f:
                return json.load(f)
    except Exception:
        pass
    return None

# ── sync helper — runs vdirsyncer in background, then refreshes cache ──────
def trigger_sync_and_rebuild():
    """
    Kick off vdirsyncer asynchronously. When it finishes, rebuild the cache
    and touch TRIGGER_FILE. QuickShell has a FileView watching that path with
    watchChanges: true, so it picks this up and reloads the current month —
    no polling, no inotifywait subprocess.
    """
    import threading

    def _worker():
        try:
            subprocess.run(['vdirsyncer', 'sync'], timeout=60, capture_output=True)
        except Exception:
            pass
        build_cache()
        try:
            os.makedirs(os.path.dirname(TRIGGER_FILE), exist_ok=True)
            with open(TRIGGER_FILE, 'w') as f:
                f.write(str(time.time()))
        except Exception:
            pass

    t = threading.Thread(target=_worker, daemon=True)
    t.start()

# ── args ───────────────────────────────────────────────────────────────────
year, month = today.year, today.month
if len(sys.argv) >= 3:
    try:
        year, month = int(sys.argv[1]), int(sys.argv[2])
    except ValueError:
        pass
elif len(sys.argv) == 2 and sys.argv[1].strip():
    parts = sys.argv[1].strip().split()
    try:
        year, month = int(parts[0]), int(parts[1])
    except (ValueError, IndexError):
        pass

is_refresh = "--refresh" in sys.argv

cache = load_cache()

if cache is None or is_refresh:
    if is_refresh:
        try:
            subprocess.run(['vdirsyncer', 'sync'], timeout=30, capture_output=True)
        except Exception:
            pass
        cache = build_cache()
    else:
        cache = build_cache()
        trigger_sync_and_rebuild()
else:
    try:
        age = time.time() - os.stat(CACHE_FILE).st_mtime
        if age > 1800:
            trigger_sync_and_rebuild()
    except Exception:
        pass

key = f"{year}-{month}"

if key in cache:
    print(json.dumps(cache[key]), flush=True)
else:
    hm = get_holiday_map()
    print(json.dumps(build_month(year, month, hm, {})), flush=True)
