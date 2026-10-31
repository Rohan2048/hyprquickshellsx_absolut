pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../Services"
import "../Theme"
import QtQuick.Effects
PanelWindow {
    id: overview

    property int columns: 5
    property int selected: 0
    property bool hasInteracted: false

    WlrLayershell.namespace: "quickshell:workspaceOverview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    visible: false

    function open() {
        WorkspaceOverviewService.refresh()
        const activeIdx = WorkspaceOverviewService.slots.findIndex(s => s.active)
        selected = activeIdx >= 0 ? activeIdx : 0
        hasInteracted = false
        visible = true
    }

    function close() { visible = false }

    function toggle() {
        if (!visible) {
            open()
        } else {
            selected = (selected + 1) % 10
            hasInteracted = true
        }
    }

    function selectPrevious() {
        if (!visible) {
            open()
        } else {
            selected = (selected + 9) % 10
            hasInteracted = true
        }
    }

    function confirm() {
        WorkspaceOverviewService.switchTo(selected)
        close()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "workspaceOverviewToggle"
        description: "Toggle workspace overview / advance selection on repeat"
        onPressed: overview.toggle()
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "workspaceOverviewConfirm"
        description: "Confirm workspace overview selection on Alt release"
        onPressed: if (overview.visible) overview.confirm()
        onReleased: if (overview.visible) overview.confirm()
    }

    IpcHandler {
        target: "workspaceOverview"
        function toggle() { overview.toggle() }
        function open() { overview.open() }
        function close() { overview.close() }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: overview.close()
    }

    FocusScope {
        anchors.centerIn: parent
        width: panel.width
        height: panel.height
        focus: overview.visible

        Keys.onPressed: (event) => {
            switch (event.key) {
                case Qt.Key_Escape: overview.close(); break
                case Qt.Key_Return:
                case Qt.Key_Enter: overview.confirm(); break
                case Qt.Key_Tab:
                case Qt.Key_Right: overview.selected = (overview.selected + 1) % 10; overview.hasInteracted = true; break
                case Qt.Key_Backtab:
                case Qt.Key_Left: overview.selected = (overview.selected + 9) % 10; overview.hasInteracted = true; break
                case Qt.Key_Down: overview.selected = (overview.selected + overview.columns) % 10; overview.hasInteracted = true; break
                case Qt.Key_Up: overview.selected = (overview.selected + 10 - overview.columns) % 10; overview.hasInteracted = true; break
                default: return
            }
            event.accepted = true
        }

        Rectangle {
            id: panel
            width: grid.implicitWidth + 48
            height: grid.implicitHeight + 48
            radius: 24
            color: Theme.isDark ? Qt.rgba(0.08, 0.08, 0.1, 0.72) : Qt.rgba(0.95, 0.95, 0.96, 0.85)
            border.width: 1
            border.color: Theme.color3

            opacity: overview.visible ? 1 : 0
            scale: overview.visible ? 1 : 0.94
            Behavior on opacity { NumberAnimation { duration: Animations.panelFadeDuration } }
            Behavior on scale {
                SpringAnimation {
                    spring: Animations.panelSlideSpring
                    damping: Animations.panelSlideDamping
                    mass: Animations.panelSlideMass
                }
            }

            GridLayout {
                id: grid
                anchors.centerIn: parent
                columns: overview.columns
                rowSpacing: 14
                columnSpacing: 14

                Repeater {
                    model: WorkspaceOverviewService.slots

                    Rectangle {
                        id: cell
                        required property var modelData
                        readonly property bool isSelected: modelData.slot === overview.selected
                        property bool pulseOn: false
                        property bool warmedUp: false

                        onIsSelectedChanged: {
                            if (isSelected) cell.warmedUp = false
                        }

                        Layout.preferredWidth: 176
                        Layout.preferredHeight: 108
                        radius: 14
                        color: modelData.active
                        ? Theme.color3
                        : (modelData.occupied ? Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.10)
                        : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.03))
                        border.width: isSelected ? 2 : 1
                        border.color: isSelected ? Theme.color3 : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.08)
                        scale: isSelected ? 1.05 : 1.0
                        clip: true

                        Behavior on scale {
                            SpringAnimation {
                                spring: Animations.trackSpring
                                damping: Animations.trackDamping
                                mass: Animations.trackMass
                            }
                        }
                        Behavior on color {
                            ColorAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard }
                        }

                        // While the cell is selected but hasn't produced its
                        // first frame yet, pulse fast (120ms) so the initial
                        // preview appears almost immediately instead of
                        // waiting for the slow 500ms cadence. Once a frame
                        // lands (warmedUp), the interval jumps to the normal
                        // 500ms — a ~100ms capture window every ~500ms,
                        // instead of holding a continuous screencopy stream
                        // open.
                        Timer {
                            id: pulseTimer
                            interval: cell.warmedUp ? 500 : 120
                            repeat: true
                            triggeredOnStart: true
                            running: overview.visible && overview.hasInteracted && cell.isSelected
                            onTriggered: { cell.pulseOn = true; pulseOffTimer.restart() }
                        }
                        Timer {
                            id: pulseOffTimer
                            interval: 100
                            onTriggered: cell.pulseOn = false
                        }

                        Item {
                            id: previewLayer
                            anchors.fill: parent
                            anchors.margins: 6
                            clip: true
                            visible: cell.modelData.toplevels.length > 0

                            readonly property real areaW: cell.modelData.usableWidth > 0 ? cell.modelData.usableWidth : 1920
                            readonly property real areaH: cell.modelData.usableHeight > 0 ? cell.modelData.usableHeight : 1080
                            readonly property real areaX: cell.modelData.usableX
                            readonly property real areaY: cell.modelData.usableY
                            readonly property real scaleX: width / areaW
                            readonly property real scaleY: height / areaH

                            Repeater {
                                model: cell.modelData.toplevels

                                ScreencopyView {
                                    id: preview
                                    required property var modelData
                                    readonly property var ipc: modelData.lastIpcObject

                                    captureSource: modelData.wayland ?? null
                                    live: overview.visible && overview.hasInteracted && cell.isSelected && cell.pulseOn

                                    onHasContentChanged: if (hasContent) cell.warmedUp = true

                                    x: ipc && ipc.at ? (ipc.at[0] - previewLayer.areaX) * previewLayer.scaleX : 0
                                    y: ipc && ipc.at ? (ipc.at[1] - previewLayer.areaY) * previewLayer.scaleY : 0
                                    width: ipc && ipc.size ? Math.max(4, ipc.size[0] * previewLayer.scaleX) : 0
                                    height: ipc && ipc.size ? Math.max(4, ipc.size[1] * previewLayer.scaleY) : 0
                                    visible: hasContent

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.foreground
                                        radius: 3
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !previewLayer.visible
                            text: modelData.occupied ? "" : "·"
                            color: Theme.foreground
                            font.pixelSize: 20
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: { overview.selected = modelData.slot; overview.hasInteracted = true }
                            onClicked: { overview.selected = modelData.slot; overview.confirm() }
                        }
                    }
                }
            }
        }
    }
}
