import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// Quickshell-style "add shortcut" picker (the + button of the shortcuts dock when
// Settings > Popups > Shortcuts palette has Style = Quickshell): the same app picker as the
// launcher, grid or list, but picking an app stores it as a shortcut instead of launching it.
PanelWindow {
    id: popup

    readonly property bool shown: Shortcuts.pickerOpen
    property bool _closing: false
    readonly property int fadeMs: Animations.panelFadeDuration

    readonly property real scrW: popup.screen ? popup.screen.width : 1920
    readonly property real scrH: popup.screen ? popup.screen.height : 1080

    visible: shown || _closing
    color: "transparent"
    exclusiveZone: 0
    implicitWidth: Math.round(Math.max(520, Math.min(1000, scrW * 0.55))) + 24 + PopupSettings.sizeW("shortcuts")
    implicitHeight: Math.round(Math.max(380, Math.min(720, scrH * 0.6))) + 24 + PopupSettings.sizeH("shortcuts")

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:shortcut-picker"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Shortcuts.pickerOpen = false }

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
    Timer { id: focusTimer; interval: 60; onTriggered: body.picker.reset() }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.shown
        onDismissed: popup.close()
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
            radius: PopupSettings.radiusOf("shortcuts")

            ShortcutPickerContent {
                id: body
                anchors.fill: parent
                host: popup
            }

        }
    }
}
