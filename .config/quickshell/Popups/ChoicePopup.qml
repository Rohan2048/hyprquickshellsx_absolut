import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// Quickshell style of the three keybind menus that used to be rofi-only:
//   powermenu  (SUPER + Esc)          Shutdown / Reboot / Suspend / Lock / Logout
//   schedule   (SUPER + SHIFT + Esc)  action list, then a HH:MM box
//   hdmi       (ALT + S)              Laptop Only / External Only / Mirror / Extend
//   animscale  (ALT + R)              Animation scaling list (Settings > Popups > Animation scale)
// Chosen in Settings > Popups > Power & display. The scripts call it through
// scripts/qs-pick.sh, which runs
//     qs ipc call choice list  <id> <title> "<a|b|c>" <result file>
//     qs ipc call choice input <id> <title> <placeholder> <result file>
// and waits for the result file: this popup writes the picked text into it (an empty file
// means cancelled: Esc, the Cancel button or a click outside). Scaled by Settings >
// Popups > General (per menu id), closes on click-away like every other popup.
PanelWindow {
    id: popup

    property string reqId: "powermenu"
    property string mode: "list"            // "list" | "input"
    property string title: ""
    property var items: []
    property string placeholder: ""
    property string resultFile: ""          // "" = preview from Settings (nothing is written)
    property bool shown: false
    property bool _closing: false
    property bool _done: true
    property int current: 0

    readonly property int fadeMs: Animations.panelFadeDuration
    readonly property real uiScale: PopupSettings.scaleOf(popup.reqId)
    readonly property real baseW: popup.mode === "input" ? 320 : 300

    visible: shown || _closing
    color: "transparent"
    exclusiveZone: 0
    // No anchors: the compositor centres the window. 12px margin around the panel for the scale-in.
    implicitWidth: Math.round(baseW * uiScale) + 24
    implicitHeight: Math.round(panel.implicitHeight * uiScale) + 24

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:choice"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // ---- result ----
    Process { id: writer }
    function finish(value) {
        if (popup._done) return
            popup._done = true
            if (popup.resultFile !== "") {
                // write to a temp name then rename, so the script never reads a half-written file
                writer.command = ["sh", "-c", "printf '%s' \"$1\" > \"$2.tmp\" && mv -f \"$2.tmp\" \"$2\"", "sh", value, popup.resultFile]
                writer.running = true
            }
            popup.shown = false
    }
    function cancel() { popup.finish("") }

    function _begin(id, mode, title, items, placeholder, file) {
        if (!popup._done) popup.finish("")       // a request is still open: cancel it first
            popup.reqId = id
            popup.mode = mode
            popup.title = title
            popup.items = items
            popup.placeholder = placeholder
            popup.resultFile = file
            popup.current = 0
            field.text = ""
            popup._done = false
            popup.shown = true
    }
    function openList(id, title, itemsStr, file) {
        const arr = String(itemsStr).split("|").filter(function (x) { return x.trim() !== "" })
        popup._begin(id, "list", title, arr, "", file)
    }
    function openInput(id, title, placeholder, file) {
        popup._begin(id, "input", title, [], placeholder, file)
    }

    onShownChanged: {
        if (shown) {
            hideTimer.stop()
            _closing = false
            focusTimer.restart()
        } else {
            _closing = true
            hideTimer.restart()
        }
    }
    Timer { id: hideTimer; interval: popup.fadeMs + 60; onTriggered: popup._closing = false }
    Timer {
        id: focusTimer
        interval: 60
        onTriggered: { if (popup.mode === "input") field.forceActiveFocus(); else root.forceActiveFocus() }
    }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.shown
        onDismissed: popup.cancel()
    }

    IpcHandler {
        target: "choice"
        function list(menu: string, title: string, items: string, file: string): void { popup.openList(menu, title, items, file) }
        function input(menu: string, title: string, placeholder: string, file: string): void { popup.openInput(menu, title, placeholder, file) }
        function close(): void { popup.cancel() }
    }

    // "Try it" buttons in Settings > Popups > Power & display
    Connections {
        target: PopupSettings
        function onChoicePreviewChanged() {
            const id = PopupSettings.choicePreview
            if (id === "") return
                PopupSettings.choicePreview = ""
                if (id === "powermenu") popup.openList(id, "Power", "Shutdown|Reboot|Suspend|Lock|Logout", "")
                    else if (id === "schedule") popup.openList(id, "Schedule Action", "Shutdown|Suspend|Reboot|Cancel Scheduled", "")
                        else if (id === "hdmi") popup.openList(id, "Display Mode", "Laptop Only|External Only|Mirror|Extend", "")
                            else if (id === "animscale") popup.openList(id, "Animation Scaling", "0.75\u00d7|1.00\u00d7|1.25\u00d7|1.50\u00d7|2.00\u00d7|Auto (Refresh Rate based)", "")
        }
    }

    Item {
        id: root
        anchors.fill: parent
        anchors.margins: 12
        focus: popup.shown && popup.mode === "list"
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
        Keys.onPressed: (event) => {
            const n = popup.items.length
            if (event.key === Qt.Key_Escape) { popup.cancel(); event.accepted = true }
            else if (popup.mode === "list" && n > 0) {
                if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || event.key === Qt.Key_J) {
                    popup.current = (popup.current + 1) % n; event.accepted = true
                } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab || event.key === Qt.Key_K) {
                    popup.current = (popup.current + n - 1) % n; event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    popup.finish(popup.items[popup.current]); event.accepted = true
                }
            }
        }

        // the panel is laid out at its normal size and scaled as a whole (PopupScale)
        PopupScale {
            anchors.fill: parent
            popupId: popup.reqId

            GlassPanel {
                id: panel
                width: popup.baseW
                implicitHeight: col.implicitHeight + 32
                height: implicitHeight
                radius: PopupSettings.radiusOf(popup.reqId)

                ColumnLayout {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    GradientText {
                        text: popup.title
                        visible: popup.title !== ""
                        font.family: Theme.fontFamily
                        font.bold: true
                        font.pixelSize: Theme.fontSizeLg
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Repeater {
                        model: popup.mode === "list" ? popup.items : []
                        delegate: GlassButton {
                            required property int index
                            required property string modelData
                            Layout.fillWidth: true
                            implicitHeight: 38
                            text: modelData
                            active: popup.current === index
                            onHoveredChanged: if (hovered) popup.current = index
                            onClicked: popup.finish(modelData)
                        }
                    }

                    TextField {
                        id: field
                        visible: popup.mode === "input"
                        Layout.fillWidth: true
                        implicitHeight: 34
                        selectByMouse: true
                        horizontalAlignment: TextInput.AlignHCenter
                        placeholderText: popup.placeholder
                        color: Theme.foreground
                        placeholderTextColor: Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        background: Rectangle {
                            radius: Theme.radiusSm
                            color: "transparent"
                            border.width: 1
                            border.color: field.activeFocus ? Theme.accentActive : Theme.borderMuted
                        }
                        Keys.onReturnPressed: popup.finish(text.trim())
                        Keys.onEnterPressed: popup.finish(text.trim())
                        Keys.onEscapePressed: popup.cancel()
                    }
                }
            }
        }
    }
}
