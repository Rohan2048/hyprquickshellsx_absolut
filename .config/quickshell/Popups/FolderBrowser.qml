pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import "../Theme"
import "../Widgets"

// Folder browser inside Settings (grid, same look as the music picker). Shows the folders AND the
// images of every format in the folder you are in, so you can tell at a glance which folder holds
// your wallpapers. "Choose this directory" picks the folder you are standing in.
// Signals: chosen(path), cancelled().
Item {
    id: root

    property string start: ""
    signal chosen(string path)
    signal cancelled()

    property string path: ""
    property var entries: []             // [{ name, path, isDir }]
    property bool loading: false
    readonly property var imageExt: ["jpg", "jpeg", "png", "webp", "bmp", "gif", "svg", "tif", "tiff", "avif", "jxl", "heic", "ico"]
    readonly property string folderIcon: "file://" + Quickshell.env("HOME") + "/.config/icons/folder.svg"
    readonly property int dirCount: root.entries.filter(function (e) { return e.isDir }).length
    readonly property int imageCount: root.entries.length - root.dirCount

    function _isImage(name) {
        const i = name.lastIndexOf(".")
        return i > 0 && root.imageExt.indexOf(name.slice(i + 1).toLowerCase()) >= 0
    }
    function list(dir) {
        loading = true
        lister.running = false
        lister.command = ["bash", "-c",
        'cd -- "$1" 2>/dev/null || cd "$HOME" || exit 1; pwd -P; ls -1ApL --group-directories-first 2>/dev/null',
        "_", dir]
        lister.running = true
    }
    function up() {
        if (root.path === "" || root.path === "/") return
            const k = root.path.lastIndexOf("/")
            root.list(k <= 0 ? "/" : root.path.slice(0, k))
    }
    Component.onCompleted: root.list(root.start)

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                if (lines.length >= 1 && lines[0] !== "") {
                    const dir = lines[0]
                    const base = dir === "/" ? "" : dir
                    const out = []
                    for (let i = 1; i < lines.length; i++) {
                        let n = lines[i]
                        if (n === "" || n[0] === ".") continue
                            const isDir = n.endsWith("/")
                            if (isDir) n = n.slice(0, -1)
                                else if (!root._isImage(n)) continue
                                    out.push({ name: n, path: base + "/" + n, isDir: isDir })
                    }
                    root.path = dir
                    root.entries = out
                }
                root.loading = false
            }
        }
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
                text: root.loading ? "Reading..." : root.path
                elide: Text.ElideLeft
                color: Theme.accentActive
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
            GlassButton { text: "✓  Choose this directory"; active: true; disabled: root.path === ""; onClicked: root.chosen(root.path) }
            GlassButton { text: "Cancel"; onClicked: root.cancelled() }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

        GridView {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            readonly property int cols: Math.max(3, Math.floor(width / 112))
            cellWidth: Math.floor(width / cols)
            cellHeight: cellWidth + 28
            model: root.entries

            delegate: Item {
                id: cell
                required property var modelData
                width: grid.cellWidth
                height: grid.cellHeight

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: 12
                    color: (cellMouse.containsMouse && cell.modelData.isDir) ? Qt.rgba(Theme.accentActive.r, Theme.accentActive.g, Theme.accentActive.b, 0.25) : "transparent"
                }
                // folder: the folder icon; image: its thumbnail (any format Qt can read)
                Item {
                    id: pic
                    x: 10; y: 8
                    width: parent.width - 20
                    height: width
                    Image {
                        visible: cell.modelData.isDir
                        anchors.centerIn: parent
                        width: parent.width * 0.6
                        height: width
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize: Qt.size(112, 112)
                        source: root.folderIcon
                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: ColorOverlay { color: Theme.iconColor }
                    }
                    Rectangle {
                        visible: !cell.modelData.isDir
                        anchors.fill: parent
                        radius: 8
                        color: Theme.pillOffBg
                        border.width: 1
                        border.color: Theme.borderMuted
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: cell.modelData.isDir ? "" : "file://" + cell.modelData.path
                            sourceSize: Qt.size(200, 200)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                        }
                    }
                }
                Text {
                    anchors.top: pic.bottom
                    anchors.topMargin: 4
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideMiddle
                    text: cell.modelData.name
                    color: Theme.foreground
                    opacity: cell.modelData.isDir ? 1 : 0.8
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.bold: cell.modelData.isDir
                }
                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: cell.modelData.isDir ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: if (cell.modelData.isDir) root.list(cell.modelData.path)
                }
            }

            Text {
                visible: !root.loading && root.entries.length === 0
                anchors.centerIn: parent
                text: "Empty folder"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }

        Text {
            Layout.fillWidth: true
            text: root.dirCount + (root.dirCount === 1 ? " folder, " : " folders, ") + root.imageCount + (root.imageCount === 1 ? " image" : " images")
            + "  ·  click a folder to open it, then Choose this directory"
            elide: Text.ElideRight
            color: Theme.foreground
            opacity: 0.5
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }
    }
}
