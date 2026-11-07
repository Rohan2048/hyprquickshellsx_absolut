import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Theme"
import "../Services"

// Small in-shell image picker (same idea as the Font page's file browser):
// folders, then image files with a thumbnail. Remembers the last folder.
// Emits picked(absolutePath) or cancelled(). Nothing runs until start().
Item {
    id: root

    signal picked(string file)
    signal cancelled()

    readonly property string stateDir: Quickshell.env("HOME") + "/.config/quickshell/state"
    readonly property string lastDirFile: stateDir + "/theme_lastdir"
    readonly property var imageExt: ["png", "jpg", "jpeg", "webp", "bmp", "gif", "svg"]

    // List or Grid (remembered, shared by every file picker in Settings)
    readonly property string viewMode: PopupSettings.get("browser", "view", "list") === "grid" ? "grid" : "list"
    function setViewMode(m) { PopupSettings.put("browser", "view", m === "grid" ? "grid" : null) }

    property string path: ""
    property var entries: []
    property bool loading: false
    property string _sig: ""

    function _isImage(name) {
        const i = name.lastIndexOf(".")
        return i > 0 && root.imageExt.indexOf(name.slice(i + 1).toLowerCase()) >= 0
    }

    // `text` = first line the directory, then `ls -1Ap` output.
    function applyListing(text) {
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
                    else if (!root._isImage(n)) continue
                        list.push({ name: n, isDir: isDir, path: base + "/" + n })
        }
        const sig = dir + "\n" + lines.join("\n")
        if (sig !== root._sig) {
            root._sig = sig
            root.path = dir
            root.entries = list
        }
        root.loading = false
    }

    function list(dir) {
        if (dir !== root.path) root.loading = true
            lister.running = false
            lister.command = ["bash", "-c",
            'd="$1"; [ -z "$d" ] && read -r d < "$2" 2>/dev/null; ' +
            '[ -d "$d" ] || d="$HOME/Pictures"; [ -d "$d" ] || d="$HOME"; ' +
            'cd -- "$d" || exit 1; pwd -P; ls -1ApL --group-directories-first 2>/dev/null',
            "_", dir, root.lastDirFile]
            lister.running = true
    }
    function start() { root.list(root.path) }
    function up() {
        if (root.path === "" || root.path === "/") return
            const i = root.path.lastIndexOf("/")
            root.list(i <= 0 ? "/" : root.path.slice(0, i))
    }
    function pick(file) {
        const dir = file.slice(0, Math.max(1, file.lastIndexOf("/")))
        Quickshell.execDetached(["bash", "-c",
                                'mkdir -p -- "$1" && printf %s "$2" > "$3"', "_", root.stateDir, dir, root.lastDirFile])
        root.picked(file)
    }

    Component.onCompleted: root.start()

    Process {
        id: lister
        stdout: StdioCollector { onStreamFinished: root.applyListing(text) }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            GlassButton { text: "Up"; onClicked: root.up() }
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

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

        ListView {
            id: view
            visible: root.viewMode === "list"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: root.entries

            delegate: Rectangle {
                id: row
                required property var modelData
                width: view.width
                height: 36
                radius: Theme.radiusSm
                color: rowMouse.containsMouse ? Theme.hoverBgStrong : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 10

                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        radius: 4
                        color: Theme.pillOffBg
                        border.width: 1
                        border.color: Theme.borderMuted
                        clip: true

                        Text {
                            visible: row.modelData.isDir
                            anchors.centerIn: parent
                            text: "/"
                            color: Theme.accentActive
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }
                        Image {
                            visible: !row.modelData.isDir
                            anchors.fill: parent
                            source: row.modelData.isDir ? "" : "file://" + row.modelData.path
                            sourceSize: Qt.size(56, 56)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: row.modelData.isDir ? row.modelData.name + "/" : row.modelData.name
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.modelData.isDir ? root.list(row.modelData.path) : root.pick(row.modelData.path)
                }
            }

            Text {
                visible: !root.loading && root.entries.length === 0
                anchors.centerIn: parent
                text: "No images or folders here"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }

        GridView {
            id: grid
            visible: root.viewMode === "grid"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            readonly property int cols: Math.max(2, Math.floor(width / 128))
            cellWidth: Math.floor(width / cols)
            cellHeight: cellWidth + 22
            model: root.viewMode === "grid" ? root.entries : []

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: Theme.radiusSm
                    color: cellMouse.containsMouse ? Theme.hoverBgStrong : "transparent"

                    Column {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4
                        Rectangle {
                            width: parent.width
                            height: parent.width
                            radius: 6
                            color: Theme.pillOffBg
                            border.width: 1
                            border.color: Theme.borderMuted
                            clip: true
                            Text {
                                visible: cell.modelData.isDir
                                anchors.centerIn: parent
                                text: "/"
                                color: Theme.accentActive
                                font.family: Theme.fontFamily
                                font.pixelSize: 34
                                font.bold: true
                            }
                            Image {
                                visible: !cell.modelData.isDir
                                anchors.fill: parent
                                source: cell.modelData.isDir ? "" : "file://" + cell.modelData.path
                                sourceSize: Qt.size(240, 240)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideMiddle
                            text: cell.modelData.isDir ? cell.modelData.name + "/" : cell.modelData.name
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }
                }
                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cell.modelData.isDir ? root.list(cell.modelData.path) : root.pick(cell.modelData.path)
                }
            }

            Text {
                visible: !root.loading && root.entries.length === 0
                anchors.centerIn: parent
                text: "No images or folders here"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }
}
