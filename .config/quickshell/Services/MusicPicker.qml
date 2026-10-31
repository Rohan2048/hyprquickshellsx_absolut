pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// MusicPicker.qml — backend for Popups/MusicPicker.qml (text-only file picker).
//
// Zero idle cost: nothing runs until the picker is opened. One short-lived
// `bash` per directory listing, one detached `bash` per selection.
//
// Contract with autoplay.sh:
//   The chosen file/folder path is written (no trailing newline) to
//   ~/.config/quickshell/state/music_target and then `playCommand` is run.
//   autoplay.sh reads that file instead of its hardcoded PLAY directory.
Singleton {
    id: root

    // Script started after a selection is written. Set "" to only write the
    // state file and let your own keybind/script start playback.
    property string playCommand: Quickshell.env("HOME") + "/.config/hypr/autoplay.sh"

    // mpv's IPC socket (same one autoplay.sh passes via --input-ipc-server).
    // If mpv is already running, the pick is sent to it with `loadfile ... replace`
    // so playback switches without killing/restarting the player. If the
    // socket is dead or missing, playCommand is run instead.
    property string mpvSocket: "/tmp/mpvsocket"

    readonly property string folderIcon: "file://" + Quickshell.env("HOME") + "/.config/icons/folder.svg"
    readonly property string musicIcon: "file://" + Quickshell.env("HOME") + "/.config/icons/music-placeholder.png"

    readonly property string stateDir: Quickshell.env("HOME") + "/.config/quickshell/state"
    readonly property string targetFile: stateDir + "/music_target"
    readonly property string lastDirFile: stateDir + "/music_lastdir"

    readonly property var audioExt: ["mp3", "flac", "ogg", "oga", "opus", "wav", "m4a", "aac",
    "wma", "mka", "ape", "alac", "aiff", "wv", "webm", "mp4"]

    property string path: ""        // current directory (resolved)
    property string filter: ""      // type-to-filter text
    property var entries: []        // [{name, isDir, path}] unfiltered
    property var rows: []           // what the UI shows (special rows + filtered entries)
    property bool loading: false
    property string _sig: ""
    property bool mpvRunning: false // true while a local mpv is reachable (enables Stop)
    // ---- Radio page ----
    property string page: "local"
    property var radio: []
    readonly property var radioRows: root.radio.map(function (s) {
        return { kind: "station", label: s.name || s.url, path: s.url, url: s.url,
            thumb: s.thumb || "", isDir: false, loading: !!s.loading }
    })
    readonly property bool radioBusy: root.radio.some(function (s) { return !!s.loading })
    readonly property string radioFile: stateDir + "/radio.json"
    readonly property string thumbDir: stateDir + "/radio-thumbs"
    readonly property string metaScript: Quickshell.env("HOME") + "/.config/quickshell/scripts/radio-meta.py"
    property var _metaQueue: []
    property string _metaUrl: ""

    function togglePage() { root.page = root.page === "radio" ? "local" : "radio" }

    function _saveRadio() {
        radioStore.setText(JSON.stringify(root.radio.map(function (s) {
            return { url: s.url, name: s.name, thumb: s.thumb || "" }
        }), null, 2))
    }

    function addRadio(raw) {
        let u = String(raw).trim()
        if (u === "") return false
            if (!/^[a-z][a-z0-9+.\-]*:\/\//i.test(u)) u = "https://" + u
                if (root.radio.some(function (s) { return s.url === u })) return false
                    const host = u.replace(/^[a-z][a-z0-9+.\-]*:\/\//i, "").split("/")[0]
                    root.radio = root.radio.concat([{ url: u, name: host, thumb: "", loading: true }])
                    root._saveRadio()
                    root._metaQueue.push(u)
                    root._nextMeta()
                    return true
    }

    function removeRadio(i) {
        const s = root.radio[i]
        if (!s) return
            if (s.thumb && s.thumb.indexOf(root.thumbDir + "/") === 0)
                Quickshell.execDetached(["rm", "-f", "--", s.thumb])
                const all = root.radio.slice()
                all.splice(i, 1)
                root.radio = all
                root._saveRadio()
    }

    function _nextMeta() {
        if (_meta.running || root._metaQueue.length === 0) return
            root._metaUrl = root._metaQueue.shift()
            _meta.command = ["python3", root.metaScript, root._metaUrl, root.thumbDir]
            _meta.running = true
    }

    function _applyMeta(url, title, thumb) {
        const all = root.radio.slice()
        for (let i = 0; i < all.length; i++) {
            if (all[i].url === url) {
                all[i] = { url: url, name: title || all[i].name, thumb: thumb || "", loading: false }
                break
            }
        }
        root.radio = all
        root._saveRadio()
    }

    property Process _meta: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text.trim().split("\n").pop())
                    root._applyMeta(root._metaUrl, j.title, j.thumb)
                } catch (e) { root._applyMeta(root._metaUrl, "", "") }
            }
        }
        onExited: {
            if (root.radio.some(function (s) { return s.url === root._metaUrl && s.loading }))
                root._applyMeta(root._metaUrl, "", "")
                root._nextMeta()
        }
    }

    property FileView radioStore: FileView {
        path: root.radioFile
        onLoaded: {
            try {
                const a = JSON.parse(text())
                root.radio = Array.isArray(a) ? a.filter(function (s) { return s && s.url }) : []
            } catch (e) { root.radio = [] }
        }
        onLoadFailed: root.radio = []
    }

    onFilterChanged: _rebuild()

    function _isAudio(name) {
        const i = name.lastIndexOf(".")
        return i > 0 && audioExt.indexOf(name.slice(i + 1).toLowerCase()) >= 0
    }

    function _rebuild() {
        const out = []
        if (root.path !== "") {
            if (root.filter === "") {
                if (root.path !== "/")
                    out.push({ kind: "up", label: "..", path: "", isDir: true })
            }
            const f = root.filter.toLowerCase()
            for (let i = 0; i < root.entries.length; i++) {
                const e = root.entries[i]
                if (f === "" || e.name.toLowerCase().indexOf(f) >= 0)
                    out.push({ kind: "entry", label: e.isDir ? e.name + "/" : e.name, path: e.path, isDir: e.isDir })
            }
        }
        root.rows = out
    }

    // Open at the last played location (falls back to ~/Music, then ~).
    function start() {
        root.checkMpv()
        root.refreshDevices()
        root.filter = ""
        if (root.path === "") root.list("")
            else root.list(root.path)
    }

    // Startup preload: same as start(), but the listing runs at the lowest CPU
    // priority so it can never compete with the shell finishing its login.
    // ---- External storage -------------------------------------------------
    // devices: [{dev, name, size, mountpoint}] for removable/USB filesystems.
    // Empty when nothing external is connected, which is what hides the
    // Internal/device bar in the popup. `watching` (popup visible) turns on a
    // udev monitor, so there is no background cost while the picker is closed.
    property var devices: []
    property bool watching: false
    property bool mounting: false
    property string _pendingDev: ""

    // Mountpoint of the device the current folder is on ("" = internal)
    readonly property string activeMount: {
        for (let i = 0; i < root.devices.length; i++) {
            const m = root.devices[i].mountpoint
            if (m && (root.path === m || root.path.indexOf(m + "/") === 0)) return m
        }
        return ""
    }

    // Bar model: empty unless something external is connected.
    readonly property var deviceTabs: {
        if (root.devices.length === 0) return []
            const t = [{ kind: "internal", label: "Internal", active: root.activeMount === "" }]
            for (let i = 0; i < root.devices.length; i++) {
                const d = root.devices[i]
                t.push({ kind: "device", label: d.name, dev: d.dev, parent: d.parent, mountpoint: d.mountpoint,
                    mounted: d.mountpoint !== "", active: d.mountpoint !== "" && d.mountpoint === root.activeMount })
            }
            return t
    }

    function refreshDevices() {
        _lsblk.running = false
        _lsblk.running = true
    }

    function goInternal() { root.list(Quickshell.env("HOME") + "/Music") }

    // Mounted: just browse it. Not mounted: mount via udisks, then browse.
    function openDevice(tab) {
        if (tab.mounted) { root.list(tab.mountpoint); return }
        if (root.mounting) return
            root.mounting = true
            root._pendingDev = tab.dev
            _mount.command = ["udisksctl", "mount", "-b", tab.dev]
            _mount.running = true
    }

    // Eject = unmount, then power the drive off so it is safe to pull.
    // External devices only (the Internal tab has no eject).
    function eject(tab) {
        if (root.mounting || !tab.mounted) return
            root.mounting = true
            _mount.command = ["bash", "-c",
            'udisksctl unmount -b "$1" && { [ -z "$2" ] || udisksctl power-off -b "$2" >/dev/null 2>&1; }; true',
            "_", tab.dev, tab.parent]
            _mount.running = true
    }

    function _truthy(v) { return v === true || v === 1 || v === "1" || v === "true" }

    function _collect(node, hot, model, out) {
        const isHot = hot || _truthy(node.hotplug) || _truthy(node.rm) || node.tran === "usb"
        const m = (node.model || model || "").trim()
        const skip = ["swap", "crypto_LUKS", "LVM2_member", "linux_raid_member"]
        if (isHot && node.fstype && skip.indexOf(node.fstype) < 0) {
            out.push({ dev: node.path, parent: node.pkname ? "/dev/" + node.pkname : node.path, name: node.label || m || node.size || node.path,
                size: node.size || "", mountpoint: node.mountpoint || "" })
        }
        const kids = node.children || []
        for (let i = 0; i < kids.length; i++) root._collect(kids[i], isHot, m, out)
    }

    function _applyDevices(text) {
        let data
        try { data = JSON.parse(text) } catch (e) { return }
        const out = []
        const top = data.blockdevices || []
        for (let i = 0; i < top.length; i++) root._collect(top[i], false, "", out)
            const hadDevice = root.activeMount !== ""
            root.devices = out
            // The device we were browsing was unplugged / unmounted: go home.
            if (hadDevice && root.activeMount === "") { root.goInternal(); return }
            if (root._pendingDev !== "") {
                for (let i = 0; i < out.length; i++) {
                    if (out[i].dev === root._pendingDev && out[i].mountpoint !== "") {
                        root._pendingDev = ""
                        root.list(out[i].mountpoint)
                        break
                    }
                }
            }
    }

    property Process _lsblk: Process {
        command: ["lsblk", "-J", "-o", "PATH,PKNAME,LABEL,MODEL,SIZE,MOUNTPOINT,FSTYPE,RM,HOTPLUG,TRAN,TYPE"]
        stdout: StdioCollector { onStreamFinished: root._applyDevices(text) }
    }

    property Process _mount: Process {
        onExited: (code) => {
            root.mounting = false
            if (code !== 0) root._pendingDev = ""
                root.refreshDevices()
        }
    }

    property Process _udev: Process {
        command: ["udevadm", "monitor", "--udev", "--subsystem-match=block"]
        running: root.watching
        stdout: SplitParser { onRead: (line) => root._udevDebounce.restart() }
    }
    property Timer _udevDebounce: Timer {
        interval: 600
        onTriggered: root.refreshDevices()
    }

    property bool _lowPrio: false
    // True once the startup preload has run; the popup maps its (transparent)
    // window at that point so opening never has to build GL resources.
    property bool ready: false
    function preload() {
        root.ready = true
        root._lowPrio = true
        root.start()
    }

    function list(dir) {
        root.filter = ""
        if (dir !== root.path) root.loading = true
            _lister.running = false
            const nice = root._lowPrio ? ["nice", "-n", "19"] : []
            root._lowPrio = false
            _lister.command = nice.concat(["bash", "-c",
                                          'd="$1"; [ -z "$d" ] && read -r d < "$2" 2>/dev/null; ' +
                                          '[ -d "$d" ] || d="$HOME/Music"; [ -d "$d" ] || d="$HOME"; ' +
                                          'cd -- "$d" || exit 1; pwd -P; ls -1ApL --group-directories-first 2>/dev/null',
                                          "_", dir, root.lastDirFile])
            _lister.running = true
    }

    function checkMpv() {
        _check.running = false
        _check.running = true
    }

    // Quit the local mpv over its IPC socket.
    function stop() {
        if (!root.mpvRunning) return
            Quickshell.execDetached(["python3", "-c",
                                    'import socket,sys; s=socket.socket(socket.AF_UNIX); s.settimeout(1); ' +
                                    's.connect(sys.argv[1]); s.sendall((sys.argv[2]+"\\n").encode())',
                                    root.mpvSocket, JSON.stringify({ command: ["quit"] })])
            root.mpvRunning = false
    }

    function enter(dir) { root.list(dir) }

    function up() {
        if (root.path === "" || root.path === "/") return
            const i = root.path.lastIndexOf("/")
            root.list(i <= 0 ? "/" : root.path.slice(0, i))
    }

    // Write the target, then switch playback. Works for a file or a folder.
    // Running mpv is told to loadfile (replace) over its IPC socket, so the
    // current song keeps playing until the new one takes over. Only when
    // mpv isn't reachable is playCommand (autoplay.sh) started.
    function play(target, isDir) {
        const isUrl = /^[a-z][a-z0-9+.\-]*:\/\//i.test(target)
        const dir = isUrl ? "" : (isDir ? target : target.slice(0, Math.max(1, target.lastIndexOf("/"))))
        const payload = JSON.stringify({ command: ["loadfile", target, "replace"] }) + "\n" +
        JSON.stringify({ command: ["set_property", "pause", false] })
        Quickshell.execDetached(["bash", "-c",
                                'mkdir -p -- "$1" && printf %s "$2" > "$3" && { [ -z "$4" ] || printf %s "$4" > "$5"; }; ' +
                                'if [ -S "$7" ] && python3 -c \'import socket,sys; s=socket.socket(socket.AF_UNIX); s.settimeout(1); ' +
                                's.connect(sys.argv[1]); s.sendall((sys.argv[2]+"\\n").encode()); s.recv(4096)\' "$7" "$8" >/dev/null 2>&1; ' +
                                'then exit 0; fi; [ -z "$6" ] || exec "$6"',
                                "_", root.stateDir, target, root.targetFile, dir, root.lastDirFile, root.playCommand,
                                root.mpvSocket, payload])
    }

    property Process _check: Process {
        command: ["bash", "-c", '[ -S "$1" ] && pgrep -x mpv >/dev/null', "_", root.mpvSocket]
        onExited: (code) => root.mpvRunning = (code === 0)
    }

    property Process _lister: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                if (lines.length === 0 || lines[0] === "") { root.loading = false; return }
                const dir = lines[0]
                const base = dir === "/" ? "" : dir
                const list = []
                for (let i = 1; i < lines.length; i++) {
                    let n = lines[i]
                    if (n === "" || n[0] === ".") continue
                        const isDir = n.endsWith("/")
                        if (isDir) n = n.slice(0, -1)
                            else if (!root._isAudio(n)) continue
                                list.push({ name: n, isDir: isDir, path: base + "/" + n })
                }
                // Same folder, same contents: leave the model untouched so a
                // re-open does not rebuild the grid mid-fade.
                const sig = dir + "\n" + lines.join("\n")
                if (sig !== root._sig) {
                    root._sig = sig
                    root.path = dir
                    root.entries = list
                    root._rebuild()
                }
                root.loading = false
            }
        }
    }
}
