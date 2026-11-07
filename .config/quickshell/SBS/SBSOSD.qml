import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// SBSOSD.qml — minimal Super Battery Saver on-screen-display. Same
// IPC contract as the normal OSDPopup.qml ("osd" target, show(kind, value))
// but flat black/white, no icons, no blur, no Behavior/NumberAnimation --
// matches the rest of this shell being built minimal from the start.
// Owns the "osd" target exclusively while SBS is active; OSDPopup.qml is
// unloaded via osdPopupLoader in shell.qml so the two never coexist.
PanelWindow {
    id: root

    WlrLayershell.namespace: "quickshell:sbs-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0
    color: "transparent"

    anchors { bottom: true }
    margins.bottom: 50

    implicitWidth: 200
    implicitHeight: 56
    visible: false

    property string kind: ""
    property real pillValue: 0
    property bool showPill: false

    readonly property var toggleLabels: ({
        "volume_muted": "Muted",
        "volume_unmuted": "Unmuted",
        "mic_on": "Mic On",
        "mic_off": "Mic Off",
        "touchpad_on": "Touchpad On",
        "touchpad_off": "Touchpad Off",
        "vnc_on": "Screen Share On",
        "vnc_off": "Screen Share Off"
    })

    IpcHandler {
        target: "osd"

        function show(kind: string, value: string): void {
            const v = (value && value.length > 0) ? parseFloat(value) : 0
            root._apply(kind, isNaN(v) ? 0 : v)
        }
    }

    function _apply(kind, value) {
        root.kind = kind

        if (kind === "volume") {
            root.showPill = true
            root.pillValue = Math.max(0, Math.min(1, value))
            label.text = "Volume " + Math.round(value * 100) + "%"
        } else if (kind === "brightness") {
            root.showPill = true
            root.pillValue = Math.max(0, Math.min(1, value / 100))
            label.text = "Brightness " + Math.round(value) + "%"
        } else {
            root.showPill = false
            label.text = root.toggleLabels[kind] || kind
        }

        hideTimer.restart()
        root.visible = true
    }
    Timer {
        id: hideTimer
        interval: 1700
        onTriggered: root.visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        border.color: "white"
        border.width: 1
        radius: 6

        Column {
            anchors.centerIn: parent
            spacing: 6

            Text {
                id: label
                anchors.horizontalCenter: parent.horizontalCenter
                color: "white"
                font.pixelSize: 12
                font.family: "SF Pro Display"
            }

            Row {
                id: pillRow
                visible: root.showPill
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 1

                readonly property int segments: 10
                readonly property int activeSegments: Math.round(root.pillValue * segments)

                Repeater {
                    model: pillRow.segments
                    delegate: Rectangle {
                        required property int index
                        width: 14
                        height: 4
                        color: index < pillRow.activeSegments ? "white" : "#444444"
                    }
                }
            }
        }
    }
}
