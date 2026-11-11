// VolumePopup.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "../Theme"
import "../Widgets"
import "../Services"

PanelWindow {
    id: popup
    readonly property real uiScale: PopupSettings.scaleOf("volume")
    visible: false

    implicitWidth: (260 + PopupSettings.sizeW("volume")) * uiScale
    implicitHeight: (220 + PopupSettings.sizeH("volume")) * uiScale
    // Behavior on implicitHeight {
    //     NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard }
    // }

    property var tracking: null

    // 0 = devices page, 1 = raw-ports (settings) page
    property int page: 0

    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "volume-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property real iconCenterOffset: 0
    property real barBottomOffset: 32

    readonly property real horizontalOverhang: 5
    readonly property real verticalGap: 3

    anchors { bottom: true; right: true }
    readonly property real effectiveRightMargin: {
        var screenW = popup.screen ? popup.screen.width : implicitWidth
        var desired = iconCenterOffset - implicitWidth / 2

        if (!popup.tracking) {
            var maxRight = Math.max(0, screenW - implicitWidth)
            return Math.min(Math.max(0, desired), maxRight)
        }

        var minRightMargin = screenW - (popup.tracking.barRightEdge + horizontalOverhang)
        var maxRightMargin = screenW - implicitWidth - popup.tracking.barLeftEdge + horizontalOverhang
        var lo = Math.min(minRightMargin, maxRightMargin)
        var hi = Math.max(minRightMargin, maxRightMargin)
        return Math.min(Math.max(lo, desired), hi)
    }
    property real smoothedRightMargin: effectiveRightMargin
    Behavior on smoothedRightMargin {
        NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
    }
    margins {
        bottom: barBottomOffset + verticalGap
        right: smoothedRightMargin
    }
    property bool closing: false

    function toggle() {
        if (popup.closing) return
            if (popup.visible) popup.close()
                else popup.open()
    }
    function open() {
        if (popup.closing) return
            popup.visible = true
    }
    function close() {
        popup.closing = true
        glassPanel.playExit()
        closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: Animations.slideBlurDuration
        onTriggered: {
            popup.visible = false
            popup.closing = false
        }
    }

    onVisibleChanged: {
        if (visible) {
            glassPanel.playEntrance()
            popup.page = 0
            contentCol.rearm()
        }
    }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.visible
        onDismissed: popup.close()
    }
    PopupScale {
        anchors.fill: parent
        popupId: "volume"

        GlassPanel {
            id: glassPanel
            anchors.fill: parent
            radius: PopupSettings.radiusOf("volume")
            tracking: popup.tracking

            property real entranceProgress: 1
            property real exitProgress: 1
            property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
            property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength

            opacity: entranceProgress * exitProgress
            readonly property real currentBlur: Math.max(glassPanel.entranceBlur, glassPanel.exitBlur)
            layer.enabled: glassPanel.currentBlur > 0.05
            layer.effect: DirectionalBlur {
                angle: Animations.slideBlurHorizontalAngle
                length: glassPanel.currentBlur
                samples: Animations.slideBlurSamples
                transparentBorder: true
            }

            NumberAnimation on entranceProgress {
                id: glassPanelEntranceAnim
                from: 0; to: 1
                duration: Animations.slideBlurDuration
                easing.type: Animations.slideBlurEasingOut
                running: false
            }
            NumberAnimation on exitProgress {
                id: glassPanelExitAnim
                from: 1; to: 0
                duration: Animations.slideBlurDuration
                easing.type: Animations.slideBlurEasingIn
                running: false
            }
            function playEntrance() { glassPanelExitAnim.stop(); exitProgress = 1; entranceProgress = 0; glassPanelEntranceAnim.restart() }
            function playExit() { glassPanelEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; glassPanelExitAnim.restart() }

            VolumeContent {
                id: contentCol
                anchors.fill: parent
                page: popup.page
                onPageRequested: (p) => popup.page = p
            }
        }
    }
}
