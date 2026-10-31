pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Theme"

// Backend for Popups/FontPickerPopup.qml. Same shape as MusicPicker:
// nothing runs until the browse page is opened.
Singleton {
    id: root

    readonly property string folderIcon: "file://" + Quickshell.env("HOME") + "/.config/icons/folder.svg"
    readonly property string stateDir: Quickshell.env("HOME") + "/.config/quickshell/state"
    readonly property string lastDirFile: stateDir + "/font_lastdir"
    readonly property var fontExt: ["ttf", "otf"]

    property string path: ""
    property string filter: ""
    property var entries: []
    property var rows: []
    property bool loading: false
    property bool ready: false          // window is mapped (transparent) once true
    property string _sig: ""

    onFilterChanged: _rebuild()

    function _isFont(name) {
        const i = name.lastIndexOf(".")
        return i > 0 && fontExt.indexOf(name.slice(i + 1).toLowerCase()) >= 0
    }

    function _rebuild() {
        const out = []
        if (root.path !== "") {
            if (root.filter === "" && root.path !== "/")
                out.push({ kind: "up", label: "..", path: "", isDir: true })
                const f = root.filter.toLowerCase()
                for (let i = 0; i < root.entries.length; i++) {
                    const e = root.entries[i]
                    if (f === "" || e.name.toLowerCase().indexOf(f) >= 0)
                        out.push({ kind: "entry", label: e.isDir ? e.name + "/" : e.name, path: e.path, isDir: e.isDir })
                }
        }
        root.rows = out
    }

    function preload() { root.ready = true }

    // Called when the browse page opens: last dir, else ~/Downloads, else ~.
    function start() {
        root.filter = ""
        root.list(root.path)
    }

    function list(dir) {
        root.filter = ""
        if (dir !== root.path) root.loading = true
            _lister.running = false
            _lister.command = ["bash", "-c",
            'd="$1"; [ -z "$d" ] && read -r d < "$2" 2>/dev/null; ' +
            '[ -d "$d" ] || d="$HOME/Downloads"; [ -d "$d" ] || d="$HOME"; ' +
            'cd -- "$d" || exit 1; pwd -P; ls -1ApL --group-directories-first 2>/dev/null',
            "_", dir, root.lastDirFile]
            _lister.running = true
    }

    function enter(dir) { root.list(dir) }

    function up() {
        if (root.path === "" || root.path === "/") return
            const i = root.path.lastIndexOf("/")
            root.list(i <= 0 ? "/" : root.path.slice(0, i))
    }

    // Remember the folder, then hand the file to the Theme font stack.
    function pick(file) {
        const dir = file.slice(0, Math.max(1, file.lastIndexOf("/")))
        Quickshell.execDetached(["bash", "-c",
                                'mkdir -p -- "$1" && printf %s "$2" > "$3"', "_", root.stateDir, dir, root.lastDirFile])
        Theme.addFont(file)
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
                            else if (!root._isFont(n)) continue
                                list.push({ name: n, isDir: isDir, path: base + "/" + n })
                }
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
