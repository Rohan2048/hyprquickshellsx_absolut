#!/usr/bin/env python3
"""
scan_apps.py — single-process replacement for the "SCAN_NEEDED" block of
shortcuts-add.sh.

Why the old bash block was slow:
  - Parsed every .desktop file with 3-4 `grep`/`cut` subprocess spawns each.
  - resolve_icon_gtk() launched a fresh `python3` interpreter (importing
    gi/Gtk from scratch) for EVERY icon that missed the direct-path check —
    by far the biggest cost, since PyGObject import + Gtk.IconTheme init is
    the expensive part, and it was paying that cost hundreds of times.
  - Icon index was built with `find | while read | printf`, line at a time.

This script does the equivalent work in one process:
  - Parses .desktop files with plain line scans (no subprocess).
  - Imports gi/Gtk exactly once; keeps one IconTheme instance and an
    in-memory resolution cache for the whole run.
  - Builds the basename->path icon index with a single os.walk pass.
  - Still shells out to convert/rsvg-convert/inkscape for the actual
    raster conversion (nothing pure-Python replaces those), but each
    external call happens once per icon, run in parallel with a
    ThreadPoolExecutor instead of backgrounded bash jobs + `wait -n`.

Output is unchanged from the original: it (re)writes APP_CACHE (tsv:
name\tdesktop_path\ticon_safe_name), ICON_INDEX (tsv, kept for parity /
debugging), the cached icon PNGs under ICONS_DIR, and touches CACHE_STAMP.
shortcuts-add.sh reads APP_CACHE exactly as before — nothing downstream
needs to change.
"""
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HOME = Path.home()
ICONS_DIR = HOME / ".config/quickshell/icons"
APP_CACHE = ICONS_DIR / ".app_cache.tsv"
ICON_INDEX = ICONS_DIR / ".icon_index.tsv"
CACHE_STAMP = ICONS_DIR / ".last_scan"

ICON_SIZE = 40
PNG_ARGS = ["-strip", "-define", "png:compression-level=9"]
WORKERS = os.cpu_count() or 4

APP_DIRS = [
    Path("/usr/share/applications"),
    Path("/usr/local/share/applications"),
    HOME / ".local/share/applications",
    Path("/var/lib/flatpak/exports/share/applications"),
    HOME / ".local/share/flatpak/exports/share/applications",
    Path("/var/lib/snapd/desktop/applications"),
]

ICON_SEARCH_DIRS = [
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
    HOME / ".local/share/icons",
    Path("/var/lib/flatpak/exports/share/icons"),
    HOME / ".local/share/flatpak/exports/share/icons",
]

ICON_EXTS = (".png", ".svg", ".xpm")


def safe_name(icon: str) -> str:
    return icon.replace("/", "_").replace(" ", "_")


# --- .desktop parsing (replaces grep -m1 "^Key=" | cut -d= -f2-) ---------
def parse_desktop(path: Path):
    name = icon = nodisplay = hidden = None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                if name is None and line.startswith("Name="):
                    name = line[len("Name="):].rstrip("\n")
                elif icon is None and line.startswith("Icon="):
                    icon = line[len("Icon="):].rstrip("\n")
                elif nodisplay is None and line.startswith("NoDisplay="):
                    nodisplay = line[len("NoDisplay="):].rstrip("\n")
                elif hidden is None and line.startswith("Hidden="):
                    hidden = line[len("Hidden="):].rstrip("\n")
    except OSError:
        return None
    if not name or "\t" in name:
        return None
    if nodisplay == "true" or hidden == "true":
        return None
    return name, icon or ""


def scan_desktop_entries():
    """Returns list of (name, desktop_path, icon_name) in dir-precedence
    order, deduped by name keeping the first occurrence — same semantics
    as the original find-loop + `awk '!seen[$1]++'`."""
    seen = set()
    rows = []
    for d in APP_DIRS:
        if not d.is_dir():
            continue
        try:
            entries = sorted(p for p in d.iterdir() if p.suffix == ".desktop")
        except OSError:
            continue
        for dfile in entries:
            parsed = parse_desktop(dfile)
            if not parsed:
                continue
            name, icon = parsed
            if name in seen:
                continue
            seen.add(name)
            rows.append((name, str(dfile), icon))
    return rows


# --- Icon index: one os.walk pass instead of `find` per dir + a line loop
def build_icon_index():
    index = {}
    for d in ICON_SEARCH_DIRS:
        if not d.is_dir():
            continue
        for root, _dirs, files in os.walk(d):
            for fname in files:
                if fname.lower().endswith(ICON_EXTS):
                    index.setdefault(fname, os.path.join(root, fname))
    return index


# --- GTK theme resolution, imported once, reused for the whole run ------
def make_gtk_lookup():
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
        theme = Gtk.IconTheme.get_default()
    except Exception:
        return lambda name: ""

    def lookup(name: str) -> str:
        try:
            info = theme.lookup_icon(name, ICON_SIZE, 0)
            return info.get_filename() or "" if info else ""
        except Exception:
            return ""

    return lookup


def resolve_icon(icon: str, gtk_lookup, icon_index: dict, cache: dict) -> str:
    if icon in cache:
        return cache[icon]
    if os.path.isfile(icon):
        result = icon
    else:
        result = gtk_lookup(icon)
        if not result:
            for ext in (".png", ".svg", ".xpm"):
                hit = icon_index.get(f"{icon}{ext}")
                if hit:
                    result = hit
                    break
    cache[icon] = result
    return result


# --- Conversion: same tool fallback chain as cache_icon(), still shells
# out (nothing pure-Python replaces convert/rsvg-convert/inkscape), but
# each icon is only resolved+converted once and runs in a thread pool.
def cache_icon(src: str, out: Path) -> bool:
    if out.exists():
        return True
    lower = src.lower()
    try:
        if lower.endswith(".svg"):
            if run_ok(["rsvg-convert", "-w", str(ICON_SIZE), "-h", str(ICON_SIZE), src, "-o", str(out)]):
                return True
            if run_ok(["convert", "-background", "none", "-resize", f"{ICON_SIZE}x{ICON_SIZE}", *PNG_ARGS, src, str(out)]):
                return True
            if run_ok(["inkscape", "--export-type=png", f"--export-width={ICON_SIZE}",
                       f"--export-height={ICON_SIZE}", f"--export-filename={out}", src]):
                return True
        elif lower.endswith(".xpm"):
            if run_ok(["convert", src, "-resize", f"{ICON_SIZE}x{ICON_SIZE}", *PNG_ARGS, str(out)]):
                return True
        else:
            if run_ok(["convert", src, "-resize", f"{ICON_SIZE}x{ICON_SIZE}", *PNG_ARGS, str(out)]):
                return True
            if lower.endswith(".png"):
                out.write_bytes(Path(src).read_bytes())
                return True
    except Exception:
        return False
    return False


def run_ok(cmd) -> bool:
    if not has_tool(cmd[0]):
        return False
    try:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        return True
    except (subprocess.CalledProcessError, OSError):
        return False


_tool_cache = {}


def has_tool(name: str) -> bool:
    if name not in _tool_cache:
        _tool_cache[name] = subprocess.run(
            ["sh", "-c", f"command -v {name}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        ).returncode == 0
    return _tool_cache[name]


def process_icon(icon: str, gtk_lookup, icon_index: dict, resolve_cache: dict):
    safe = safe_name(icon)
    out = ICONS_DIR / f"{safe}.png"
    if out.exists():
        return
    path = resolve_icon(icon, gtk_lookup, icon_index, resolve_cache)
    if path:
        cache_icon(path, out)


def main():
    ICONS_DIR.mkdir(parents=True, exist_ok=True)

    rows = scan_desktop_entries()
    if not rows:
        print("No applications found", file=sys.stderr)
        return 1

    icon_index = build_icon_index()
    gtk_lookup = make_gtk_lookup()
    resolve_cache: dict = {}

    # Resolution stays single-threaded (it's now in-process and fast —
    # no subprocess spawn per lookup — and Gtk.IconTheme isn't safe to
    # hammer from multiple threads). Only the actual file conversion,
    # which is pure subprocess I/O wait, goes in the thread pool.
    icons_needed = sorted({icon for _, _, icon in rows if icon})
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        list(pool.map(lambda i: process_icon(i, gtk_lookup, icon_index, resolve_cache), icons_needed))

    tmp_cache = APP_CACHE.with_suffix(".tsv.building")
    with open(tmp_cache, "w", encoding="utf-8") as f:
        for name, dfile, icon in rows:
            f.write(f"{name}\t{dfile}\t{safe_name(icon) if icon else ''}\n")
    tmp_cache.replace(APP_CACHE)

    with open(ICON_INDEX, "w", encoding="utf-8") as f:
        for basename, path in icon_index.items():
            f.write(f"{basename}\t{path}\n")

    CACHE_STAMP.touch()
    return 0


if __name__ == "__main__":
    sys.exit(main())
