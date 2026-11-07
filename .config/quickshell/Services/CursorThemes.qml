pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * CursorThemes.qml -- Settings > Cursor. Main shell only.
 *
 * Lists the cursor themes on the machine (any folder with a "cursors" folder inside, in
 * ~/.local/share/icons, ~/.icons, /usr/share/icons, /usr/local/share/icons), always offers
 * "Default" (the system's own cursor) and Bibata, and applies the choice with scripts/set-cursor.sh
 * (live through hyprctl, remembered in state/cursor-theme.txt, GTK / X11 kept in step).
 * New themes are added with scripts/install-cursor.sh (a folder or an archive from the file picker).
 *
 * With nothing chosen yet the cursor is Bibata when it is installed, else the system Default.
 */
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateFile: root.home + "/.config/quickshell/state/cursor-theme.txt"
    readonly property string scripts: root.home + "/.config/quickshell/scripts/"
    readonly property string previewDir: root.home + "/.cache/quickshell/cursor-previews/"
    readonly property int minSize: 16
    readonly property int maxSize: 64

    property string theme: ""          // as stored ("" = nothing chosen yet)
    property int size: 20
    property var installed: []         // [{ name, dir, user }]
    property bool scanning: false
    property string message: ""        // result of the last Add

    readonly property var bibata: {
        for (let i = 0; i < root.installed.length; i++)
            if (root.installed[i].name === "Bibata-Modern-Classic") return root.installed[i]
                for (let i = 0; i < root.installed.length; i++)
                    if (root.installed[i].name.indexOf("Bibata") === 0) return root.installed[i]
                        return null
    }
    readonly property string effective: root.theme !== "" ? root.theme
    : (root.bibata !== null ? root.bibata.name : "default")

    // what the settings page lists: Default, Bibata (even when missing), then everything else
    readonly property var entries: {
        const out = [{ name: "default", label: "Default", note: "the system's own cursor", installed: true, user: false, special: true }]
        const b = root.bibata
        out.push(b !== null ? { name: b.name, label: b.name, note: "default theme", installed: true, user: b.user, special: true }
        : { name: "Bibata-Modern-Classic", label: "Bibata-Modern-Classic", note: "not installed", installed: false, user: false, special: true })
        for (let i = 0; i < root.installed.length; i++) {
            const t = root.installed[i]
            if (b !== null && t.name === b.name) continue
                if (t.name === "default" || t.name === "Default") continue
                    out.push({ name: t.name, label: t.name, note: t.user ? "your themes" : "system", installed: true, user: t.user, special: false })
        }
        return out
    }

    // the theme's normal arrow as a PNG (made by scripts/cursor-preview.py while scanning)
    function previewOf(name) { return "file://" + root.previewDir + name + ".png" }

    function refresh() {
        root.scanning = true
        scanner.running = false
        scanner.command = ["bash", "-c",
        'pv="$HOME/.cache/quickshell/cursor-previews"; mkdir -p "$pv"; py="$HOME/.config/quickshell/scripts/cursor-preview.py"; ' +
        '[ -f "$pv/default.png" ] || for c in /usr/share/icons/default /usr/share/icons/Adwaita; do python3 "$py" "$c" "$pv/default.png" 2>/dev/null && break; done; ' +
        'for d in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons /usr/local/share/icons; do ' +
        '[ -d "$d" ] || continue; for t in "$d"/*/; do t="${t%/}"; [ -d "$t/cursors" ] || continue; n=$(basename "$t"); ' +
        'u=0; case "$d" in "$HOME"/*) u=1;; esac; printf "%s\\t%s\\t%s\\n" "$n" "$d" "$u"; ' +
        '[ -f "$pv/$n.png" ] || python3 "$py" "$t" "$pv/$n.png" 2>/dev/null; done; done']
        scanner.running = true
    }

    // Applying runs one script at a time: while one is running, a newer request just waits and the
    // latest choice runs when it ends. The size slider only applies once you pause / let go
    // (350 ms), so dragging stays smooth and the cursor updates after.
    property bool _again: false
    function _run() {
        if (applier.running) { root._again = true; return }
        applier.command = ["bash", root.scripts + "set-cursor.sh", root.effective, String(root.size)]
        applier.running = true
    }
    function apply(name) {
        root.theme = name
        applyTimer.stop()
        root._run()
    }
    function setSize(px) {
        root.size = Math.max(root.minSize, Math.min(root.maxSize, Math.round(px)))
        if (root.theme === "") root.theme = root.effective
            applyTimer.restart()
    }
    Timer { id: applyTimer; interval: 350; onTriggered: root._run() }
    Process {
        id: applier
        onExited: { if (root._again) { root._again = false; root._run() } }
    }
    function install(path) {
        root.message = "Adding..."
        installer.running = false
        installer.command = ["bash", root.scripts + "install-cursor.sh", path]
        installer.running = true
    }
    // only themes in your own folders can be removed
    function remove(name) {
        for (let i = 0; i < root.installed.length; i++) {
            const t = root.installed[i]
            if (t.name === name && t.user && name !== "" && name.indexOf("/") < 0) {
                Quickshell.execDetached(["bash", "-c", 'rm -rf -- "$1/$2" "$3/$2.png"', "_", t.dir, name, root.home + "/.cache/quickshell/cursor-previews"])
                if (root.theme === name) root.apply("default")
                    refreshLater.restart()
                    return
            }
        }
    }
    Timer { id: refreshLater; interval: 600; onTriggered: root.refresh() }

    Process {
        id: scanner
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}
                const list = []
                const lines = text.split("\n")
                // user folders come first in the scan, so a user's copy wins over the system's
                for (let i = 0; i < lines.length; i++) {
                    const p = lines[i].split("\t")
                    if (p.length !== 3 || p[0] === "" || seen[p[0]]) continue
                        seen[p[0]] = true
                        list.push({ name: p[0], dir: p[1], user: p[2] === "1" })
                }
                list.sort(function (a, b) { return a.name.toLowerCase() < b.name.toLowerCase() ? -1 : 1 })
                root.installed = list
                root.scanning = false
            }
        }
    }
    Process {
        id: installer
        stdout: StdioCollector {
            onStreamFinished: {
                const names = text.split("\n").filter(function (x) { return x.trim() !== "" })
                root.message = names.length > 0 ? "Added: " + names.join(", ") : "No cursor theme found there (it needs a folder named cursors inside)."
                root.refresh()
            }
        }
    }

    function _parse(raw) {
        const line = String(raw).split("\n")[0]
        const p = line.split("\t")
        if (p[0] !== undefined && p[0].trim() !== "") root.theme = p[0].trim()
            const n = parseInt(p[1])
            if (isFinite(n)) root.size = Math.max(root.minSize, Math.min(root.maxSize, n))
    }
    FileView {
        id: file
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._parse(text())
    }

    Component.onCompleted: root.refresh()
}
