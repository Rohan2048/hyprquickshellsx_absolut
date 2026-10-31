#!/usr/bin/env python3
# ~/.config/hypr/generate-kdeglobals.py
# Writes ~/.config/kdeglobals from pywal's colors.json, adapted for light/dark
# mode. Replaces the old `cp ~/.cache/wal/kdeglobals ~/.config/kdeglobals`
# step in apply-theme.sh — that copied file is always dark-oriented since
# nothing here runs `wal -l`, so light mode needs its own bg/fg/accent pass,
# same idea as generate-kate-theme.py.
#
# Usage: generate-kdeglobals.py [dark|light]

import colorsys
import json
import os
import sys

MODE = sys.argv[1] if len(sys.argv) > 1 else None
if MODE not in ("dark", "light"):
    mode_file = os.path.expanduser("~/.cache/quickshell/theme_mode")
    try:
        with open(mode_file) as f:
            MODE = f.read().strip()
    except OSError:
        MODE = None
if MODE not in ("dark", "light"):
    MODE = "dark"
IS_DARK = MODE == "dark"

colors_json = os.path.expanduser("~/.cache/wal/colors.json")
if not os.path.exists(colors_json):
    print("generate-kdeglobals: colors.json not found", file=sys.stderr)
    sys.exit(1)

with open(colors_json) as f:
    data = json.load(f)

special = data.get("special", {})
raw = data.get("colors", {})

def hex_to_rgb(h):
    h = h.lstrip('#')
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)

def rgb_str(hex_color):
    r, g, b = hex_to_rgb(hex_color)
    return f"{r},{g},{b}"

def clamp_for_bg(hex_color, dark):
    """Same clamp as Theme.qml's adaptColor() / the Kate script's
    clamp_for_bg — keeps accent colors legible against the current bg."""
    r, g, b = hex_to_rgb(hex_color)
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    if dark:
        if l < 0.45:
            l = 0.45
    else:
        if l > 0.5:
            l = 0.5
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    r, g, b = (max(0, min(255, int(round(v)))) for v in (r * 255, g * 255, b * 255))
    return f"#{r:02x}{g:02x}{b:02x}"

# Fixed light bg/fg — same values Theme.qml falls back to in light mode
BG_LIGHT = "#f5f3fa"
FG_LIGHT = "#1a1625"

if IS_DARK:
    bg     = rgb_str(special.get("background", "#0d0b16"))
    fg     = rgb_str(special.get("foreground", "#e6e1f0"))
    color0 = rgb_str(raw.get("color0", special.get("background", "#0d0b16")))
    color8 = rgb_str(raw.get("color8", "#4c1d95"))
    color1 = rgb_str(raw.get("color1", "#7c3aed"))
    color2 = rgb_str(raw.get("color2", "#a855f7"))
else:
    bg     = rgb_str(BG_LIGHT)
    fg     = rgb_str(FG_LIGHT)
    color0 = rgb_str(BG_LIGHT)
    color8 = rgb_str(clamp_for_bg(raw.get("color8", "#4c1d95"), dark=False))
    color1 = rgb_str(clamp_for_bg(raw.get("color1", "#7c3aed"), dark=False))
    color2 = rgb_str(clamp_for_bg(raw.get("color2", "#a855f7"), dark=False))

kdeglobals = f"""[ColorEffects:Disabled]
ChangeSelectionColor=true
Color=56,56,56
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0.1
IntensityEffect=2

[ColorEffects:Inactive]
Enable=false

[Colors:Button]
BackgroundNormal={color0}
ForegroundNormal={fg}
DecorationFocus={color1}
DecorationHover={color2}

[Colors:Selection]
BackgroundNormal={color1}
ForegroundNormal={fg}

[Colors:Tooltip]
BackgroundNormal={color0}
ForegroundNormal={fg}

[Colors:View]
BackgroundAlternate={color0}
BackgroundNormal={bg}
ForegroundNormal={fg}
ForegroundInactive={color8}
DecorationFocus={color1}
DecorationHover={color2}

[Colors:Window]
BackgroundNormal={bg}
ForegroundNormal={fg}
DecorationFocus={color1}
DecorationHover={color2}

[Colors:Header]
BackgroundNormal={bg}
ForegroundNormal={fg}
DecorationFocus={color1}
DecorationHover={color2}

[Colors:Complementary]
BackgroundNormal={color0}
ForegroundNormal={fg}
DecorationFocus={color1}
DecorationHover={color2}

[WM]
activeBackground={color0}
activeForeground={fg}
inactiveBackground={bg}
inactiveForeground={color8}

[General]
ColorScheme=pywal
Name=pywal
shadeSortColumn=true

[KDE]
contrast=4
widgetStyle=Breeze
"""

out_path = os.path.expanduser("~/.config/kdeglobals")
tmp_path = out_path + ".tmp"
with open(tmp_path, "w") as f:
    f.write(kdeglobals)
os.replace(tmp_path, out_path)

print(f"generate-kdeglobals: written to {out_path} ({MODE})")


