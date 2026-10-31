import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// Quickshell version of `rofi -show drun`: a big centred panel with the applications as a
// grid (or a list with descriptions). Used when Settings > Popups > Applications has
// Style = Quickshell; the launcher keybind (scripts/launcher.sh) calls
//     qs ipc call apps toggle
// Fade + spring scale like the Settings popup. Draws with the shell theme.
PanelWindow {
    id: popup

    readonly property bool shown: PopupSettings.appsOpen
    property bool _closing: false
    readonly property int fadeMs: Animations.panelFadeDuration

    readonly property real scrW: popup.screen ? popup.screen.width : 1920
    readonly property real scrH: popup.screen ? popup.screen.height : 1080

    visible: shown || _closing
    color: "transparent"
    exclusiveZone: 0
    // No anchors: centred by the compositor. Same proportions as the rofi theme (60% x 60%).
    implicitWidth: Math.round(Math.max(520, Math.min(1100, scrW * 0.6))) + 24
    implicitHeight: Math.round(Math.max(380, Math.min(760, scrH * 0.6))) + 24

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:apps"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function open() { PopupSettings.appsOpen = true }
    function close() { PopupSettings.appsOpen = false }
    function toggle() { PopupSettings.appsOpen = !PopupSettings.appsOpen }

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
    Timer { id: focusTimer; interval: 60; onTriggered: picker.reset() }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.shown
        onDismissed: popup.close()
    }

    IpcHandler {
        target: "apps"
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
            radius: PopupSettings.radiusOf("apps")

            AppPicker {
                id: picker
                anchors.fill: parent
                anchors.margins: 14
                onPicked: (entry) => { popup.close(); entry.execute() }
                onDismissed: popup.close()
            }
        }
    }
}
