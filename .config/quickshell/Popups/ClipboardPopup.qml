import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// Quickshell version of the rofi clipboard history (`cliphist list | rofi -dmenu ... | cliphist decode | wl-copy`):
// a centred panel with a search box and the history, newest first. Used when Settings > Popups >
// Clipboard history has Style = Quickshell; the keybind (scripts/clipboard.sh) calls
//     qs ipc call clipboard toggle
// Enter copies the entry (cliphist decode | wl-copy) and closes. Same fade + spring scale as the launcher,
// drawn with the shell theme and the Theme > Border settings.
PanelWindow {
    id: popup

    readonly property bool shown: PopupSettings.clipboardOpen
    property bool _closing: false
    readonly property int fadeMs: Animations.panelFadeDuration

    readonly property real scrW: popup.screen ? popup.screen.width : 1920
    readonly property real scrH: popup.screen ? popup.screen.height : 1080

    visible: shown || _closing
    color: "transparent"
    exclusiveZone: 0
    // No anchors: centred by the compositor. Same proportions as the rofi theme (35% x 50%).
    implicitWidth: Math.round(Math.max(480, Math.min(820, scrW * 0.35))) + 24
    implicitHeight: Math.round(Math.max(360, Math.min(700, scrH * 0.5))) + 24

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:clipboard"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function open() { PopupSettings.clipboardOpen = true }
    function close() { PopupSettings.clipboardOpen = false }
    function toggle() { PopupSettings.clipboardOpen = !PopupSettings.clipboardOpen }

    // ---- the history ----
    // { id, text, image, info }  (cliphist list: "<id>\t<one-line preview>", images read "[[ binary data 34 KiB png 1280x720 ]]")
    property var entries: []
    property string query: ""
    property int cur: 0
    property bool wipeArmed: false
    property bool loaded: false

    readonly property var filtered: {
        const q = popup.query.trim().toLowerCase()
        if (q === "") return popup.entries
            return popup.entries.filter(function (e) { return (e.image ? "image " + e.info : e.text).toLowerCase().indexOf(q) >= 0 })
    }
    onFilteredChanged: popup.cur = Math.max(0, Math.min(popup.cur, popup.filtered.length - 1))

    function parse(raw) {
        const out = []
        const lines = raw.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const ln = lines[i]
            const t = ln.indexOf("\t")
            if (t <= 0) continue
                const id = ln.substring(0, t)
                const body = ln.substring(t + 1)
                const m = /^\[\[ binary data (.*) \]\]$/.exec(body)
                out.push({ id: id, text: body, image: m !== null, info: m ? m[1] : "" })
        }
        popup.entries = out
        popup.loaded = true
        popup.cur = 0
    }
    function refresh() { if (!lister.running) lister.running = true }

    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector { onStreamFinished: popup.parse(text) }
    }

    function pick(entry) {
        if (!entry) return
            Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "_", entry.id])
            popup.close()
    }
    function remove(entry) {
        if (!entry) return
            Quickshell.execDetached(["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist delete", "_", entry.id])
            popup.entries = popup.entries.filter(function (e) { return e.id !== entry.id })
    }
    function wipe() {
        Quickshell.execDetached(["cliphist", "wipe"])
        popup.entries = []
        popup.wipeArmed = false
    }
    function move(d) {
        const n = popup.filtered.length
        if (n === 0) return
            popup.cur = Math.max(0, Math.min(n - 1, popup.cur + d))
            list.positionViewAtIndex(popup.cur, ListView.Contain)
    }

    onShownChanged: {
        if (shown) {
            hideTimer.stop()
            _closing = false
            query = ""
            wipeArmed = false
            cur = 0
            refresh()
            focusTimer.restart()
        } else {
            _closing = true
            hideTimer.restart()
        }
    }
    Timer { id: hideTimer; interval: popup.fadeMs + 60; onTriggered: popup._closing = false }
    Timer { id: focusTimer; interval: 60; onTriggered: { search.text = ""; search.forceActiveFocus() } }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.shown
        onDismissed: popup.close()
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { popup.toggle() }
        function open(): void { popup.open() }
        function close(): void { popup.close() }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 12
        opacity: popup.shown ? 1 : 0
        scale: popup.shown ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: popup.fadeMs } }
        Behavior on scale {
            SpringAnimation {
                spring: Animations.panelSlideSpring
                damping: Animations.panelSlideDamping
                mass: Animations.panelSlideMass
            }
        }

        GlassPanel {
            anchors.fill: parent
            radius: PopupSettings.radiusOf("clipboard")

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ---- search ----
                TextField {
                    id: search
                    Layout.fillWidth: true
                    implicitHeight: 34
                    selectByMouse: true
                    placeholderText: "Search clipboard..."
                    color: Theme.foreground
                    placeholderTextColor: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    // border follows Settings > Theme > Border
                    background: FieldBorder { radius: Theme.radiusSm; focused: search.activeFocus }
                    onTextChanged: { popup.query = text; popup.cur = 0 }
                    Keys.onPressed: (event) => {
                        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                        switch (event.key) {
                            case Qt.Key_Escape: popup.close(); event.accepted = true; break
                            case Qt.Key_Return:
                            case Qt.Key_Enter: popup.pick(popup.filtered[popup.cur]); event.accepted = true; break
                            case Qt.Key_Down: popup.move(1); event.accepted = true; break
                            case Qt.Key_Up: popup.move(-1); event.accepted = true; break
                            case Qt.Key_Tab: popup.move(1); event.accepted = true; break
                            case Qt.Key_Backtab: popup.move(-1); event.accepted = true; break
                            case Qt.Key_PageDown: popup.move(6); event.accepted = true; break
                            case Qt.Key_PageUp: popup.move(-6); event.accepted = true; break
                            case Qt.Key_Delete:
                                if (ctrl) { popup.remove(popup.filtered[popup.cur]); event.accepted = true }
                                break
                        }
                    }
                }

                // ---- the list ----
                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    boundsBehavior: Flickable.StopAtBounds
                    model: popup.filtered
                    currentIndex: popup.cur

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === popup.cur
                        readonly property bool hot: rowMouse.containsMouse || delMouse.containsMouse

                        width: ListView.view.width
                        height: 38
                        radius: Theme.radiusSm
                        color: selected ? Theme.hoverBgStrong : (hot ? Theme.hoverBg : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }

                        MouseArea {
                            id: rowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: popup.cur = row.index
                            onClicked: popup.pick(row.modelData)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 8

                            // images are listed with their size
                            Rectangle {
                                visible: row.modelData.image
                                implicitWidth: tag.implicitWidth + 12
                                implicitHeight: tag.implicitHeight + 4
                                radius: height / 2
                                color: "transparent"
                                border.width: 1
                                border.color: Theme.textDim
                                Text {
                                    id: tag
                                    anchors.centerIn: parent
                                    text: "Image"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                    font.bold: true
                                }
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row.modelData.image ? row.modelData.info : row.modelData.text
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }
                            // remove this one entry
                            Item {
                                implicitWidth: 22
                                implicitHeight: 22
                                opacity: row.hot || row.selected ? 0.8 : 0
                                Behavior on opacity { NumberAnimation { duration: 100 } }
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u00d7"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize + 4
                                }
                                MouseArea {
                                    id: delMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: popup.remove(row.modelData)
                                }
                            }
                        }
                    }

                    // nothing to show
                    Text {
                        anchors.centerIn: parent
                        visible: popup.filtered.length === 0
                        horizontalAlignment: Text.AlignHCenter
                        text: !popup.loaded ? "" : (popup.query.trim() !== "" ? "Nothing matches" : "The clipboard history is empty.\nCopy something, or check that cliphist is running.")
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }

                // ---- footer ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: "Enter copy   Esc close   Ctrl+Del remove"
                        color: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeXs
                    }
                    GlassButton {
                        visible: popup.entries.length > 0
                        text: popup.wipeArmed ? "Really clear all?" : "Clear all"
                        implicitHeight: 26
                        onClicked: { if (popup.wipeArmed) popup.wipe(); else popup.wipeArmed = true }
                    }
                }
            }
        }
    }
}
