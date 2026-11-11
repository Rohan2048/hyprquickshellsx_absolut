#!/usr/bin/env python3
# ~/.config/hypr/generate-kate-theme.py
# Generates a KSyntaxHighlighting theme from pywal colors
# Output: ~/.local/share/org.kde.syntax-highlighting/themes/pywal.theme
#
# Usage: generate-kate-theme.py [dark|light]
#   apply-theme.sh passes this through as $1. If called with no argument,
#   falls back to reading ~/.cache/quickshell/theme_mode (the file
#   Theme.qml's _writeSystemTheme() writes on every toggle), then to "dark".
#
# Note: pywal's raw colors file is generated once by `wal` and is always
# dark-oriented in this setup (color0 = dark bg, color15 = light fg) — the
# light/dark split isn't baked into the palette the way Theme.qml's own
# `isDark` branches are. So for light mode this script mirrors what
# Theme.qml's adaptColor() does: swap in a fixed light bg/fg (matching
# Theme.qml's fallback palette) and clamp the accent colors' lightness so
# they stay legible against it, rather than just reusing colors[0]/[15].

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

# Load pywal colors
colors_file = os.path.expanduser("~/.cache/wal/colors")
if not os.path.exists(colors_file):
    print("generate-kate-theme: colors file not found", file=sys.stderr)
    sys.exit(1)

with open(colors_file) as f:
    raw = [line.strip() for line in f if line.strip()]

def hex_to_rgb(h):
    h = h.lstrip('#')
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)

def rgb_to_hex(r, g, b):
    r, g, b = (max(0, min(255, int(round(v)))) for v in (r, g, b))
    return f"#{r:02x}{g:02x}{b:02x}"

def blend(hex1, hex2, ratio=0.5):
    """Blend two hex colors."""
    r1, g1, b1 = hex_to_rgb(hex1)
    r2, g2, b2 = hex_to_rgb(hex2)
    r = r1 * (1 - ratio) + r2 * ratio
    g = g1 * (1 - ratio) + g2 * ratio
    b = b1 * (1 - ratio) + b2 * ratio
    return rgb_to_hex(r, g, b)

def shade_toward_bg(hex_color, factor, dark=IS_DARK):
    """Replaces the old darken(hex, factor). Used for subtle background
    overlays (current line, selection, folding markers, etc.) — blends the
    color toward black in dark mode (same as the old darken()) or toward
    white in light mode, so overlays stay subtle against either background
    instead of just getting darker and disappearing on a light bg."""
    target = "#000000" if dark else "#ffffff"
    return blend(hex_color, target, 1 - factor)

def clamp_for_bg(hex_color, dark=IS_DARK):
    """Mirrors Theme.qml's adaptColor(): clamps HSL lightness so accent
    colors (keywords, strings, etc.) stay legible against the current
    background — brighter floor in dark mode, darker ceiling in light mode."""
    r, g, b = hex_to_rgb(hex_color)
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    if dark:
        if l < 0.45:
            l = 0.45
    else:
        if l > 0.5:
            l = 0.5
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return rgb_to_hex(r * 255, g * 255, b * 255)

# Fixed light bg/fg, matching Theme.qml's own light-mode fallback colors
# (background: "#f5f3fa", foreground: "#1a1625") so Kate stays visually
# consistent with the rest of the desktop instead of drifting from it.
BG_LIGHT = "#f5f3fa"
FG_LIGHT = "#1a1625"

# colors[0] = background, colors[7] = foreground-ish, colors[1-6] = accent colors
# colors[8-15] = brighter variants
if IS_DARK:
    bg = raw[0]
    fg = raw[15]          # Normal text
    fg_dim = raw[7]        # LineNumbers / CurrentLineNumber base
else:
    bg = BG_LIGHT
    fg = FG_LIGHT
    fg_dim = FG_LIGHT

c1 = clamp_for_bg(raw[1])
c2 = clamp_for_bg(raw[2])
c3 = clamp_for_bg(raw[3])
c4 = clamp_for_bg(raw[4])
c7 = clamp_for_bg(raw[7]) if IS_DARK else fg_dim
c8 = clamp_for_bg(raw[8])    # muted/comment tone
c9 = clamp_for_bg(raw[9])
c10 = clamp_for_bg(raw[10])
c11 = clamp_for_bg(raw[11])
c12 = clamp_for_bg(raw[12])
c13 = clamp_for_bg(raw[13])
c14 = clamp_for_bg(raw[14])
c15 = fg

theme = {
    "metadata": {
        "name": "pywal",
        "revision": 1
    },
    "text-styles": {
        "Normal": {
            "text-color": c15,
            "selected-text-color": c15,
            "bold": False,
            "italic": False,
            "underline": False,
            "strike-through": False
        },
        "Keyword": {
            "text-color": c9,
            "selected-text-color": c9,
            "bold": True
        },
        "Function": {
            "text-color": c13,
            "selected-text-color": c5 if False else c13,
        },
        "Variable": {
            "text-color": c14,
            "selected-text-color": c14
        },
        "ControlFlow": {
            "text-color": c11,
            "selected-text-color": c11,
            "bold": True
        },
        "Operator": {
            "text-color": c10,
            "selected-text-color": c10
        },
        "BuiltIn": {
            "text-color": c12,
            "selected-text-color": c12
        },
        "Extension": {
            "text-color": c9,
            "selected-text-color": c15,
            "bold": True
        },
        "Preprocessor": {
            "text-color": c10,
            "selected-text-color": c10
        },
        "Attribute": {
            "text-color": c12,
            "selected-text-color": c11
        },
        "Char": {
            "text-color": c14,
            "selected-text-color": c14
        },
        "SpecialChar": {
            "text-color": c14,
            "selected-text-color": c14
        },
        "String": {
            "text-color": c9,
            "selected-text-color": c9
        },
        "VerbatimString": {
            "text-color": c1,
            "selected-text-color": c1
        },
        "SpecialString": {
            "text-color": c1,
            "selected-text-color": c1
        },
        "Import": {
            "text-color": c10,
            "selected-text-color": c10
        },
        "DataType": {
            "text-color": c12,
            "selected-text-color": c11
        },
        "DecVal": {
            "text-color": c13,
            "selected-text-color": c13
        },
        "BaseN": {
            "text-color": c13,
            "selected-text-color": c13
        },
        "Float": {
            "text-color": c13,
            "selected-text-color": c13
        },
        "Constant": {
            "text-color": c14,
            "selected-text-color": c14,
            "bold": True
        },
        "Comment": {
            "text-color": c8,
            "selected-text-color": c8,
            "italic": True
        },
        "Documentation": {
            "text-color": blend(c1, c8),
            "selected-text-color": c1
        },
        "Annotation": {
            "text-color": c10,
            "selected-text-color": c10
        },
        "CommentVar": {
            "text-color": c8,
            "selected-text-color": c8
        },
        "RegionMarker": {
            "text-color": c12,
            "selected-text-color": c14,
            "background-color": shade_toward_bg(c4, 0.3)
        },
        "Information": {
            "text-color": c11,
            "selected-text-color": c3
        },
        "Warning": {
            "text-color": c1,
            "selected-text-color": c1
        },
        "Alert": {
            "text-color": c10,
            "selected-text-color": c10,
            "background-color": shade_toward_bg(c1, 0.3),
            "bold": True
        },
        "Error": {
            "text-color": c1,
            "selected-text-color": c1,
            "underline": True
        },
        "Others": {
            "text-color": c10,
            "selected-text-color": c10
        }
    },
    "editor-colors": {
        "BackgroundColor":               bg,
        "CodeFolding":                   shade_toward_bg(c4, 0.5),
        "BracketMatching":               shade_toward_bg(c7, 0.2),
        "CurrentLine":                   shade_toward_bg(c8, 0.7),
        "IconBorder":                    shade_toward_bg(c8, 0.8),
        "IndentationLine":               shade_toward_bg(c8, 0.6),
        "LineNumbers":                   c8,
        "CurrentLineNumber":             c7,
        "MarkBookmark":                  c12,
        "MarkBreakpointActive":          c1,
        "MarkBreakpointReached":         c11,
        "MarkBreakpointDisabled":        c13,
        "MarkExecution":                 c8,
        "MarkWarning":                   c3,
        "MarkError":                     c1,
        "ModifiedLines":                 c3,
        "ReplaceHighlight":              shade_toward_bg(c11, 0.5),
        "SavedLines":                    c10,
        "SearchHighlight":               shade_toward_bg(c4, 0.4),
        "TextSelection":                 shade_toward_bg(c4, 0.45),
        "Separator":                     shade_toward_bg(c8, 0.7),
        "SpellChecking":                 c1,
        "TabMarker":                     c8,
        "TemplateBackground":            shade_toward_bg(c8, 0.8),
        "TemplatePlaceholder":           shade_toward_bg(c2, 0.3),
        "TemplateFocusedPlaceholder":    shade_toward_bg(c2, 0.3),
        "TemplateReadOnlyPlaceholder":   shade_toward_bg(c1, 0.3),
        "WordWrapMarker":                shade_toward_bg(c8, 0.6)
    }
}

out_dir = os.path.expanduser("~/.local/share/org.kde.syntax-highlighting/themes")
os.makedirs(out_dir, exist_ok=True)
out_file = os.path.join(out_dir, "pywal.theme")

with open(out_file, "w") as f:
    json.dump(theme, f, indent=4)

print(f"generate-kate-theme: written to {out_file} ({MODE})")
