#!/usr/bin/env python3
"""
Scans XDG application directories for .desktop entries, resolves each
one's icon against the active icon theme (following its Inherits= chain,
same resolution order rofi/GTK use), and caches the result.
Only re-scans when the SET of application directories changes (a dir
appearing/disappearing) - not on every call, not based on individual
.desktop file mtimes.

Usage:
  list-apps.py            # print cached JSON if dirs unchanged, else rescan
  list-apps.py --force     # always rescan
"""
import configparser
import json
import os
import subprocess
import sys
from pathlib import Path

ICON_THEME_FALLBACK = "hicolor"  # used only if we can't detect the active theme at all

CACHE_DIR = Path.home() / ".cache" / "quickshell"
CACHE_FILE = CACHE_DIR / "applist-cache.json"


def app_dirs():
    dirs = []
    xdg_data_home = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    dirs.append(Path(xdg_data_home) / "applications")

    xdg_data_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    for d in xdg_data_dirs.split(":"):
        if d:
            dirs.append(Path(d) / "applications")

    for extra in [
        Path.home() / ".local/share/flatpak/exports/share/applications",
        Path("/var/lib/flatpak/exports/share/applications"),
        Path("/var/lib/snapd/desktop/applications"),
    ]:
        if extra not in dirs:
            dirs.append(extra)

    return [d for d in dirs if d.is_dir()]


def icon_search_dirs():
    dirs = [
        Path.home() / ".local/share/icons",
        Path.home() / ".icons",
        Path("/usr/share/icons"),
        Path("/usr/local/share/icons"),
    ]
    return [d for d in dirs if d.is_dir()]


def current_icon_theme():
    """Detects the active icon theme name from whichever DE is running.
    Falls back to hicolor if neither lookup succeeds."""
    for cmd in (
        ["gsettings", "get", "org.gnome.desktop.interface", "icon-theme"],
        ["kreadconfig5", "--file", "kdeglobals", "--group", "Icons", "--key", "Theme"],
    ):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=2)
            if out.returncode == 0 and out.stdout.strip():
                return out.stdout.strip().strip("'\"")
        except Exception:
            continue
    return ICON_THEME_FALLBACK


def theme_inheritance_chain(start_theme):
    """Walks Inherits= chains starting from start_theme, always ending
    with hicolor as the universal fallback. Mirrors how rofi/GTK resolve
    icons instead of guessing a fixed theme priority list - e.g. breeze
    inherits hicolor, other themes may inherit 2-3 levels deep."""
    chain = []
    seen = set()
    queue = [start_theme]
    while queue:
        theme = queue.pop(0)
        if theme in seen:
            continue
        seen.add(theme)
        chain.append(theme)
        for root in icon_search_dirs():
            index_file = root / theme / "index.theme"
            if index_file.is_file():
                try:
                    cp = configparser.RawConfigParser(strict=False)
                    cp.read(index_file, encoding="utf-8")
                    inherits = cp.get("Icon Theme", "Inherits", fallback="")
                    for parent in inherits.split(","):
                        parent = parent.strip()
                        if parent and parent not in seen:
                            queue.append(parent)
                except Exception:
                    pass
                break
    if "hicolor" not in chain:
        chain.append("hicolor")
    return chain


def all_icon_theme_dirs():
    chain = theme_inheritance_chain(current_icon_theme())
    dirs = []
    for theme in chain:
        for root in icon_search_dirs():
            td = root / theme
            if td.is_dir() and td not in dirs:
                dirs.append(td)
    return dirs


def resolve_icon(icon_value):
    if not icon_value:
        return ""
    p = Path(icon_value)
    if p.is_absolute() and p.exists():
        return str(p)

    icon_name = Path(icon_value).name  # strip any path component - rglob needs a bare name

    for theme_dir in all_icon_theme_dirs():
        for ext in ("svg", "png"):
            matches = list(theme_dir.rglob(f"{icon_name}.{ext}"))
            if matches:
                return str(matches[0])

    for ext in ("svg", "png", "xpm"):
        candidate = Path("/usr/share/pixmaps") / f"{icon_name}.{ext}"
        if candidate.exists():
            return str(candidate)

    return ""


def parse_desktop_file(path):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    try:
        cp.read(path, encoding="utf-8")
    except Exception:
        return None
    if "Desktop Entry" not in cp:
        return None
    entry = cp["Desktop Entry"]

    if entry.get("Type", "Application") != "Application":
        return None
    if entry.get("NoDisplay", "false").lower() == "true":
        return None
    if entry.get("Hidden", "false").lower() == "true":
        return None

    name = entry.get("Name", "")
    if not name:
        return None

    exec_raw = entry.get("Exec", "")
    exec_clean = " ".join(
        tok for tok in exec_raw.split()
        if not (tok.startswith("%") and len(tok) == 2)
    )

    return {
        "id": path.stem,
        "name": name,
        "exec": exec_clean,
        "icon": resolve_icon(entry.get("Icon", "")),
        "terminal": entry.get("Terminal", "false").lower() == "true",
    }


def scan():
    dirs = app_dirs()
    seen, apps = set(), []
    for d in dirs:
        for f in sorted(d.glob("*.desktop")):
            app = parse_desktop_file(f)
            if app and app["id"] not in seen:
                seen.add(app["id"])
                apps.append(app)
    apps.sort(key=lambda a: a["name"].lower())
    return dirs, apps


def main():
    force = "--force" in sys.argv
    CACHE_DIR.mkdir(parents=True, exist_ok=True)

    current_fp = sorted(str(d) for d in app_dirs())
    cached = None
    if CACHE_FILE.exists() and not force:
        try:
            cached = json.loads(CACHE_FILE.read_text())
        except Exception:
            cached = None

    if cached and cached.get("dirs") == current_fp:
        print(json.dumps(cached["apps"]))
        return

    _, apps = scan()
    CACHE_FILE.write_text(json.dumps({"dirs": current_fp, "apps": apps}))
    print(json.dumps(apps))


if __name__ == "__main__":
    main()
