pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Services"
import "../Theme"
import "../Widgets"

// Quickshell style of the wallpaper picker (SUPER + SHIFT + W): a grid of your wallpapers, same look
// and keys as the music picker. Chosen in Settings > Popups > Wallpaper picker; the keybind script
// (hypr/wallpaper_switcher.sh) opens it with scripts/qs-pick.sh and falls back to rofi when the
// shell does not answer.
//   qs ipc call wallpaperPicker open | close | toggle
// Keys: type = filter   arrows = move   Enter = apply   Esc = clear filter / close
// Applying runs scripts/apply-wallpaper.sh (the same steps the rofi script does).
PanelWindow {
    id: picker

    property bool shown: false
    property bool _closing: false
    property int selected: 0
    property var all: []                  // [{ name, path, thumb }]
    property string filter: ""
    property bool loading: false
    readonly property int fadeMs: Animations.panelFadeDuration
    readonly property real uiScale: PopupSettings.scaleOf("wallpaper")
    readonly property int columns: 4
    readonly property real baseW: 760
    readonly property real baseH: 560
    readonly property var rows: {
        const f = picker.filter.toLowerCase()
        return f === "" ? picker.all : picker.all.filter(function (r) { return r.name.toLowerCase().indexOf(f) >= 0 })
    }

    visible: shown || _closing
    color: "transparent"
    exclusiveZone: 0
    implicitWidth: Math.round(baseW * uiScale) + 24
    implicitHeight: Math.round(baseH * uiScale) + 24

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:wallpaperPicker"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function open() {
        hideTimer.stop()
        _closing = false
        filter = ""
        selected = 0
        load()
        shown = true
    }
    function close() {
        if (!shown) return
            shown = false
            _closing = true
            hideTimer.restart()
    }
    function toggle() { shown ? close() : open() }
    function apply(i) {
        const r = picker.rows[i]
        if (!r) return
            Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/apply-wallpaper.sh", r.path])
            close()
    }

    Timer { id: hideTimer; interval: picker.fadeMs + 60; onTriggered: picker._closing = false }

    // list the folder: name <TAB> path <TAB> thumbnail (the rofi script's cache when it has one, else the image)
    function load() {
        loading = true
        lister.running = false
        lister.command = ["bash", "-c",
        'shopt -s nullglob nocaseglob; d="$1"; t="$HOME/.cache/wallpaper_thumbs"; ' +
        'for f in "$d"/*.jpg "$d"/*.jpeg "$d"/*.png "$d"/*.webp "$d"/*.bmp "$d"/*.gif; do ' +
        '[ -f "$f" ] || continue; b=$(basename "$f"); n="${b%.*}"; th="$t/${n}_thumb.png"; ' +
        '[ -f "$th" ] || th="$f"; printf "%s\\t%s\\t%s\\n" "$n" "$f" "$th"; done | sort -f',
        "_", PopupSettings.wallpaperDir]
        lister.running = true
    }
    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const p = lines[i].split("\t")
                    if (p.length === 3 && p[1] !== "") out.push({ name: p[0], path: p[1], thumb: p[2] })
                }
                picker.all = out
                picker.loading = false
            }
        }
    }

    ClickAwayCloser {
        targetWindows: [picker]
        active: picker.shown
        onDismissed: picker.close()
    }

    IpcHandler {
        target: "wallpaperPicker"
        function toggle(): void { picker.toggle() }
        function open(): void { picker.open() }
        function close(): void { picker.close() }
    }
    // "Try Quickshell version" in Settings
    Connections {
        target: PopupSettings
        function onWallpaperRequested() { picker.open() }
    }

    FocusScope {
        anchors.fill: parent
        anchors.margins: 12
        focus: picker.shown
        opacity: picker.shown ? 1 : 0
        scale: picker.shown ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: picker.fadeMs } }
        Behavior on scale {
            SpringAnimation {
                spring: Animations.panelSlideSpring
                damping: Animations.panelSlideDamping
                mass: Animations.panelSlideMass
            }
        }

        Keys.onPressed: (event) => {
            const n = picker.rows.length
            switch (event.key) {
                case Qt.Key_Escape:
                    if (picker.filter !== "") picker.filter = ""
                        else picker.close()
                            break
                case Qt.Key_Return:
                case Qt.Key_Enter: picker.apply(picker.selected); break
                case Qt.Key_Right: picker.selected = Math.min(n - 1, picker.selected + 1); break
                case Qt.Key_Left: picker.selected = Math.max(0, picker.selected - 1); break
                case Qt.Key_Down: picker.selected = Math.min(n - 1, picker.selected + picker.columns); break
                case Qt.Key_Up: picker.selected = Math.max(0, picker.selected - picker.columns); break
                case Qt.Key_Home: picker.selected = 0; break
                case Qt.Key_End: picker.selected = Math.max(0, n - 1); break
                case Qt.Key_Backspace: picker.filter = picker.filter.slice(0, -1); break
                default:
                    if (!(event.modifiers & Qt.ControlModifier) && event.text.length === 1 && event.text >= " ")
                        picker.filter += event.text
                        else return
            }
            event.accepted = true
        }

        PopupScale {
            anchors.fill: parent
            popupId: "wallpaper"

            Rectangle {
                id: panel
                width: picker.baseW
                height: picker.baseH
                radius: PopupSettings.radiusOf("wallpaper")
                color: Theme.popupPaintBg
                border.width: 1
                border.color: Theme.accentActive
                clip: true

                ThemeFill { anchors.fill: parent; fill: Theme.popupFill; radius: panel.radius }

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    Text {
                        width: parent.width
                        text: "Wallpapers  ·  " + PopupSettings.wallpaperDir
                        elide: Text.ElideMiddle
                        color: Theme.accentActive
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: "> " + picker.filter + "▂"
                        elide: Text.ElideRight
                        color: Theme.foreground
                        opacity: picker.filter === "" ? 0.45 : 1
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Rectangle { width: parent.width; height: 1; color: Theme.foreground; opacity: 0.12 }

                    GridView {
                        id: grid
                        width: parent.width
                        height: parent.height - 86
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        cellWidth: Math.floor(width / picker.columns)
                        cellHeight: cellWidth * 0.62 + 26
                        model: picker.rows
                        currentIndex: picker.selected
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                        delegate: Item {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property bool sel: index === picker.selected
                            readonly property bool current: modelData.path === WallpaperState.imagePath
                            width: grid.cellWidth
                            height: grid.cellHeight

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 3
                                radius: 10
                                color: cell.sel ? Qt.rgba(Theme.accentActive.r, Theme.accentActive.g, Theme.accentActive.b, 0.28) : "transparent"
                                border.width: cell.current ? 2 : 0
                                border.color: Theme.accentActive
                            }
                            Rectangle {
                                id: frame
                                x: 9; y: 9
                                width: parent.width - 18
                                height: width * 0.62
                                radius: 8
                                color: Theme.pillOffBg
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: "file://" + cell.modelData.thumb
                                    sourceSize: Qt.size(360, 360)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                }
                            }
                            Text {
                                anchors.top: frame.bottom
                                anchors.topMargin: 4
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideMiddle
                                text: cell.modelData.name
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onEntered: picker.selected = cell.index
                                onClicked: { picker.selected = cell.index; picker.apply(cell.index) }
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        text: picker.loading ? "Loading..." : (picker.rows.length === 0 ? "No wallpapers found in this folder"
                        : "Enter: Apply  ·  type to filter  ·  arrows to move  ·  Esc: Close")
                        elide: Text.ElideRight
                        color: Theme.foreground
                        opacity: 0.5
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                    }
                }
            }
        }
    }
}
