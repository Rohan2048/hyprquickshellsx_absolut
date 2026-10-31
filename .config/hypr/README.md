# hyprquickshellsx — Dependency Reference

Everything the shell's own code actually calls — pulled directly out of
`hyprland.lua`, the `.sh`/`.py` scripts, and the Quickshell QML by reading
every file in the archive, not a generic "what a Hyprland setup usually
needs" list. Fedora is assumed for package names since the codebase's own
comments point at a dnf-based distro (`vnc.sh`: *"sudo dnf install
wayvnc"*).

## Contents
1. [Keybindings](#1-keybindings)
2. [Hyprland](#2-hyprland)
3. [Hyprland companion tools](#3-hyprland-companion-tools)
4. [Quickshell](#4-quickshell)
5. [Rofi](#5-rofi)
6. [khal](#6-khal)
7. [vdirsyncer](#7-vdirsyncer)
8. [pywal](#8-pywal)
9. [KDE/Qt integration layer](#9-kdeqt-integration-layer)
10. [Audio & media](#10-audio--media)
11. [Network & Bluetooth](#11-network--bluetooth)
12. [Screenshots & clipboard](#12-screenshots--clipboard)
13. [Notifications](#13-notifications)
14. [Power & performance](#14-power--performance)
15. [VNC](#15-vnc)
16. [Python runtime](#16-python-runtime)
17. [Fonts, icons & cursors](#17-fonts-icons--cursors)
18. [Misc CLI / base utilities](#18-misc-cli--base-utilities)
19. [Additional Notes to take care of](#19-additional-notes-to-take-cate-of)
20. [Suggested install (Fedora)](#20-suggested-install-fedora)

---
## 1. Keybindings

`Start+L`: locks the screen, you can access some essential quick settings and also have some power options, although shutdown and reboot require you to enter password

`Start+R`: invokes app launcher

`Start+S`: invokes screenshot +editor tool, with grim acting as the backend. You can basically add text(even add your own fonts in text), lines, arrows, rectangles, circles, Doodles(whether normal or dotted, and shapes being either filled or hollow) and add blur to blur sensitive info. You can even select each annotation and accordingly bring that to front or behind as per preference. Save anywhere or share on phone if you have KDE Connect(yea KDE Connect was integrated since it was relatively easier for my flow).

You can toggle VNC server with `Alt+V` and connect with phone accordingly, although this is currently at work to, implement stronger security onto it.

`Alt+R`: lets you scale animations as per your preference.

`Start+W`: lets you invoke app shortcuts. Basically add upto 10 applications.

`Start+Shift+W`: lets you invoke Wallpaper selection. Although the directory is determined in the script `wallpaper-switcher.sh` in `~/.config/hypr` so that can be set accordingly.

`Start+T`: lets you play music locally(you download music, you play it). The directory is fixed as per `autoplay.sh` in `~/.config/hypr` so that can also be adjusted as per preference. `Alt+N` lets you go next, `Alt+P` lets you go previous.

`Alt+S`: lets you set up your hdmi interface for external displays if you have a laptop. For desktops, I advise to comment out the keybindings for `ALT+S` and `ALT+SHIFT+S` in `hyprland.lua` under `~/.config/hypr`.

`Start+Esc`: invokes Power options to directly perform the actions on your computer. These involve "Shut Down", "Reboot", "Suspend" , "Lock" and "Logout".

`Start+Shift+Esc`: invokes Power options that will be performed on the time you schedule. It only involves "Shut Down", "Reboot", and "Suspend".



## 2. Hyprland
- **Hyprland** — the compositor. `hyprland.lua` is marked for **0.55**
  and uses Hyprland's native Lua config API (`hl.monitor`, `hl.bind`,
  `hl.exec_cmd`, `hl.layer_rule`, `hl.window_rule`, `hl.gesture`,
  `hl.env`, `hl.permission`, `hl.config`) instead of the classic
  `hyprland.conf` syntax. Not in Fedora's official repos — see §20.


## 3. Hyprland companion tools
- **hyprctl** — bundled with Hyprland; used constantly (`monitors -j`,
  `eval "hl.monitor(...)"`, `eval "hl.device(...)"`, `reload`) since
  `hyprctl keyword` doesn't work under a Lua config.
- **xdg-desktop-portal-hyprland** + **xdg-desktop-portal** — launched
  directly by `shellwrapper.sh` (systemd portal autostart wasn't
  working on this machine).
- **polkit-mate-authentication-agent-1** — the actual polkit agent
  launched (MATE's, specifically — not polkit-kde or polkit-gnome).
- Cursor theme **Bibata-Modern-Classic**, set via
  `XCURSOR_SIZE`/`HYPRCURSOR_SIZE`.

## 4. Quickshell
- **Quickshell** itself — launched as `qs -d`; controlled at runtime via
  `qs ipc call <target> <action>` (lock, screenshot, commands,
  shortcuts). Not in Fedora's official repos — see §20.
- Must be built with these QML modules enabled: `Quickshell.Hyprland`,
  `Quickshell.Io`, `Quickshell.Wayland`, `Quickshell.Services.Notifications`,
  and **`Quickshell.Services.Pam`** (needs `linux-pam` at build time —
  powers the lock screen's PAM auth).
- Qt6 runtime it pulls in: `QtQuick` / `QtQuick.Controls` / `.Effects` /
  `.Layouts` / `.Shapes`, `QtQml` / `QtQml.Models`, and
  **`Qt5Compat.GraphicalEffects`** (the qt6 5compat module — blur/shadow
  effects).

## 5. Rofi
- **rofi** — app launcher (`-show drun`), power menu, wallpaper picker,
  HDMI menu, schedule-action dialog, clipboard picker, commands
  add/launch, Bluetooth PIN entry. Nine separate `.rasi` theme files.
- Icon theme **Papirus** (rofi's `icon-theme:`), with
  hicolor/Adwaita/Breeze/oxygen as scan fallbacks in `shortcuts-add.sh`.
- Font **Satoshi Variable** — not a repo font, install manually.

## 6. khal
CLI calendar. Invoked as `khal list --format '{start-date}|{title}' ...`
from `calendar.sh`. Reads from a local vdir that vdirsyncer keeps
populated.

## 7. vdirsyncer
`vdirsyncer sync`, invoked from the same script (on a timer, and
synchronously on force-refresh). Local storage has two collections
configured: a Google Calendar one and a holidays one.

## 8. pywal
- The `wal` binary — installed to `~/.local/bin/wal` via pip, **not** a
  Fedora package. Regenerates the color palette on every wallpaper
  change (`wal -i <path>`).
- You may need to use `~/.local/bin/wal -i  "$selected_path" -q` or just `wal -i "$selected_path" -q` depending on distro. Check paths accordingly.
- Ships templates for rofi, GTK, Konsole (generated natively by wal),
  kdeglobals, and Hyprland's own Lua colors
  (`~/.cache/wal/hyprland-colours.lua`, sourced by `hyprland.lua`
  directly via `dofile()`).
- Templates for waybar and dunst also exist under `wal/templates/` but
  have no active consumer — see §19.

## 9. KDE/Qt integration layer
A fair amount of KDE tooling runs underneath Hyprland, without Plasma
itself installed:
- `kdeglobals`, Breeze / Breeze-Dark GTK color scheme — regenerated on
  every theme toggle
- `qdbus`, `dbus-send` — reload live Konsole profiles / notify
  Breeze & KWin to reparse (KWin itself isn't running; this is just a
  harmless signal send)
- `gsettings` — sets the GTK light/dark preference
- KSyntaxHighlighting theme generation, targeting
  `~/.local/share/org.kde.syntax-highlighting/themes/` (Kate/KWrite's
  editor theme format)
- **konsole** (`$terminal`), **dolphin** (`$fileManager` — also killed
  and relaunched on every wallpaper change)
- **kdeconnectd**, **kded**, **kglobalaccel6**, **kdeconnect-indicator**
  — autostarted daemons
- **kdeconnect-cli** — screenshot "share to phone" button; checks
  `command -v kdeconnect-cli` first and shows a notification instead of
  failing outright if it's missing

## 10. Audio & media
- **wpctl** (WirePlumber) — volume/mute, from both keybinds and
  `Services/Volume.qml`
- **pactl** — sink listing/switching (`set-sink.sh`), subscribed to
  live (`volume-listener.sh` reads `pactl subscribe`)
- **playerctl** — media keys, now-playing toasts, `MusicPlayerService.qml`
- **mpv** — background music player (`autoplay.sh`), driven over
  `--input-ipc-server`
- **paplay** — plays the bundled `.mp3` notification sounds (battery
  full/low/critical/charging)

## 11. Network & Bluetooth
- **NetworkManager** (`nmcli`) — scan, connect, forget, `nmcli monitor`
  for live wifi state
- **BlueZ** (`bluetoothctl`) — scan, pair (including interactive
  passkey/PIN confirmation), connect, trust, remove; also queried
  directly over D-Bus (`org.bluez`) in `bt-history.sh`'s monitor mode
- **rfkill** — airplane-mode toggle, Bluetooth fallback status check

## 12. LockScreen, Screenshots & clipboard
- **grim** — called directly from `LockScreen.qml` (pre-lock blur
  background) and `CaptureBackend.qml` (screenshot tool) — not shelled
  out through a wrapper script
- **wl-clipboard** (`wl-copy` / `wl-paste`) — clipboard write, plus
  `wl-paste --watch cliphist` piped straight into history
- **cliphist** — clipboard history backing the `SUPER+P` picker
- **ImageMagick** (`convert`/`magick`) → **rsvg-convert** → **inkscape**
  — fallback chain (first one found wins) for converting `.desktop` app
  icons and SVGs into cached PNGs

## 13. Notifications
- **notify-send** — the large majority of notifications
- **quickshell** — notification service for toast messages, notification popups,etc

## 14. Power & performance
- **tuned** (`tuned-adm profile ...`) — needs passwordless sudo (see the
  sudoers snippet saved in `NOTES.txt`)
- CPU governor — a direct `sudo tee` to
  `/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`, no separate
  tool involved
- Turbo toggle — direct read/write of
  `/sys/devices/system/cpu/intel_pstate/no_turbo` — **Intel-only**,
  won't work on AMD hardware
- `systemd-logind` config edits (`tweaks.sh`, one-time),
  `systemd-inhibit` (`lock-before-suspend.sh`), `loginctl`
- **at** (`atq`/`atrm`) — scheduled shutdown/suspend/reboot

## 15. VNC
**wayvnc** — toggled with `ALT+V`. Official Fedora package.

## 16. Python runtime
- **python3** everywhere — calendar caching, JSON state files, theme
  generation, D-Bus listeners
- pip packages (not all packaged for Fedora — see §20): **Pillow**,
  **dbus-python**, **PyGObject** (`gi.repository.GLib`), **holidays**
  (region hardcoded to `'IN'` in `calendar.sh` — change if that's not
  your locale)

## 17. Fonts, icons & cursors
Two separate theme stacks that don't match each other — see §19:

| | Rofi / QML | GTK apps |
|---|---|---|
| Font | Satoshi Variable | Noto Sans |
| Icon theme | Papirus | breeze |
| Cursor theme | Bibata-Modern-Classic | breeze_cursors |

`colorreload-gtk-module` and `window-decorations-gtk-module` (both from
the **breeze-gtk** package) are also required — set as `gtk-modules` in
both `gtk-3.0` and `gtk-4.0` `settings.ini`.

## 18. Misc CLI / base utilities
`jq`, `openssl`, `dbus-monitor`, `dbus-update-activation-environment`,
`ping`, plus standard coreutils/util-linux (`flock`, `timeout`, `pgrep`,
`stdbuf`, `runuser`, `find`, `sort`) — all things a base install
already has.

Terminal fallback chain in `commands-launch.sh` (first one found wins):
**konsole** → kitty → alacritty → wezterm → foot → xterm.

---

## 19. Additional Notes to take care of
Found while tracing the code — not required reading to get everything
installed, but worth reconciling:

- **Two icon themes** (Papirus for rofi, breeze for GTK) and **two
  cursor themes** (Bibata-Modern-Classic for Hyprland, breeze_cursors
  for GTK) — reads like drift rather than a deliberate choice.
- **hyprexpo** is fully set up (Lua 5.5 built, plugin cloned, `hyprpm`
  permission granted) but every config line for it is commented out —
  dead weight unless you're planning to turn it back on.
- `calendar.sh`'s `holidays` region is hardcoded to `'IN'`.
- `wal/templates/kdeglobals` is superseded by `generate-kdeglobals.py`
  (says so in that script's own comment); `colors-waybar.css`,
  `dunstrc`, and `eww-colours.scss` are leftovers from the pre-Quickshell setup with no active consumer.

## 20. Suggested install (Fedora)

**Not in Fedora's official repos — need a COPR or a source build:**
- **Hyprland** isn't packaged in Fedora's repos; it needs a COPR (these
  shift maintainers — as of late 2025 `solopasha/hyprland` was
  abandoned in favor of `sdegler/hyprland`) or a source build. Check
  [hyprland.org](https://hyprland.org)'s install docs for whichever COPR
  is current when you read this rather than trusting a hardcoded name.
- **Quickshell** isn't packaged either — same story (e.g.
  `errornointernet/quickshell` COPR, or build from source). Watch for
  Qt6 version mismatches between the COPR build and your Fedora's Qt —
  this has broken installs on recent Fedora releases.
- If hand-managing COPRs isn't appealing, **JaKooLit/Fedora-Hyprland**
  on GitHub is a maintained install script built specifically around
  this Hyprland+Quickshell-on-Fedora dependency chain.
- **Lua 5.5** — build from source (steps in `lua5.5 step.txt`), then
  `hyprpm update` / `hyprpm enable hyprexpo` for the plugin.
- **pywal**, **holidays** (Python) — not packaged for Fedora:
  `pip3 install --user pywal holidays`
- **polkit-mate-authentication-agent-1** — from the `mate-polkit`
  package.
- **Satoshi Variable** font — download and drop into
  `~/.local/share/fonts`.

**Everything else — standard dnf install:**
```bash
sudo dnf install hyprlock xdg-desktop-portal-hyprland xdg-desktop-portal \
  rofi khal vdirsyncer \
  konsole dolphin kdeconnect \
  wireplumber pulseaudio-utils playerctl mpv \
  NetworkManager bluez rfkill \
  grim wl-clipboard cliphist \
  ImageMagick librsvg2-tools inkscape \
  dunst libnotify \
  tuned at \
  wayvnc \
  jq openssl brightnessctl \
  python3-pillow python3-dbus python3-gobject python3-pip \
  papirus-icon-theme breeze-icon-theme breeze-cursor-theme breeze-gtk
```

A few of these (`wayvnc`, `cliphist`, `khal`, `vdirsyncer`, `kdeconnect`,
the icon themes) only landed in Fedora's official repos in the last
couple of years — if `dnf install` can't find one on an older release,
that package is the first place to check for a COPR.
