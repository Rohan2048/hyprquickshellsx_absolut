#!/usr/bin/env bash
# =============================================================================
#  install.sh  -  install / upgrade Shspeshifter Shell (hyprquickshellsx_absolut)
#
#  One script for both jobs: run it on a fresh machine to install everything,
#  run it again later to upgrade (git pull + package upgrades + config sync).
#
#  Target: Fedora (dnf).  Run it from a clone of the repo, as your normal user
#  (it asks for sudo only for the steps that need it).
#
#    ./install.sh              interactive install / upgrade
#    ./install.sh --check      dry run: search repos, show what WOULD happen
#    ./install.sh --tools      only list which tools exist and their versions (any distro), then stop
#    ./install.sh --config-only   only pull + sync the config folders (fast update)
#    ./install.sh --packages-only only install / upgrade the tools
#    ./install.sh -y           answer yes to prompts (except sudoers, see below)
#    ./install.sh --force      overwrite config files you edited (a backup is made)
#    ./install.sh --no-copr    never enable a COPR; tell me what to install myself
#    ./install.sh --no-pull    do not git pull
#    ./install.sh --no-upgrade do not upgrade already-installed packages
#    ./install.sh --sudoers narrow|full|skip   passwordless-sudo rules (asked if omitted)
#    ./install.sh -v           show command output live; DEBUG=1 for a full bash trace
#
#  Where packages come from (nothing else is ever used):
#    1. Fedora's own repositories (dnf)
#    2. Only if Fedora's repos do not carry the needed version, exactly two COPRs:
#         sdegler/hyprland          (Hyprland + portal)
#         errornointernet/quickshell
#    3. PyPI, only for pywal (and holidays / vdirsyncer[google] if dnf lacks them)
#  Fonts and wallpapers come from this repo, nothing is downloaded for them.
#
#  Every failure is written to a log with the exact command, exit code and
#  output, and repeated at the end with a hint on how to fix it.
#
#  Missing tools never block the config copy: on non-Fedora systems (or without
#  dnf / sudo) the script warns and still syncs the config folders. Use --tools
#  at any time to see which tools are present.
# =============================================================================
set -o pipefail
[[ ${DEBUG:-0} == 1 ]] && set -x

SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SRC="$(dirname "$SELF")"
ORIG_ARGS=("$@")

OFFICIAL_REPO_RE='^(https://(www\.)?github\.com/|git@github\.com:|ssh://git@github\.com/)Rohan2048/hyprquickshellsx_absolut(\.git)?/?$'
TRUSTED_COPRS=("sdegler/hyprland" "errornointernet/quickshell")
MIN_HYPRLAND="0.55"

# ---------- options ----------------------------------------------------------
TOOLS_ONLY=0 CHECK=0 CONFIG_ONLY=0 PKG_ONLY=0 ASSUME_YES=0 FORCE=0 NO_COPR=0 NO_PULL=0 NO_UPGRADE=0 VERBOSE=0
SUDOERS_MODE=""
while (($#)); do
  case "$1" in
    --check) CHECK=1 ;;
    --tools) TOOLS_ONLY=1 ;;
    --config-only) CONFIG_ONLY=1 ;;
    --packages-only) PKG_ONLY=1 ;;
    -y|--yes) ASSUME_YES=1 ;;
    --force) FORCE=1 ;;
    --no-copr) NO_COPR=1 ;;
    --no-pull) NO_PULL=1 ;;
    --no-upgrade) NO_UPGRADE=1 ;;
    --sudoers) shift; SUDOERS_MODE="${1:-}"; [[ $SUDOERS_MODE =~ ^(narrow|full|skip)$ ]] || { echo "--sudoers needs narrow|full|skip"; exit 2; } ;;
    -v|--verbose) VERBOSE=1 ;;
    -h|--help) sed -n '2,38p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)"; exit 2 ;;
  esac
  shift
done
((CONFIG_ONLY && PKG_ONLY)) && { echo "--config-only and --packages-only cannot be combined"; exit 2; }

# ---------- output / logging -------------------------------------------------
if [[ -t 1 ]]; then B=$'\e[1m'; R=$'\e[31m'; G=$'\e[32m'; Y=$'\e[33m'; C=$'\e[36m'; N=$'\e[0m'; else B= R= G= Y= C= N=; fi
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprquickshellsx"
mkdir -p "$STATE_DIR/logs"
LOG="$STATE_DIR/logs/install-$(date +%Y%m%d-%H%M%S).log"
LAST_OUT="$(mktemp)"
TMPD="$(mktemp -d)"
ISSUES=()
KEEPALIVE_PID=""
RC=0

say()  { printf '%s\n' "$*" | tee -a "$LOG" >/dev/null; printf '%s\n' "$*"; }
step() { printf '\n%s==> %s%s\n' "$B$C" "$*" "$N"; printf '\n==> %s\n' "$*" >>"$LOG"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; printf '  ok: %s\n' "$*" >>"$LOG"; }
info() { printf '  %s\n' "$*"; printf '  %s\n' "$*" >>"$LOG"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; printf '  WARN: %s\n' "$*" >>"$LOG"; }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$*"; printf '  FAIL: %s\n' "$*" >>"$LOG"; }

cleanup() {
  [[ -n $KEEPALIVE_PID ]] && kill "$KEEPALIVE_PID" 2>/dev/null
  rm -rf "$TMPD" "$LAST_OUT"
}
trap cleanup EXIT
trap 'echo; echo "Interrupted. Log: $LOG"; exit 130' INT TERM

# run LABEL cmd...   -> output to $LAST_OUT and the log, exit code in $RC
run() {
  local label="$1"; shift
  { printf '\n### [%s] %s\n$ %s\n' "$(date +%T)" "$label" "$*"; } >>"$LOG"
  : >"$LAST_OUT"
  if ((VERBOSE)); then
    "$@" 2>&1 | tee -a "$LAST_OUT" "$LOG"; RC=${PIPESTATUS[0]}
  else
    "$@" >"$LAST_OUT" 2>&1; RC=$?; cat "$LAST_OUT" >>"$LOG"
  fi
  printf '[exit %s]\n' "$RC" >>"$LOG"
  return "$RC"
}

# add_issue ERROR|WARN "title" "hint"   (attaches the tail of the last command's output)
add_issue() {
  local lvl="$1" title="$2" hint="$3" tailtxt
  tailtxt="$(tail -n 8 "$LAST_OUT" 2>/dev/null | sed 's/^/        /' | tr '\n' '\036')"
  ISSUES+=("${lvl}"$'\x1f'"${title}"$'\x1f'"${hint}"$'\x1f'"exit ${RC}"$'\x1f'"${tailtxt}")
  [[ $lvl == ERROR ]] && bad "$title" || warn "$title"
}

ask() { # ask "question" [default y|n]
  local q="$1" d="${2:-y}" a
  ((ASSUME_YES)) && return 0
  [[ -t 0 ]] || { [[ $d == y ]]; return; }
  read -r -p "  $q [$([[ $d == y ]] && echo Y/n || echo y/N)] " a
  a="${a:-$d}"; [[ $a =~ ^[Yy] ]]
}

die() { bad "$*"; echo; echo "Log: $LOG"; exit 1; }

ver_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]; }

# ---------- tool report (works on any distro) --------------------------------
# "name[/alt name]|flag that prints its version"  (empty flag: the tool has none, the package manager is asked instead)
REQ_TOOLS=(
  # WM / shell / launcher
  "Hyprland|--version" "hyprctl|version" "qs/quickshell|--version" "rofi|-version"
  # theming / clipboard / screenshots
  "wal|--version" "grim|" "wl-copy|--version" "wl-paste|--version" "cliphist|version"
  # audio / media
  "playerctl|--version" "wpctl|--version" "pactl|--version" "paplay|--version" "mpv|--version" "yt-dlp|--version"
  # display / network / bluetooth
  "brightnessctl|--version" "udevadm|--version" "nmcli|--version" "bluetoothctl|--version" "rfkill|--version"
  "dbus-monitor|--version" "dbus-send|--version" "dbus-update-activation-environment|"
  # notifications / power / scheduling
  "notify-send|--version" "tuned-adm|" "sysctl|--version" "systemctl|--version" "systemd-inhibit|--version" "at|-V"
  # calendar
  "khal|--version" "vdirsyncer|--version"
  # KDE / GTK integration layer, polkit, terminal, file manager
  "gsettings|--version" "qdbus6/qdbus-qt6/qdbus|" "kded6|" "kglobalaccel6/kglobalacceld|"
  "polkit-mate-authentication-agent-1|" "konsole|--version" "dolphin|--version"
  # wallpaper thumbnails / icon cache
  "magick/convert|--version"
  # misc / standard
  "jq|--version" "openssl|version" "ping|-V" "socat|-V" "inotifywait|--help" "fc-list|--version"
  "gcc|--version" "git|--version" "curl|--version" "unzip|-v" "python3|--version" "sudo|--version"
  "awk|" "sed|--version" "grep|--version" "find|--version"
)
OPT_TOOLS=(
  "wayvnc|--version" "qt6ct|" "kvantummanager|--version" "rsvg-convert|--version" "mpvpaper|" "qmake6/qmake-qt6|--version"
  "kdeconnect-cli|--version" "kdeconnectd|" "kdeconnect-indicator|"
)
PY_MODULES=( dbus gi PIL holidays )
QML_MODULES=(
  QtQuick/Layouts QtQuick/Controls QtQuick/Effects QtQuick/Shapes QtQml/Models Qt5Compat/GraphicalEffects
  Quickshell/Io Quickshell/Wayland Quickshell/Hyprland Quickshell/Services/Notifications Quickshell/Services/Pam
)
TOOL_MISS_REQ=()

# find an executable by name: PATH first, then the usual libexec folders (polkit agent, kdeconnectd, kglobalacceld live there)
find_exe() {
  local n="$1" p d
  p="$(command -v "$n" 2>/dev/null)"
  [[ -n $p && -x $p ]] && { printf '%s' "$p"; return 0; }
  for d in /usr/libexec /usr/lib /usr/lib64 /usr/libexec/kf6 /usr/lib/kf6 /usr/lib/kf6/libexec /usr/lib64/libexec /usr/lib/mate-polkit /usr/libexec/mate-polkit /usr/lib/polkit-mate; do
    [[ -f $d/$n && -x $d/$n ]] && { printf '%s' "$d/$n"; return 0; }
  done
  return 1
}

# version of the package that owns a file, whatever the distro's package manager is
pkg_version_of() {
  local f v="" pk
  f="$(readlink -f "$1" 2>/dev/null)" || return 0
  if command -v rpm >/dev/null 2>&1; then v="$(rpm -qf --qf '%{VERSION}' "$f" 2>/dev/null)" || v=""
  elif command -v dpkg-query >/dev/null 2>&1; then
    pk="$(dpkg-query -S "$f" 2>/dev/null | head -n1 | cut -d: -f1)"
    [[ -n $pk ]] && v="$(dpkg-query -W -f='${Version}' "$pk" 2>/dev/null)"
  elif command -v pacman >/dev/null 2>&1; then
    pk="$(pacman -Qoq "$f" 2>/dev/null | head -n1)"
    [[ -n $pk ]] && v="$(pacman -Q "$pk" 2>/dev/null | awk '{print $2}')"
  fi
  printf '%s' "$v"
}

# tool_version PATH FLAG  -> first version number the tool prints, else the owning package's version, else nothing
tool_version() {
  local p="$1" a="$2" out="" v=""
  if [[ -n $a ]]; then
    out="$(${TO[@]+"${TO[@]}"} "$p" $a </dev/null 2>&1 | head -n 20)"
    v="$(grep -oE '[0-9]+(\.[0-9]+)+' <<<"$out" | head -n1)"
  fi
  [[ -z $v ]] && v="$(pkg_version_of "$p")"
  printf '%s' "$v"
}

# trow ok|miss|opt NAME TEXT  -> one line on screen, the same line without colour in the log
trow() {
  local mark
  case "$1" in ok) mark="${G}✓${N}" ;; miss) mark="${R}✗${N}" ;; *) mark="${Y}-${N}" ;; esac
  printf '  %s %-18s %s\n' "$mark" "$2" "$3"
  printf '  tool %-18s %s\n' "$2" "$3" >>"$LOG"
}

tool_report() {
  local d_id d_name pm="" m spec names flag n found path v rc mod dir hit pass qip ldc lib so
  local -a alts
  TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 3)
  d_id="$( . /etc/os-release 2>/dev/null; printf '%s' "${ID:-unknown}" )"
  d_name="$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-unknown}" )"
  for m in dnf apt pacman zypper apk xbps-install nix-env; do command -v "$m" >/dev/null 2>&1 && { pm="$m"; break; }; done
  step "Tool check"
  info "system:  $d_name   kernel $(uname -r)   package manager: ${pm:-none found}"
  info "session: ${XDG_SESSION_TYPE:-unknown}   wayland display: ${WAYLAND_DISPLAY:-none}   bash ${BASH_VERSION%%[^0-9.]*}"
  TOOL_MISS_REQ=()
  for pass in req opt; do
    echo; printf '  %s%s tools%s\n' "$B" "$([[ $pass == req ]] && echo Required || echo Optional)" "$N"
    local list=("${REQ_TOOLS[@]}"); [[ $pass == opt ]] && list=("${OPT_TOOLS[@]}")
    for spec in "${list[@]}"; do
      names="${spec%%|*}"; flag="${spec#*|}"; found=""; path=""
      IFS=/ read -ra alts <<<"$names"
      for n in "${alts[@]}"; do path="$(find_exe "$n")" && [[ -n $path ]] && { found="$n"; break; }; done
      if [[ -n $found ]]; then
        v="$(tool_version "$path" "$flag")"
        if [[ $found == Hyprland && -n $v ]] && ! ver_ge "$v" "$MIN_HYPRLAND"; then
          trow miss "$found" "${v}  (too old: this config needs >= $MIN_HYPRLAND)  $path"
          TOOL_MISS_REQ+=("Hyprland>=$MIN_HYPRLAND")
        else
          trow ok "$found" "${v:-present, version unknown}  $path"
        fi
      elif [[ $pass == req ]]; then trow miss "${names//\// or }" "not found"; TOOL_MISS_REQ+=("${alts[0]}")
      else trow opt "${names//\// or }" "not found (optional)"; fi
    done
  done

  echo; printf '  %sPython modules%s (python3 %s)\n' "$B" "$N" "$(python3 -c 'import platform; print(platform.python_version())' 2>/dev/null || echo missing)"
  if command -v python3 >/dev/null 2>&1; then
    for mod in "${PY_MODULES[@]}"; do
      v="$(python3 -c "import $mod; print(getattr($mod, '__version__', ''))" 2>/dev/null)"; rc=$?
      if ((rc == 0)); then trow ok "$mod" "${v:-present, version unknown}"
      else trow miss "$mod" "cannot be imported"; TOOL_MISS_REQ+=("python:$mod"); fi
    done
  fi

  echo; printf '  %sQt / QML modules%s\n' "$B" "$N"
  qip="${QML_IMPORT_PATH:-}:${QML2_IMPORT_PATH:-}"
  for mod in "${QML_MODULES[@]}"; do
    hit=""
    for dir in /usr/lib64/qt6/qml /usr/lib/qt6/qml /usr/lib/x86_64-linux-gnu/qt6/qml /usr/lib/aarch64-linux-gnu/qt6/qml /usr/lib/qt/qml /usr/local/lib64/qt6/qml /usr/local/lib/qt6/qml ${qip//:/ }; do
      [[ -d $dir/$mod ]] && { hit="$dir/$mod"; break; }
    done
    if [[ -n $hit ]]; then trow ok "${mod//\//.}" "$hit"
    else trow miss "${mod//\//.}" "not found in the usual Qt6 QML folders"; TOOL_MISS_REQ+=("qml:${mod//\//.}"); fi
  done

  echo; printf '  %sLibraries / services%s\n' "$B" "$N"
  ldc="$(command -v ldconfig 2>/dev/null || echo /sbin/ldconfig)"
  for lib in libgtk-4.so:gtk4 libadwaita-1.so:libadwaita; do
    so="${lib%%:*}"; n="${lib#*:}"
    if "$ldc" -p 2>/dev/null | grep -q "$so"; then trow ok "$n" "found ($so)"
    else trow miss "$n" "not found ($so)"; TOOL_MISS_REQ+=("lib:$n"); fi
  done
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet atd 2>/dev/null; then trow ok "atd (service)" "running"
    else trow opt "atd (service)" "not running: scheduled shutdown/suspend/reboot needs it (sudo systemctl enable --now atd)"; fi
  fi

  echo
  if ((${#TOOL_MISS_REQ[@]} == 0)); then ok "every required tool is present"
  elif [[ $d_id == fedora ]]; then info "missing / outdated: ${TOOL_MISS_REQ[*]}  (the package step below takes care of these)"
  else
    : >"$LAST_OUT"; RC=0
    add_issue WARN "required tools missing or too old: ${TOOL_MISS_REQ[*]}" "This script only installs packages on Fedora. Install them with your distro's package manager (${pm:-none found}); the exact names differ per distro, see README.md. Run ./install.sh --tools to re-check."
  fi
  return 0
}

# ---------- wheel / sudo check ----------------------------------------------
check_wheel() {
  step "sudo / wheel group"
  local user grp members insess=0 hint
  user="$(id -un)"
  if getent group wheel >/dev/null 2>&1; then grp=wheel
  elif getent group sudo >/dev/null 2>&1; then grp=sudo
  else grp=wheel; fi
  hint="As root (su -), add yourself: usermod -aG $grp $user . Then run 'visudo' and make sure this line exists and is NOT commented out:  %$grp ALL=(ALL) ALL   . Log out and back in afterwards. WARNING: never edit /etc/sudoers with a normal editor or with a plain 'sudo nano /etc/sudoers': a single syntax error breaks sudo completely. Only use visudo (it validates before saving). See README.md, 'Sudo / Permissions'."
  if ! command -v sudo >/dev/null 2>&1; then
    : >"$LAST_OUT"; RC=0
    add_issue WARN "sudo is not installed" "Install sudo as root (Fedora: su -c 'dnf install sudo'; Debian/Ubuntu: apt install sudo; Arch: pacman -S sudo). $hint"
    return 0
  fi
  members=" $(getent group "$grp" 2>/dev/null | cut -d: -f4 | tr ',' ' ') "
  id -nG "$user" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp" && insess=1
  if ((insess)); then ok "$user is in the '$grp' group"
  elif [[ $members == *" $user "* ]]; then
    warn "$user was added to '$grp' but this session predates it: log out and back in for sudo to work"
  else
    : >"$LAST_OUT"; RC=0
    add_issue WARN "'$user' is not in the '$grp' group (sudo will not work)" "$hint"
    return 0
  fi
  if sudo -n true 2>/dev/null; then
    if sudo -n grep -rhsE "^[[:space:]]*%$grp[[:space:]]" /etc/sudoers /etc/sudoers.d 2>/dev/null | grep -q .; then ok "sudoers has an active %$grp rule"
    else
      : >"$LAST_OUT"; RC=0
      add_issue WARN "no active %$grp rule found in sudoers" "$hint"
    fi
  else info "sudoers rule not verified (needs a password to read); the sudo step below will show whether it works"; fi
  return 0
}

# ---------- vdirsyncer (calendar sync) check ---------------------------------
check_vdirsyncer() {
  step "Calendar sync (vdirsyncer, optional)"
  local vd="$HOME/.config/vdirsyncer"
  if [[ ! -d $vd ]]; then
    warn "$vd does not exist: Google Calendar sync is not set up."
    info "Optional. The calendar popup is part of the shell either way; with vdirsyncer + khal it also shows your Google Calendar events."
    info "To enable it: follow 'Calendar Widget Setup' in README.md (Google OAuth credentials, ~/.config/vdirsyncer/config, vdirsyncer discover, vdirsyncer sync)."
  elif [[ ! -f $vd/config ]]; then
    warn "$vd exists but has no config file. See 'Calendar Widget Setup' in README.md (Step 4) if you want calendar sync."
  elif grep -q 'google_calendar' "$vd/config" 2>/dev/null && [[ ! -s $vd/google_token ]]; then
    warn "vdirsyncer is configured but not authenticated (no google_token). Run: vdirsyncer discover google_calendar   then: vdirsyncer sync"
  else
    ok "vdirsyncer configured ($vd)"
    if command -v systemctl >/dev/null 2>&1 && ! systemctl --user is-enabled vdirsyncer.timer >/dev/null 2>&1; then
      info "no vdirsyncer.timer enabled: events only sync when you run 'vdirsyncer sync' (README.md, Step 8 sets up auto-sync)"
    fi
  fi
  return 0
}

# ---------- sanity -----------------------------------------------------------
((EUID == 0)) && die "Do not run this as root. Run as your normal user; sudo is used only where needed."
printf '%sShspeshifter Shell installer%s  (log: %s)\n' "$B" "$N" "$LOG"
{ echo "install.sh args: ${ORIG_ARGS[*]:-}"; echo "date: $(date -Is)"; echo "user: $(id -un)  home: $HOME"; } >>"$LOG"

if [[ -d $SRC/.config/hypr && -d $SRC/.config/quickshell ]]; then CONF_SRC="$SRC/.config"
elif [[ -d $SRC/hypr && -d $SRC/quickshell ]]; then CONF_SRC="$SRC"
else die "Cannot find the config folders next to install.sh ($SRC). Run it from a clone of the repo (it needs the .config/ folder)."; fi
FONTS_SRC="$SRC/fonts"; WALL_SRC="$SRC/wallpapers"
CONFIG="$HOME/.config"

# ---------- 1. pull the latest repo -----------------------------------------
self_update() {
  step "Repository"
  if ((NO_PULL)); then info "skipping git pull (--no-pull)"; return; fi
  command -v git >/dev/null || { warn "git is not installed; cannot pull (it gets installed below)"; return; }
  [[ -d $SRC/.git ]] || { info "not a git checkout, using the files as they are"; return; }
  local url before after
  url="$(git -C "$SRC" remote get-url origin 2>/dev/null)"
  if ! [[ $url =~ $OFFICIAL_REPO_RE ]]; then
    warn "origin is '$url', not the official repo. Not pulling from it; using local files."
    return
  fi
  before="$(git -C "$SRC" rev-parse HEAD)"
  if ((CHECK)); then
    run "git fetch" git -C "$SRC" fetch --quiet origin || { add_issue WARN "git fetch failed" "Check your network; try: git -C '$SRC' fetch"; return; }
    local behind; behind="$(git -C "$SRC" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo '?')"
    info "$behind commit(s) available upstream"; return
  fi
  if run "git pull" git -C "$SRC" pull --ff-only; then
    after="$(git -C "$SRC" rev-parse HEAD)"
    if [[ $before == "$after" ]]; then ok "already up to date ($(git -C "$SRC" rev-parse --short HEAD))"
    else
      ok "updated $(git -C "$SRC" rev-parse --short "$before") -> $(git -C "$SRC" rev-parse --short "$after")"
      if ! git -C "$SRC" diff --quiet "$before" "$after" -- install.sh 2>/dev/null; then
        info "install.sh itself changed; restarting with the new version"
        exec bash "$SELF" "${ORIG_ARGS[@]}" --no-pull
      fi
    fi
  else
    add_issue WARN "git pull failed" "Local changes or diverged history. See: git -C '$SRC' status   (stash/commit your edits, then re-run). Continuing with the files already here."
  fi
}

# ---------- 2. packages ------------------------------------------------------
REQ_PKGS=(
  # shell + session basics
  libnotify rofi ImageMagick wl-clipboard cliphist grim jq openssl iputils inotify-tools
  gawk sed grep findutils socat glib2 fontconfig at sudo gcc git curl unzip
  # audio / media
  pipewire wireplumber pipewire-pulseaudio pulseaudio-utils playerctl mpv mpv-mpris yt-dlp
  # hardware / network / power
  brightnessctl NetworkManager bluez util-linux dbus dbus-tools tuned procps-ng
  # python helpers (bluetooth agent, kvantum generator, pywal)
  python3 python3-dbus python3-gobject python3-pip python3-pillow
  # Qt / KDE integration layer (runs without Plasma)
  qt6-qtdeclarative qt6-qtsvg qt6-qt5compat qt6-qttools kde-cli-tools plasma-integration
  kf6-kded kf6-kglobalaccel breeze-gtk gtk4 libadwaita mate-polkit konsole dolphin kdeconnect
  # calendar widget
  khal vdirsyncer python3-holidays
)
OPT_PKGS=( wayvnc librsvg2-tools qt6ct kvantum papirus-icon-theme breeze-icon-theme breeze-cursor-theme bibata-cursor-themes )
HYPR_PKGS=( hyprland xdg-desktop-portal-hyprland xdg-desktop-portal xorg-x11-server-Xwayland )
QS_PKGS=( quickshell )

declare -A AVAIL=()
P_NEW=() P_UPG=() P_MISS_REQ=() P_MISS_OPT=()

pkg_installed() { rpm -q --whatprovides "$1" >/dev/null 2>&1; }

# fill AVAIL[name]=1 for every given name some enabled repo can supply
query_available() {
  local names=("$@") n out
  out="$(dnf repoquery -q --available --queryformat '%{name}\n' "${names[@]}" 2>>"$LOG" | sort -u)"
  for n in "${names[@]}"; do
    if grep -qxF "$n" <<<"$out"; then AVAIL[$n]=1
    elif [[ -n "$(dnf repoquery -q --available --whatprovides "$n" 2>>"$LOG" | head -n1)" ]]; then AVAIL[$n]=1
    fi
  done
}

# newest version a repo offers for a package name (empty if none)
repo_version() {
  local n="$1" line
  line="$(dnf repoquery -q --available "$n" 2>>"$LOG" | sort -V | tail -n1)"
  [[ -z $line ]] && return 0
  line="${line#"$n"-}"; line="${line#*:}"; printf '%s' "${line%%-*}"
}

installed_hyprland_version() {
  command -v Hyprland >/dev/null 2>&1 || return 0
  Hyprland --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1
}

ensure_copr_cmd() {
  dnf copr --help >/dev/null 2>&1 && return 0
  run "install dnf copr plugin" sudo dnf install -y dnf5-plugins || run "install dnf copr plugin" sudo dnf install -y dnf-plugins-core
  dnf copr --help >/dev/null 2>&1
}

enable_copr() {
  local proj="$1" ok_p=0 t
  for t in "${TRUSTED_COPRS[@]}"; do [[ $t == "$proj" ]] && ok_p=1; done
  ((ok_p)) || { bad "refusing to enable untrusted COPR '$proj'"; return 1; }
  ((NO_COPR)) && { info "--no-copr given: not enabling $proj"; return 1; }
  if dnf copr list 2>/dev/null | grep -qF "$proj"; then ok "COPR $proj already enabled"; return 0; fi
  ((CHECK)) && { info "would enable COPR $proj"; return 0; }
  info "Fedora's repos do not provide a usable build, so the trusted COPR $proj is needed."
  info "  (maintainer-run third-party repo: https://copr.fedorainfracloud.org/coprs/$proj/)"
  ask "Enable COPR $proj?" y || { warn "COPR $proj declined"; return 1; }
  ensure_copr_cmd || { add_issue ERROR "dnf copr command unavailable" "Install it: sudo dnf install dnf5-plugins   (or dnf-plugins-core on dnf4)"; return 1; }
  if run "enable COPR $proj" sudo dnf copr enable -y "$proj"; then ok "enabled COPR $proj"
  else add_issue ERROR "Could not enable COPR $proj" "It may have no build for fedora-$FEDORA_VER yet. Check https://copr.fedorainfracloud.org/coprs/$proj/ . If missing, install that tool another way (see package hints below) and re-run."; return 1; fi
}

plan_packages() {
  step "Searching repositories"
  run "dnf makecache" sudo dnf makecache -y || add_issue WARN "dnf makecache failed" "Network/mirror problem? Try: sudo dnf clean all && sudo dnf makecache"

  # --- Hyprland (needs >= $MIN_HYPRLAND, Lua config)
  local inst_h avail_h
  inst_h="$(installed_hyprland_version)"
  avail_h="$(repo_version hyprland)"
  HYPR_OK=0
  if [[ -n $inst_h ]] && ver_ge "$inst_h" "$MIN_HYPRLAND"; then HYPR_OK=1; ok "Hyprland $inst_h installed"
  elif [[ -n $avail_h ]] && ver_ge "$avail_h" "$MIN_HYPRLAND"; then HYPR_OK=1; ok "Hyprland $avail_h available from the enabled repos"
  else
    info "Hyprland >= $MIN_HYPRLAND not found (installed: ${inst_h:-none}, repos: ${avail_h:-none}); trying the trusted COPR"
    if enable_copr "sdegler/hyprland"; then
      ((CHECK)) || run "dnf makecache" sudo dnf makecache -y
      avail_h="$(repo_version hyprland)"
      if [[ -n $avail_h ]] && ver_ge "$avail_h" "$MIN_HYPRLAND"; then HYPR_OK=1; ok "Hyprland $avail_h available from sdegler/hyprland"; fi
    fi
    if ((!HYPR_OK)) && ! ((CHECK && !NO_COPR)); then
      : >"$LAST_OUT"; RC=0
      add_issue ERROR "Hyprland >= $MIN_HYPRLAND is not available for Fedora $FEDORA_VER" \
        "This config uses Hyprland's Lua API (0.55+). Install Hyprland yourself (https://wiki.hypr.land/Getting-Started/Installation/), make sure 'Hyprland --version' shows >= $MIN_HYPRLAND, then re-run ./install.sh. The Hyprland packages were NOT installed to avoid an incompatible version."
    fi
  fi

  # --- Quickshell
  QS_OK=0
  if command -v qs >/dev/null 2>&1 && pkg_installed quickshell; then QS_OK=1; ok "quickshell installed"
  elif [[ -n "$(repo_version quickshell)" ]]; then QS_OK=1; ok "quickshell available from the enabled repos"
  else
    info "quickshell not in the enabled repos; trying the trusted COPR"
    if enable_copr "errornointernet/quickshell"; then
      ((CHECK)) || run "dnf makecache" sudo dnf makecache -y
      [[ -n "$(repo_version quickshell)" ]] && { QS_OK=1; ok "quickshell available from errornointernet/quickshell"; }
    fi
    if ((!QS_OK)) && ! ((CHECK && !NO_COPR)); then
      : >"$LAST_OUT"; RC=0
      add_issue ERROR "quickshell is not available for Fedora $FEDORA_VER" \
        "Install the backend yourself: see https://quickshell.org (build from source needs Qt6 dev packages + linux-pam-devel for the lock screen), then re-run ./install.sh."
    fi
  fi

  # --- everything else: classify installed / new / missing
  local all=("${REQ_PKGS[@]}" "${OPT_PKGS[@]}") p
  ((HYPR_OK)) && all+=("${HYPR_PKGS[@]}")
  ((QS_OK)) && all+=("${QS_PKGS[@]}")
  local todo=()
  for p in "${all[@]}"; do pkg_installed "$p" && P_UPG+=("$p") || todo+=("$p"); done
  ((${#todo[@]})) && query_available "${todo[@]}"
  for p in "${todo[@]}"; do
    if [[ -n ${AVAIL[$p]:-} ]]; then P_NEW+=("$p")
    elif printf '%s\n' "${OPT_PKGS[@]}" | grep -qxF "$p"; then P_MISS_OPT+=("$p")
    else P_MISS_REQ+=("$p"); fi
  done
  info "${#P_UPG[@]} already installed, ${#P_NEW[@]} to install, ${#P_MISS_REQ[@]} required + ${#P_MISS_OPT[@]} optional not found in any enabled repo"
  ((${#P_NEW[@]})) && info "to install: ${P_NEW[*]}"
  ((${#P_MISS_REQ[@]})) && warn "required but not found: ${P_MISS_REQ[*]}"
  ((${#P_MISS_OPT[@]})) && info "optional, not found (skipped): ${P_MISS_OPT[*]}"
  return 0
}

hint_for() {
  case "$1" in
    hyprland|xdg-desktop-portal-hyprland) echo "Hyprland packages come from the sdegler/hyprland COPR on Fedora, or build per https://wiki.hypr.land/Getting-Started/Installation/ ." ;;
    quickshell) echo "Not in Fedora's repos: errornointernet/quickshell COPR, or build from source (https://quickshell.org). Qt6 version mismatches between COPR and Fedora are a known cause of failures." ;;
    cliphist) echo "Install a release binary from https://github.com/sentriz/cliphist (put it in ~/.local/bin)." ;;
    yt-dlp) echo "mpv needs it to play YouTube/radio URLs (music_target, Radio page); without it mpv quits right after starting. Check: dnf search yt-dlp" ;;
    mpv-mpris) echo "Provides the MPRIS plugin for mpv; if missing, music controls in the shell will not work. Check: dnf search mpris" ;;
    wayvnc) echo "Optional (VNC toggle on Alt+V). Safe to skip." ;;
    bibata-cursor-themes) echo "Optional cursor theme; set another cursor in hyprland.lua or install Bibata from https://github.com/ful1e5/Bibata_Cursor ." ;;
    *) echo "Check the name with: dnf search $1   - and see which package provides it: dnf provides '*/$1'. If your Fedora release renamed it, install the replacement manually." ;;
  esac
}

install_packages() {
  step "Installing / upgrading packages"
  local p lvl
  if ((${#P_NEW[@]})); then
    info "installing ${#P_NEW[@]} package(s); this can take a few minutes (details in the log)"
    if run "dnf install (batch)" sudo dnf install -y "${P_NEW[@]}"; then ok "installed ${#P_NEW[@]} package(s)"
    else
      warn "batch install failed (exit $RC); retrying one by one to find the culprit"
      for p in "${P_NEW[@]}"; do
        if run "dnf install $p" sudo dnf install -y "$p"; then ok "$p"
        else
          lvl=ERROR; printf '%s\n' "${OPT_PKGS[@]}" | grep -qxF "$p" && lvl=WARN
          add_issue "$lvl" "dnf could not install '$p'" "$(hint_for "$p")"
        fi
      done
    fi
  else info "nothing new to install"; fi

  if ((!NO_UPGRADE)) && ((${#P_UPG[@]})); then
    if run "dnf upgrade (installed tools)" sudo dnf upgrade -y --refresh "${P_UPG[@]}"; then ok "upgraded installed tools (if newer builds existed)"
    else add_issue WARN "dnf upgrade of installed tools failed" "Try manually: sudo dnf upgrade --refresh   - look for dependency conflicts in the log."; fi
  fi
  for p in "${P_MISS_REQ[@]}"; do : >"$LAST_OUT"; RC=0; add_issue ERROR "'$p' not found in any enabled repository" "$(hint_for "$p")"; done
  return 0
}

pip_tools() {
  step "Python tools (PyPI)"
  if ! python3 -m pip --version >/dev/null 2>&1; then
    : >"$LAST_OUT"; RC=0; add_issue ERROR "pip is not available" "Install it: sudo dnf install python3-pip   then re-run."; return
  fi
  # pywal: not packaged for Fedora. Exact PyPI name 'pywal'.
  if command -v wal >/dev/null 2>&1 && ! python3 -m pip show pywal >/dev/null 2>&1; then
    ok "pywal installed (system package)"
  else
    if run "pip pywal" python3 -m pip install --user --upgrade pywal; then ok "pywal $(python3 -m pip show pywal 2>/dev/null | awk '/^Version/{print $2}')"
    else add_issue ERROR "pywal could not be installed with pip" "If the error says 'externally-managed-environment', use: pipx install pywal   (sudo dnf install pipx). Then check 'wal --version' and that ~/.local/bin is in PATH."; fi
  fi
  if ! python3 -c 'import holidays' >/dev/null 2>&1; then
    run "pip holidays" python3 -m pip install --user holidays && ok "holidays" || add_issue WARN "python 'holidays' missing" "The calendar popup's holiday marks need it: python3 -m pip install --user holidays"
  fi
  if command -v vdirsyncer >/dev/null 2>&1 && ! python3 -c 'import aiohttp_oauthlib' >/dev/null 2>&1; then
    if ask "vdirsyncer lacks Google support. Install 'vdirsyncer[google]' with pip (--user)?" y; then
      run "pip vdirsyncer[google]" python3 -m pip install --user "vdirsyncer[google]" && ok "vdirsyncer[google]" || add_issue WARN "vdirsyncer[google] failed" "Only needed for Google Calendar sync: python3 -m pip install --user 'vdirsyncer[google]'"
    fi
  fi
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "~/.local/bin is not in PATH; pip-installed tools (wal) will not be found until it is" ;; esac
  return 0
}

enable_services() {
  step "System services"
  local u
  for u in atd tuned bluetooth; do
    if systemctl list-unit-files "$u.service" 2>/dev/null | grep -q "^$u.service"; then
      if systemctl is-enabled --quiet "$u" 2>/dev/null && systemctl is-active --quiet "$u" 2>/dev/null; then ok "$u already running"
      else run "enable $u" sudo systemctl enable --now "$u" && ok "enabled $u" || add_issue WARN "could not enable $u" "Try: sudo systemctl enable --now $u ; journalctl -u $u -b"; fi
    else info "$u.service not present (skipped)"; fi
  done
  return 0
}

# ---------- 3. fonts, wallpapers --------------------------------------------
install_assets() {
  step "Fonts and wallpapers"
  # fonts ship as loose .ttf/.otf/.woff2 files and/or .zip archives (Satoshi.zip, led-counter.zip, ...)
  local fd="$HOME/.local/share/fonts/hyprquickshellsx" fstamp="$STATE_DIR/fonts.sha256" changed=0 f h name
  if [[ -d $FONTS_SRC ]] && [[ -n "$(find "$FONTS_SRC" -type f 2>/dev/null | head -n1)" ]]; then
    mkdir -p "$fd"
    declare -A FSEEN=()
    [[ -f $fstamp ]] && while IFS=$'\t' read -r h name; do [[ -n $name ]] && FSEEN[$name]=$h; done <"$fstamp"
    while IFS= read -r -d '' f; do
      name="$(basename "$f")"; h="$(sha256sum "$f" | cut -d' ' -f1)"
      if [[ ${FSEEN[$name]:-} == "$h" ]] && find "$fd" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.woff2' \) 2>/dev/null | grep -q .; then continue; fi
      changed=1
      ((CHECK)) && { info "would install font: $name"; continue; }
      case "${name,,}" in
        *.zip)
          if ! command -v unzip >/dev/null 2>&1; then : >"$LAST_OUT"; RC=0; add_issue ERROR "cannot unpack $name: unzip is missing" "Install unzip with your package manager, then re-run ./install.sh"; continue; fi
          if run "unzip $name" unzip -oq "$f" -d "$fd/${name%.*}"; then
            if find "$fd/${name%.*}" -type f \( -iname '*.ttf' -o -iname '*.otf' -o -iname '*.woff2' \) | grep -q .; then ok "font pack $name"; FSEEN[$name]="$h"
            else add_issue WARN "$name contains no .ttf/.otf/.woff2 files" "Open the zip and check it really is a font archive; fonts shown in the shell will fall back otherwise."; fi
          else add_issue ERROR "could not unpack $name" "Is the zip corrupt (re-download/re-export it)? Test: unzip -t '$f'"; fi ;;
        *.ttf|*.otf|*.woff2) cp -f "$f" "$fd/" && { ok "font $name"; FSEEN[$name]="$h"; } ;;
      esac
    done < <(find "$FONTS_SRC" -maxdepth 2 -type f \( -iname '*.zip' -o -iname '*.ttf' -o -iname '*.otf' -o -iname '*.woff2' \) -print0 | sort -z)
    if ((changed)) && ! ((CHECK)); then
      for name in "${!FSEEN[@]}"; do printf '%s\t%s\n' "${FSEEN[$name]}" "$name"; done >"$fstamp"
      if command -v fc-cache >/dev/null 2>&1; then
        run "fc-cache" fc-cache -f "$fd" && ok "font cache refreshed" || add_issue WARN "fc-cache failed" "Run: fc-cache -fv"
      else warn "fc-cache not found (install fontconfig); fonts may not show until the cache is rebuilt"; fi
    elif ((!changed)); then ok "fonts up to date"; fi
  else warn "no fonts/ folder in the repo; the shell font (Satoshi) must be installed manually into ~/.local/share/fonts"; fi

  local wd="$HOME/Downloads/WALLPAPERS"
  mkdir -p "$HOME/Downloads/MISC/MUSIC" 2>/dev/null
  if [[ -d $WALL_SRC ]] && ! ((CHECK)); then
    mkdir -p "$wd"; cp -n "$WALL_SRC"/* "$wd"/ 2>/dev/null
    ok "wallpapers available in $wd (existing files never overwritten)"
  fi
  return 0
}

# ---------- 4. config sync ---------------------------------------------------
declare -A MAN=() MAN_NEW=()
MANIFEST="$STATE_DIR/manifest.tsv"
BACKUP_DIR="$HOME/.config-backups/hyprquickshellsx/$(date +%Y%m%d-%H%M%S)"
CONFLICTS=()
HOME_ESC="$(printf '%s' "$HOME" | sed 's/[&#\\]/\\&/g')"

excluded() { case "$1" in quickshell/.qmlcache/*|quickshell/icons/.last_scan|quickshell/icons/.app_cache.tsv|*.lock|hypr/volume-osd|quickshell/icons/.icon_index.tsv|gtk-3.0/bookmarks|*/__pycache__/*|*.pyc|*.upstream-new|.git/*|*/.git/*) return 0 ;; esac; return 1; }
user_owned() { case "$1" in quickshell/state/*|khal/config) return 0 ;; esac; return 1; }

hash_file() { # rel file  (the wallpaper line is yours, so it is ignored when comparing)
  if [[ $1 == hypr/shellwrapper.sh ]]; then sed -E 's/^WALLPAPER=.*/WALLPAPER=@/' "$2" | sha256sum | cut -d' ' -f1
  else sha256sum "$2" | cut -d' ' -f1; fi
}

expand_home() { local v="$1"; v="${v//\$\{HOME\}/$HOME}"; v="${v//\$HOME/$HOME}"; printf '%s' "${v/#\~/$HOME}"; }

keep_wallpaper_line() { # out dest   (WALLPAPER may be written as "$HOME/..." or an absolute path)
  local out="$1" dest="$2" cur="" val first
  [[ -f $dest ]] && cur="$(grep -m1 '^WALLPAPER=' "$dest" 2>/dev/null || true)"
  if [[ -n $cur ]]; then
    val="${cur#WALLPAPER=}"; val="${val//\"/}"; val="$(expand_home "$val")"
    [[ -f $val ]] || cur=""
  fi
  if [[ -z $cur ]]; then
    val="$(grep -m1 '^WALLPAPER=' "$out" | sed -E 's/^WALLPAPER=//; s/"//g')"; val="$(expand_home "$val")"
    if [[ ! -f $val ]]; then
      first="$(find "$HOME/Downloads/WALLPAPERS" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) 2>/dev/null | sort | head -n1)"
      [[ -n $first ]] && cur="WALLPAPER=\"$first\""
    fi
  fi
  [[ -n $cur ]] && { NEWLINE="$cur" awk '/^WALLPAPER=/ && !d {print ENVIRON["NEWLINE"]; d=1; next} {print}' "$out" >"$out.2" && mv "$out.2" "$out"; }
  return 0
}

make_candidate() { # rel src out dest
  local rel="$1" src="$2" out="$3" dest="$4"
  if ! user_owned "$rel" && grep -Iq . "$src" 2>/dev/null; then
    sed -E "s#/home/[A-Za-z0-9._-]+/#${HOME_ESC}/#g" "$src" >"$out"      # paths of the author's home -> this home
  else cp "$src" "$out"; fi
  chmod --reference="$src" "$out" 2>/dev/null
  [[ $rel == hypr/shellwrapper.sh ]] && keep_wallpaper_line "$out" "$dest"
  return 0
}

backup_file() { # rel
  local rel="$1"
  [[ -e $CONFIG/$rel ]] || return 0
  mkdir -p "$BACKUP_DIR/$(dirname "$rel")" && cp -p "$CONFIG/$rel" "$BACKUP_DIR/$rel"
}

sync_config() {
  step "Syncing config  ($CONF_SRC -> $CONFIG)"
  [[ -f $MANIFEST ]] && while IFS=$'\t' read -r h r; do [[ -n $r ]] && MAN[$r]=$h; done <"$MANIFEST"
  local rel src dst cand cur_h new_h n_new=0 n_upd=0 n_same=0 n_keep=0 n_own=0 n_conf=0 n_force=0
  cand="$TMPD/cand"
  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    excluded "$rel" && continue
    src="$CONF_SRC/$rel"; dst="$CONFIG/$rel"
    if user_owned "$rel"; then
      if [[ -e $dst ]]; then ((n_own++)); continue; fi
    fi
    make_candidate "$rel" "$src" "$cand" "$dst"
    new_h="$(hash_file "$rel" "$cand")"
    if [[ ! -e $dst ]]; then
      ((n_new++)); ((CHECK)) || { mkdir -p "$(dirname "$dst")"; install -m "$(stat -c %a "$src")" "$cand" "$dst"; }
      user_owned "$rel" || MAN_NEW[$rel]="$new_h"
      continue
    fi
    cur_h="$(hash_file "$rel" "$dst")"
    if [[ $cur_h == "$new_h" ]]; then
      ((n_same++)); MAN_NEW[$rel]="$new_h"; rm -f "$dst.upstream-new" 2>/dev/null
    elif [[ ${MAN[$rel]:-} == "$cur_h" ]]; then            # you never touched it: safe to update
      ((n_upd++)); MAN_NEW[$rel]="$new_h"
      ((CHECK)) || { backup_file "$rel"; install -m "$(stat -c %a "$src")" "$cand" "$dst"; rm -f "$dst.upstream-new"; }
    elif ((FORCE)); then
      ((n_force++)); MAN_NEW[$rel]="$new_h"
      ((CHECK)) || { backup_file "$rel"; install -m "$(stat -c %a "$src")" "$cand" "$dst"; rm -f "$dst.upstream-new"; }
    else                                                    # you changed it AND upstream differs: keep yours
      ((n_conf++)); CONFLICTS+=("$rel"); [[ -n ${MAN[$rel]:-} ]] && MAN_NEW[$rel]="${MAN[$rel]}"
      ((CHECK)) || install -m "$(stat -c %a "$src")" "$cand" "$dst.upstream-new"
    fi
  done < <(cd "$CONF_SRC" && find . -type f -print0 | sort -z)

  ok "new: $n_new   updated: $n_upd   unchanged: $n_same   your settings kept: $n_own   overwritten (--force): $n_force"
  if ((n_conf)); then
    warn "$n_conf file(s) differ from upstream AND were edited on your side, so they were left alone:"
    printf '      %s\n' "${CONFLICTS[@]}"
    info "the new upstream version of each sits next to it as <file>.upstream-new (diff it, merge what you want)."
    info "to take upstream for everything instead:  ./install.sh --config-only --force   (backs up first)"
  fi
  if ((!CHECK)); then
    mkdir -p "$STATE_DIR"
    for rel in "${!MAN_NEW[@]}"; do printf '%s\t%s\n' "${MAN_NEW[$rel]}" "$rel"; done | sort -k2 >"$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
    [[ -d $BACKUP_DIR ]] && { info "backup of replaced files: $BACKUP_DIR"
      ls -1dt "$HOME/.config-backups/hyprquickshellsx"/*/ 2>/dev/null | tail -n +6 | while read -r old; do rm -rf -- "$old"; done; }
    find "$CONFIG/hypr" "$CONFIG/quickshell/scripts" -type f \( -name '*.sh' -o -name '*.py' \) -exec chmod +x {} + 2>/dev/null
  fi
  return 0
}

# ---- safety net: user state (quickshell/state) must survive every run ----------
STATE_SNAP=""; STATE_BEFORE="$TMPD/state.before"
snapshot_state() {
  ((CHECK)) && return 0
  local sd="$CONFIG/quickshell/state" bd="$HOME/.config-backups/hyprquickshellsx"
  [[ -d $sd ]] || return 0
  mkdir -p "$bd"
  STATE_SNAP="$bd/state-$(date +%Y%m%d-%H%M%S).tar.gz"
  if tar -C "$CONFIG/quickshell" -czf "$STATE_SNAP" state 2>>"$LOG"; then
    ( cd "$sd" && find . -type f -printf '%s\t%p\n' | sort -k2 ) >"$STATE_BEFORE"
    ok "state snapshot: $STATE_SNAP"
    ls -1t "$bd"/state-*.tar.gz 2>/dev/null | tail -n +11 | while read -r old; do rm -f -- "$old"; done
  else warn "could not snapshot state (continuing; state files are never overwritten by this script)"; STATE_SNAP=""; fi
  return 0
}
verify_state() {
  ((CHECK)) && return 0
  [[ -n $STATE_SNAP && -s $STATE_BEFORE ]] || return 0
  local sd="$CONFIG/quickshell/state" size path lost=() now
  while IFS=$'\t' read -r size path; do
    [[ -z $path ]] && continue
    now=-1; [[ -f $sd/$path ]] && now="$(stat -c %s "$sd/$path")"
    if [[ $now -lt 0 ]] || { [[ $size -gt 0 ]] && [[ $now -eq 0 ]]; }; then lost+=("${path#./}"); fi
  done <"$STATE_BEFORE"
  if ((${#lost[@]})); then
    local f restored=0
    for f in "${lost[@]}"; do tar -C "$CONFIG/quickshell" -xzf "$STATE_SNAP" "state/$f" 2>>"$LOG" && restored=$((restored + 1)); done
    : >"$LAST_OUT"; RC=0
    add_issue ERROR "${#lost[@]} state file(s) went missing or empty during the run; restored $restored from the snapshot" "Snapshot: $STATE_SNAP . Affected: ${lost[*]} . Please report this with the log: $LOG"
  else ok "state intact (${STATE_BEFORE##*/}: every file still present and non-empty)"; fi
  return 0
}

post_config() {
  ((CHECK)) && return 0
  step "Finishing touches"
  # volume OSD: the shipped binary is built on another machine, so compile it here
  local csrc="$CONFIG/hypr/volume-osd.c" cbin="$CONFIG/hypr/volume-osd"
  if [[ -f $csrc ]] && { [[ ! -x $cbin ]] || [[ $csrc -nt $cbin ]] || ((FORCE)); }; then
    if command -v gcc >/dev/null 2>&1; then
      run "compile volume-osd" gcc -O2 -Wall -o "$cbin" "$csrc" && ok "compiled volume-osd" || add_issue ERROR "volume-osd failed to compile" "Needs gcc + glibc headers (Fedora: sudo dnf install gcc glibc-devel; Arch: sudo pacman -S gcc). The volume popup will not show until it builds: gcc -O2 -Wall -o ~/.config/hypr/volume-osd ~/.config/hypr/volume-osd.c"
    else : >"$LAST_OUT"; RC=0; add_issue WARN "gcc missing, volume-osd not built" "Install gcc, then re-run ./install.sh --config-only (the volume popup will not show until it is built)."; fi
  else ok "volume-osd up to date"; fi
  # GTK file-chooser bookmarks need absolute URIs, so they are generated for this user instead of shipped
  if [[ ! -e $CONFIG/gtk-3.0/bookmarks ]]; then
    mkdir -p "$CONFIG/gtk-3.0"
    for d in Music Pictures Videos Documents Downloads; do
      u="$HOME/$d"; command -v xdg-user-dir >/dev/null 2>&1 && u="$(xdg-user-dir "${d^^}" 2>/dev/null || echo "$HOME/$d")"
      [[ -d $u ]] && printf 'file://%s\n' "$u"
    done >"$CONFIG/gtk-3.0/bookmarks"
    ok "generated gtk-3.0/bookmarks for $HOME"
  fi
  # stale caches / saved paths (also fixes Theme presets) after a move between machines
  if [[ -x $CONFIG/quickshell/scripts/portable-refresh.sh ]]; then
    run "portable-refresh" bash "$CONFIG/quickshell/scripts/portable-refresh.sh" && ok "portable-refresh ran" || add_issue WARN "portable-refresh.sh failed" "Run it by hand to see the error: bash ~/.config/quickshell/scripts/portable-refresh.sh"
  fi
  # live session: reload Hyprland; Quickshell reloads edited QML files by itself
  if pgrep -x Hyprland >/dev/null 2>&1 && command -v hyprctl >/dev/null 2>&1; then
    run "hyprctl reload" hyprctl reload && ok "Hyprland config reloaded (Quickshell picks up QML changes live)" || warn "hyprctl reload failed (not inside the Hyprland session?)"
  fi
  return 0
}

# ---------- 5. passwordless sudo (opt-in) -----------------------------------
setup_sudoers() {
  ((CHECK)) && return 0
  step "Passwordless sudo for the shell's toggles"
  local mode="$SUDOERS_MODE" user tgt="/etc/sudoers.d/hyprquickshellsx" f="$TMPD/sudoers" b
  [[ $mode == skip ]] && { info "skipped (--sudoers skip)"; return; }
  command -v sudo >/dev/null 2>&1 || { warn "sudo not installed; skipping sudoers"; return; }
  user="$(id -un)"; [[ $user =~ ^[a-z_][a-z0-9_-]*$ ]] || { warn "unusual user name '$user'; skipping sudoers"; return; }
  if [[ -z $mode ]]; then
    if ((ASSUME_YES)) || [[ ! -t 0 ]]; then info "not changing sudoers (pass --sudoers narrow|full to do it unattended)"; return; fi
    cat <<EOF
  The turbo / governor / tuned toggles and power actions need 'sudo' without a password.
    [n] narrow (recommended): only those exact commands and 3 exact files
    [f] full: the broad rule from the README. It includes unrestricted tee and sed as root,
        which is effectively root for any program running as you. Only if you accept that.
    [s] skip (those toggles will just ask for / fail without a password)
EOF
    read -r -p "  choice [n/f/s] " b
    case "${b:-n}" in n|N) mode=narrow ;; f|F) mode=full ;; *) mode=skip ;; esac
  fi
  [[ $mode == skip ]] && { info "skipped"; return; }
  p() { command -v "$1" 2>/dev/null || echo "$2"; }
  local SYSTEMCTL TUNED TEE SYSCTL SED AT ATRM
  SYSTEMCTL="$(p systemctl /usr/bin/systemctl)"; TUNED="$(p tuned-adm /usr/sbin/tuned-adm)"; TEE="$(p tee /usr/bin/tee)"
  SYSCTL="$(p sysctl /usr/sbin/sysctl)"; SED="$(p sed /usr/bin/sed)"; AT="$(p at /usr/bin/at)"; ATRM="$(p atrm /usr/bin/atrm)"
  {
    echo "# managed by hyprquickshellsx install.sh ($mode)"
    if [[ $mode == narrow ]]; then
      echo "Cmnd_Alias HQSX = $SYSTEMCTL suspend, $SYSTEMCTL poweroff, $SYSTEMCTL reboot, $SYSTEMCTL reload systemd-logind, $TUNED profile *, $TEE /sys/devices/system/cpu/intel_pstate/no_turbo, $TEE /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor"
      echo "$user ALL=(root) NOPASSWD: HQSX"
    else
      echo "$user ALL=(ALL) NOPASSWD: $SYSTEMCTL suspend, $SYSTEMCTL poweroff, $SYSTEMCTL reboot, $TUNED profile *, $TEE, $SYSCTL, $SED, $AT, $ATRM"
    fi
  } >"$f"
  if ! run "visudo check" sudo visudo -cf "$f"; then add_issue ERROR "generated sudoers rules failed validation (not installed)" "Nothing was changed. Report this with the log: $LOG"; return; fi
  if run "install sudoers" sudo install -o root -g root -m 0440 "$f" "$tgt" && run "visudo full check" sudo visudo -c; then ok "installed $tgt ($mode rules)"
  else run "remove bad sudoers" sudo rm -f "$tgt"; add_issue ERROR "could not install $tgt" "Nothing was left behind. Add the rules by hand with: sudo visudo -f $tgt   (see README 'Sudo / Permissions')"; fi
  [[ $mode == narrow ]] && info "battery charge-limit writes use their own one-file rule (the Battery settings page shows the exact line)."
  return 0
}

# ---------- 6. verification --------------------------------------------------
verify() {
  step "Verifying"
  local c miss=0
  for c in Hyprland hyprctl qs rofi wal grim wl-copy wl-paste cliphist playerctl wpctl pactl nmcli bluetoothctl rfkill brightnessctl mpv yt-dlp jq khal notify-send tuned-adm at; do
    if command -v "$c" >/dev/null 2>&1; then :; else warn "command not found: $c"; miss=1; fi
  done
  ((!miss)) && ok "all required commands are on PATH"
  local hv; hv="$(installed_hyprland_version)"
  if [[ -n $hv ]]; then ver_ge "$hv" "$MIN_HYPRLAND" && ok "Hyprland $hv" || { : >"$LAST_OUT"; RC=0; add_issue ERROR "Hyprland $hv is older than $MIN_HYPRLAND" "hyprland.lua needs the Lua config API of $MIN_HYPRLAND+; upgrade Hyprland."; }; fi
  if command -v qs >/dev/null 2>&1; then
    if find /usr/lib64/qt6/qml/Quickshell/Services /usr/lib/qt6/qml/Quickshell/Services -maxdepth 1 -iname 'Pam*' 2>/dev/null | grep -q .; then ok "Quickshell has the PAM module (lock screen)"
    else : >"$LAST_OUT"; RC=0; add_issue WARN "Quickshell PAM module not found" "The lock screen needs Quickshell built with PAM (linux-pam-devel at build time). Use the COPR build or build from source with PAM enabled."; fi
  fi
  fc-list 2>/dev/null | grep -qi satoshi || warn "Satoshi font not detected by fontconfig (shell falls back to another font)"
  return 0
}

summary() {
  echo; printf '%s==================== Summary ====================%s\n' "$B" "$N"
  local e=0 w=0 rec lvl title hint code tailtxt
  for rec in "${ISSUES[@]:-}"; do
    [[ -z $rec ]] && continue
    IFS=$'\x1f' read -r lvl _ <<<"$rec"
    if [[ $lvl == ERROR ]]; then e=$((e + 1)); else w=$((w + 1)); fi
  done
  if ((e + w == 0)); then printf '%sEverything went through cleanly.%s\n' "$G" "$N"
  else
    printf '%s%d error(s), %d warning(s):%s\n' "$Y" "$e" "$w" "$N"
    for rec in "${ISSUES[@]}"; do
      IFS=$'\x1f' read -r lvl title hint code tailtxt <<<"$rec"
      printf '\n %s[%s]%s %s  (%s)\n' "$([[ $lvl == ERROR ]] && printf %s "$R" || printf %s "$Y")" "$lvl" "$N" "$title" "$code"
      [[ -n $hint ]] && printf '   fix: %s\n' "$hint"
      [[ -n $tailtxt ]] && { printf '   last output:\n'; printf '%s' "$tailtxt" | tr '\036' '\n'; echo; }
    done
  fi
  echo; echo "Full log (commands, exit codes, output): $LOG"
  if ((CHECK)); then echo "That was a dry run (--check). Nothing was changed."
  else echo "Next: log out and back in (or run 'hyprctl reload'). Re-run ./install.sh any time to upgrade."; fi
  ((e)) && return 1 || return 0
}

# ---------- main -------------------------------------------------------------
# Missing tools or an unsupported distro must never block the config copy.
set +u   # an unset variable in the tool check must never abort the run
if ((TOOLS_ONLY)); then tool_report; echo; echo "Log: $LOG"; exit 0; fi
self_update
tool_report || true
check_wheel || true
check_vdirsyncer || true

if ((!CONFIG_ONLY)); then
  # shellcheck disable=SC1091
  . /etc/os-release 2>/dev/null
  if [[ ${ID:-} != fedora ]] || ! command -v dnf >/dev/null 2>&1; then
    warn "Automatic package install is Fedora (dnf) only; detected '${PRETTY_NAME:-unknown}'."
    info "Copying configs only. Install the tools yourself; run ./install.sh --tools to see what's missing."
    ((PKG_ONLY)) && exit 1
    CONFIG_ONLY=1
  else
    FEDORA_VER="${VERSION_ID:-?}"
    [[ $FEDORA_VER != 44 ]] && warn "written for Fedora 44, you are on $FEDORA_VER (continuing)"
    if ((!CHECK)); then
      step "Authentication"
      if sudo -v; then
        ( while true; do sleep 50; sudo -n true 2>/dev/null || exit; done ) & KEEPALIVE_PID=$!
        ok "sudo ready"
      else
        warn "sudo unavailable; skipping package installation, copying configs only"
        ((PKG_ONLY)) && exit 1
        CONFIG_ONLY=1
      fi
    fi
    if ((!CONFIG_ONLY)); then
      plan_packages
      if ((!CHECK)); then install_packages; pip_tools; enable_services; fi
    fi
  fi
fi

if ((!PKG_ONLY)); then
  snapshot_state
  install_assets
  sync_config
  post_config
  verify_state
  ((CONFIG_ONLY)) || setup_sudoers
fi
((CHECK)) || ((CONFIG_ONLY)) || verify
summary
