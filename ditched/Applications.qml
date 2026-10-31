import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import "../Services"
import "../Theme"
import "../Widgets"
import "../Popups"

PanelWindow {
    id: root
    visible: false
    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:popup:applications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors { top: true; bottom: true; left: true; right: true }

    property string query: ""
    property bool closing: false

    readonly property var filteredApps: {
        if (root.query.trim().length === 0) return AppList.apps
            const q = root.query.toLowerCase()
            return AppList.apps.filter(a => a.name.toLowerCase().includes(q))
    }

    function open() {
        if (root.closing) return
        root.query = ""
        root.visible = true
        searchField.forceActiveFocus()
        panel.playEntrance()
        appGrid.introTrigger++
    }
    function close() {
        if (root.closing) return
        root.closing = true
        panel.playExit()
        appGrid.outroTrigger++
        closeTimer.restart()
    }
    function toggle() {
        if (root.visible) root.close()
            else root.open()
    }

    Timer {
        id: closeTimer
        interval: Animations.slideBlurDuration
        onTriggered: {
            root.visible = false
            root.closing = false
        }
    }

    IpcHandler {
        target: "applications"
        function toggle() { root.toggle() }
        function open() { root.open() }
        function close() { root.close() }
    }

    // Click-away dismissal, same pattern as NotificationPopup.
    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    GlassPanel {
        id: panel
        width: parent.width * 0.6
        height: parent.height * 0.6
        anchors.centerIn: parent

        property real entranceProgress: 1
        property real exitProgress: 1
        property real entranceBlurRadius: (1 - entranceProgress) * Animations.panelBlurRadius
        property real exitBlurRadius: (1 - exitProgress) * Animations.panelBlurRadius

        opacity: entranceProgress * exitProgress

        readonly property bool animating: (entranceProgress > 0 && entranceProgress < 1)
        || (exitProgress > 0 && exitProgress < 1)
        // Pre-warm flag: forces layer.enabled true once, silently, right
        // after load - so the GaussianBlur shader compiles at startup
        // instead of on the user's first real open. Cheap because the
        // panel is still invisible (opacity 0) at that point anyway.
        property bool prewarmed: false
        layer.enabled: panel.animating || !panel.prewarmed
        layer.effect: GaussianBlur {
            radius: Math.max(panel.entranceBlurRadius, panel.exitBlurRadius, 0.01)
            samples: Animations.slideBlurSamples
            deviation: radius / 2
            transparentBorder: true
        }

        SpringAnimation on entranceProgress {
            id: panelEntranceAnim
            to: 1
            spring: Animations.panelSlideSpring
            damping: Animations.panelSlideDamping
            mass: Animations.panelSlideMass
            running: false
        }
        SpringAnimation on exitProgress {
            id: panelExitAnim
            to: 0
            spring: Animations.panelSlideSpring
            damping: Animations.panelSlideDamping
            mass: Animations.panelSlideMass
            running: false
        }
        function playEntrance() { panelExitAnim.stop(); exitProgress = 1; entranceProgress = 0; panelEntranceAnim.restart() }
        function playExit() { panelEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; panelExitAnim.restart() }

        Component.onCompleted: {
            // entranceProgress starts at 1 (opacity 1 -> but root.visible is
            // false at this point, so nothing is actually shown on screen).
            // Force the shader to compile now, then flip prewarmed so the
            // real open/close logic takes over the layer.enabled gating.
            entranceProgress = 0.5   // any mid-value forces a non-zero radius once
            prewarmTimer.start()
        }
        Timer {
            id: prewarmTimer
            interval: 16   // one frame is enough for the shader to compile+run once
            repeat: false
            onTriggered: {
                panel.entranceProgress = 1
                panel.prewarmed = true
            }
        }


        MouseArea {
            anchors.fill: parent
            onClicked: (mouse) => { mouse.accepted = true }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "Search..."
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: 14
                background: Rectangle { color: "transparent" }
                onTextChanged: root.query = text
                Keys.onEscapePressed: root.close()
                Keys.onReturnPressed: {
                    if (root.filteredApps.length > 0) {
                        root.launch(root.filteredApps[0])
                    }
                }
            }

            Grid {
                id: appGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.filteredApps
                cellSize: 96
                onActivated: (itemData, index) => root.launch(itemData)
            }
        }
    }

    function launch(app) {
        if (!app || !app.exec) return
            const cmd = app.terminal
            ? ["sh", "-c", `${Theme.terminalExec || "konsole"} -e ${app.exec}`]
            : ["sh", "-c", app.exec]
            Quickshell.execDetached(cmd)
            root.close()
    }
}
