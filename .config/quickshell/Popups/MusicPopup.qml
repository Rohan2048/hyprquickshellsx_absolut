pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../Services"
import "../Theme"
import "../Widgets"

PanelWindow {
    id: popup
    readonly property real uiScale: PopupSettings.scaleOf("music")
    visible: false

    property var tracking: null

    WlrLayershell.namespace: "quickshell:musicPopup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property real iconCenterOffset: 0
    property real barBottomOffset: 32
    readonly property real horizontalOverhang: 5
    readonly property real verticalGap: 3

    anchors { bottom: true; left: true }

    readonly property real effectiveLeftMargin: {
        var screenW = popup.screen ? popup.screen.width : implicitWidth
        var desired = iconCenterOffset - implicitWidth / 2

        if (!popup.tracking) {
            var maxLeft = Math.max(0, screenW - implicitWidth)
            return Math.min(Math.max(0, desired), maxLeft)
        }

        var minLeftMargin = popup.tracking.barLeftEdge - horizontalOverhang
        var maxLeftMargin = popup.tracking.barRightEdge + horizontalOverhang - implicitWidth

        var lo, hi
        if (maxLeftMargin >= minLeftMargin) {
            lo = minLeftMargin
            hi = maxLeftMargin
        } else {
            lo = minLeftMargin
            hi = minLeftMargin
        }
        return Math.min(Math.max(lo, desired), hi)
    }

    property real smoothedLeftMargin: effectiveLeftMargin
    Behavior on smoothedLeftMargin {
        NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
    }

    margins {
        bottom: barBottomOffset + verticalGap
        left: smoothedLeftMargin
    }

    implicitWidth: (340 + PopupSettings.sizeW("music")) * uiScale
    implicitHeight: content.implicitHeight * uiScale
    color: "transparent"

    property real openProgress: 0

    // Lets MusicPlayerService run its 1 s position poll only while shown.
    onVisibleChanged: MusicPlayerService.popupOpen = visible

    function open() {
        closeAnim.stop()
        popup.visible = true
        openAnim.restart()
    }
    function close() {
        openAnim.stop()
        closeAnim.restart()
    }
    function toggle() {
        if (popup.openProgress > 0) popup.close()
            else popup.open()
    }

    NumberAnimation {
        id: openAnim
        target: popup; property: "openProgress"
        to: 1
        duration: Animations.pageSlideDuration
        easing.type: Animations.pageSlideEasingOut
    }
    NumberAnimation {
        id: closeAnim
        target: popup; property: "openProgress"
        to: 0
        duration: Animations.pageSlideDuration
        easing.type: Animations.pageSlideEasingIn
        onStopped: popup.visible = false
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "musicPopupToggle"
        description: "Toggle music player popup"
        onPressed: popup.toggle()
    }

    IpcHandler {
        target: "musicPopup"
        function toggle() { popup.toggle() }
        function open() { popup.open() }
        function close() { popup.close() }
    }

    Connections {
        target: MusicPlayerService
        function onActiveChanged() {
            if (!MusicPlayerService.active)
                popup.close()
        }
    }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.visible
        onDismissed: popup.close()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: popup.close()
        z: -1
    }

    PopupScale {
        anchors.fill: parent
        popupId: "music"

        GlassPanel {
            id: content
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: 340 + PopupSettings.sizeW("music")
            implicitHeight: body.rootCol.implicitHeight + 36 + PopupSettings.sizeH("music")
            radius: PopupSettings.radiusOf("music")
            tracking: popup.tracking

            y: (1 - popup.openProgress) * (height + 36)
            opacity: popup.openProgress
            property real blurAmount: Math.sin(Math.PI * popup.openProgress) * Animations.slideBlurVerticalLength

            layer.enabled: content.blurAmount > 0.05
            layer.effect: DirectionalBlur {
                angle: Animations.slideBlurVerticalAngle
                length: content.blurAmount
                samples: Animations.slideBlurSamples
                transparentBorder: true
            }

            MusicContent {
                id: body
                anchors.fill: parent
                host: popup
            }

        }
    }
}
