pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Services"
import "../Theme"
import "../Widgets"

// File picker for adding cursor themes (inside Settings > Cursor), same style as the icon / image
// pickers, with List and Grid views. Folders open on click. A folder that is a cursor theme (or holds
// some) is marked and has its own Add button; archives (.tar.gz, .zip ...) are added with a click.
// "Add this folder" adds the folder you are standing in. Signals: picked(path), cancelled().
Item {
    id: root

    signal picked(string path)
    signal cancelled()

    readonly property string stateDir: Quickshell.env("HOME") + "/.config/quickshell/state"
    readonly property string lastDirFile: root.stateDir + "/cursor_lastdir"
    readonly property var archiveExt: [".tar.gz", ".tgz", ".tar.xz", ".txz", ".tar.bz2", ".tbz2", ".tar.zst", ".tar", ".zip"]
    readonly property string viewMode: PopupSettings.get("browser", "view", "list") === "grid" ? "grid" : "list"
    function setViewMode(m) { PopupSettings.put("browser", "view", m === "grid" ? "grid" : null) }

    property string path: ""
    property bool here: false            // the folder we are in is itself a cursor theme
    property var entries: []             // [{ name, path, kind: "dir"|"theme"|"archive" }]
    property bool loading: false

    function _isArchive(n) {
        const l = n.toLowerCase()
        for (let i = 0; i < root.archiveExt.length; i++) if (l.endsWith(root.archiveExt[i])) return true
            return false
    }
    function list(dir) {
        root.loading = true
        lister.running = false
        lister.command = ["bash", "-c",
        'd="$1"; [ -z "$d" ] && read -r d < "$2" 2>/dev/null; [ -d "$d" ] || d="$HOME/Downloads"; [ -d "$d" ] || d="$HOME"; ' +
        'cd -- "$d" || exit 1; pwd -P; if [ -d cursors ]; then echo 1; else echo 0; fi; ' +
        'for f in */; do f="${f%/}"; [ -e "$f" ] || continue; k=D; ' +
        'if [ -d "$f/cursors" ]; then k=T; else for s in "$f"/*/; do [ -d "${s}cursors" ] && { k=T; break; }; done; fi; ' +
        'printf "%s\\t%s\\n" "$k" "$f"; done; ' +
        'for f in *; do [ -f "$f" ] && printf "F\\t%s\\n" "$f"; done',
        "_", dir, root.lastDirFile]
        lister.running = true
    }
    function up() {
        if (root.path === "" || root.path === "/") return
            const k = root.path.lastIndexOf("/")
            root.list(k <= 0 ? "/" : root.path.slice(0, k))
    }
    function pick(p) {
        Quickshell.execDetached(["bash", "-c", 'mkdir -p -- "$1" && printf %s "$2" > "$3"', "_", root.stateDir,
                                p.slice(0, Math.max(1, p.lastIndexOf("/"))), root.lastDirFile])
        root.picked(p)
    }
    Component.onCompleted: root.list("")

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                if (lines.length < 2 || lines[0] === "") { root.loading = false; return }
                const dir = lines[0]
                const base = dir === "/" ? "" : dir
                const dirs = []
                const themes = []
                const archives = []
                for (let i = 2; i < lines.length; i++) {
                    const p = lines[i].split("\t")
                    if (p.length !== 2 || p[1] === "" || p[1][0] === ".") continue
                        const e = { name: p[1], path: base + "/" + p[1], kind: "dir" }
                        if (p[0] === "T") { e.kind = "theme"; themes.push(e) }
                        else if (p[0] === "D") dirs.push(e)
                            else if (p[0] === "F" && root._isArchive(p[1])) { e.kind = "archive"; archives.push(e) }
                }
                root.path = dir
                root.here = lines[1] === "1"
                root.entries = themes.concat(dirs, archives)
                root.loading = false
            }
        }
    }

    component Badge: Text {
        color: Theme.accentActive
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.bold: true
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            GlassButton { text: "Up"; disabled: root.path === "" || root.path === "/"; onClicked: root.up() }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideLeft
                text: root.loading ? "Reading..." : root.path
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
            GlassButton { text: "List"; active: root.viewMode === "list"; onClicked: root.setViewMode("list") }
            GlassButton { text: "Grid"; active: root.viewMode === "grid"; onClicked: root.setViewMode("grid") }
            GlassButton { text: "Cancel"; onClicked: root.cancelled() }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: root.here
            spacing: 8
            Badge { Layout.fillWidth: true; text: "This folder is a cursor theme." }
            GlassButton { text: "Add this folder"; active: true; onClicked: root.pick(root.path) }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

        // ---------------- list ----------------
        ListView {
            id: listView
            visible: root.viewMode === "list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.viewMode === "list" ? root.entries : []

            delegate: Rectangle {
                id: row
                required property var modelData
                width: listView.width
                height: 36
                radius: Theme.radiusSm
                color: rowMouse.containsMouse ? Theme.hoverBgStrong : "transparent"
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.modelData.kind === "archive" ? root.pick(row.modelData.path) : root.list(row.modelData.path)
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10
                    Text {
                        Layout.preferredWidth: 20
                        horizontalAlignment: Text.AlignHCenter
                        text: row.modelData.kind === "archive" ? "⬇" : (row.modelData.kind === "theme" ? "◆" : "/")
                        color: row.modelData.kind === "dir" ? Theme.foreground : Theme.accentActive
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: row.modelData.kind === "archive" ? row.modelData.name : row.modelData.name + "/"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Badge { visible: row.modelData.kind === "theme"; text: "cursor theme" }
                    Badge { visible: row.modelData.kind === "archive"; text: "archive: click to add" }
                    GlassButton {
                        visible: row.modelData.kind === "theme"
                        text: "Add"
                        active: true
                        onClicked: root.pick(row.modelData.path)
                    }
                }
            }
        }

        // ---------------- grid ----------------
        GridView {
            id: grid
            visible: root.viewMode === "grid"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            readonly property int cols: Math.max(3, Math.floor(width / 120))
            cellWidth: Math.floor(width / cols)
            cellHeight: 118
            model: root.viewMode === "grid" ? root.entries : []

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: 12
                    color: cellMouse.containsMouse ? Qt.rgba(Theme.accentActive.r, Theme.accentActive.g, Theme.accentActive.b, 0.2) : "transparent"
                    border.width: cell.modelData.kind === "dir" ? 0 : 1
                    border.color: Theme.accentActive
                }
                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cell.modelData.kind === "archive" ? root.pick(cell.modelData.path) : root.list(cell.modelData.path)
                }
                Column {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: cell.modelData.kind === "archive" ? "⬇" : (cell.modelData.kind === "theme" ? "◆" : "/")
                        color: cell.modelData.kind === "dir" ? Theme.foreground : Theme.accentActive
                        font.family: Theme.fontFamily
                        font.pixelSize: 30
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        text: cell.modelData.name
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: cell.modelData.kind !== "dir"
                        text: cell.modelData.kind === "theme" ? "cursor theme" : "archive"
                        color: Theme.accentActive
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }
                }
                // folders that are themes: Add without opening
                Rectangle {
                    visible: cell.modelData.kind === "theme"
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 6
                    width: 38; height: 20; radius: 10
                    color: addMouse.containsMouse ? Theme.accentHover : Theme.accentActive
                    Text { anchors.centerIn: parent; text: "Add"; color: Theme.textOnAccent; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
                    MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.pick(cell.modelData.path) }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: !root.loading && root.entries.length === 0
            text: "No folders or archives here"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }
        Text {
            Layout.fillWidth: true
            text: "Pick a cursor theme folder (marked) or an archive you downloaded. It is copied into ~/.local/share/icons."
            elide: Text.ElideRight
            color: Theme.foreground
            opacity: 0.5
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }
    }
}
