#!/usr/bin/env bash
# ~/.config/hypr/apply-theme.sh
# Applies pywal colors to kdeglobals (KDE/Qt apps), GTK, and Konsole.
# Call this after wal has run — in shellwrapper.sh after the wal line.
#
# Usage: apply-theme.sh [dark|light]
#   Theme.qml's _writeSystemTheme() calls this with the mode as $1.
#   shellwrapper.sh calls this with NO argument right after wal runs on
#   wallpaper change — in that case we fall back to the persisted
#   ~/.cache/quickshell/theme_mode (written by Theme.qml on every
#   isDark change), same fallback generate-kdeglobals.py already uses.
#   Only defaults to dark if that cache file is missing/unreadable too.
#
# Dependencies: gsettings, plasma-integration (provides QT_QPA_PLATFORMTHEME=kde)
#
# Note: kdeglobals/Kate changes intentionally do NOT push live to
# already-running apps — that's a restart-to-apply model everywhere except
# Konsole. Kate's editor theme has no live-reload path at all.
# Sending KGlobalSettings' notifyChange used to make Dolphin's palette flip
# live while everything else stayed stale, which looked broken — dropped
# that call so behavior is consistent: everything picks up the new theme
# on next launch.

set -eo pipefail

WAL_COLORS="$HOME/.cache/wal/colors"
KONSOLE_DIR="$HOME/.local/share/konsole"
THEME_MODE_CACHE="$HOME/.cache/quickshell/theme_mode"

MODE="${1:-}"
if [[ -z "$MODE" ]]; then
    if [[ -f "$THEME_MODE_CACHE" ]]; then
        MODE="$(cat "$THEME_MODE_CACHE")"
    fi
fi
if [[ "$MODE" != "dark" && "$MODE" != "light" ]]; then
    echo "apply-theme: unknown mode '$MODE', defaulting to dark" >&2
    MODE="dark"
fi

# ── Guard ─────────────────────────────────────────────────────────────────────
if [[ ! -f "$WAL_COLORS" ]]; then
    echo "apply-theme: $WAL_COLORS not found, has wal run yet?" >&2
    exit 1
fi

# ── 1. GTK color scheme ──────────────────────────────────────────────────────
echo "apply-theme: setting GTK $MODE preference..."
if [[ "$MODE" == "light" ]]; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    gsettings set org.gnome.desktop.interface gtk-theme 'Breeze' 2>/dev/null || true
else
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface gtk-theme 'Breeze-Dark' 2>/dev/null || true
fi

# ── 2. kdeglobals adapted for the current mode ───────────────────────────────
echo "apply-theme: generating kdeglobals ($MODE)..."
python3 ~/.config/hypr/generate-kdeglobals.py "$MODE"

# ── 3. KDE color scheme file (symlink to the generated kdeglobals) ──────────
echo "apply-theme: symlinking color scheme..."
mkdir -p ~/.local/share/color-schemes
ln -sf ~/.config/kdeglobals ~/.local/share/color-schemes/pywal.colors

# ── 4. Konsole color scheme (pywal generates this natively) ──────────────────
echo "apply-theme: symlinking Konsole scheme..."
mkdir -p "$KONSOLE_DIR"
ln -sf ~/.cache/wal/colors-konsole.colorscheme "$KONSOLE_DIR/pywal.colorscheme"

# ── 5. Kate/KWrite syntax highlighting theme ─────────────────────────────────
echo "apply-theme: generating Kate theme ($MODE)..."
python3 ~/.config/hypr/generate-kate-theme.py "$MODE"

# ── 6. Force running Konsole instances to reload the profile live ───────────
echo "apply-theme: reloading running Konsole instances..."
for svc in $(qdbus 2>/dev/null | grep '^org\.kde\.konsole'); do
    for session in $(qdbus "$svc" | grep '^/Sessions/[0-9]*$'); do
        qdbus "$svc" "$session" org.kde.konsole.Session.setProfile pywal 2>/dev/null || true
    done
done

# ── 7. Notify Breeze/KWin/KDE platform theme to reparse live ────────────────
echo "apply-theme: notifying Breeze/KWin to reparse..."
dbus-send --session --type=signal /KWin org.kde.KWin.reloadConfig 2>/dev/null || true
dbus-send --session --type=signal /BreezeStyle org.kde.Breeze.Style.reparseConfiguration 2>/dev/null || true
dbus-send --session --type=signal /BreezeDecoration org.kde.Breeze.Style.reparseConfiguration 2>/dev/null || true
dbus-send --session --type=signal /KToolBar org.kde.KToolBar.styleChanged 2>/dev/null || true
dbus-send --session --type=signal /KIconLoader org.kde.KIconLoader.iconChanged 2>/dev/null || true
dbus-send --session --type=signal /KDEPlatformTheme org.kde.KDEPlatformTheme.refreshFonts 2>/dev/null || true

dbus-send --session --type=signal /KGlobalSettings org.kde.KGlobalSettings.notifyChange int32:0 int32:0
echo "apply-theme: done ($MODE)."
