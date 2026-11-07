import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "../Theme"
import "../Widgets"
import "../Services"
import "../SBS"

// Direct port of (defwidget battery-popup-widget) — the "47% / 1:24 remaining /
// Turbo Mode / Prioritise / Optimise For" panel from the screenshot.
PanelWindow {
    id: popup
    readonly property real uiScale: PopupSettings.scaleOf("battery")
    visible: false

    implicitWidth: (360 + PopupSettings.sizeW("battery")) * uiScale
    implicitHeight: (contentCol.baseHeight + PopupSettings.sizeH("battery")) * uiScale

    property var tracking: null

    property real iconCenterOffset: 0

    property real barBottomOffset: 32

    // Max pixels the popup may overhang either side of the bar's own
    // rendered edges (not the screen edges) — keeps it visually anchored
    // to the bar for a tight "floaty" look instead of drifting across the
    // screen when the anchor icon sits near a bar edge.
    readonly property real horizontalOverhang: 5

    // Gap between the bar's top edge and the popup's bottom edge, so the
    // popup sits just above the bar instead of flush against it.
    readonly property real verticalGap: 3

    readonly property real effectiveRightMargin: {
        var screenW = popup.screen ? popup.screen.width : implicitWidth
        var desired = iconCenterOffset - implicitWidth / 2

        if (!popup.tracking) {
            var maxRight = Math.max(0, screenW - implicitWidth)
            return Math.min(Math.max(0, desired), maxRight)
        }

        // rightMargin is measured from the screen's right edge, so bar
        // edges (measured from the screen's left edge) need converting:
        //   popup's right edge may sit at most `horizontalOverhang` px
        //   past the bar's right edge  -> sets the minimum right margin
        //   popup's left edge may sit at most `horizontalOverhang` px
        //   past the bar's left edge   -> sets the maximum right margin
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

    // Horizontal tail position, measured from the popup's own left edge.
    // Clamped inward so it never renders past the panel's rounded corners.


    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:popup:battery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // eww: (geometry :anchor "bottom right") — bar sits at the screen bottom
    anchors { bottom: true; right: true; left: false }
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
        }
    }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.visible
        onDismissed: popup.close()
    }

    PopupScale {
        anchors.fill: parent
        popupId: "battery"

        GlassPanel {
            id: glassPanel
            anchors.fill: parent
            radius: PopupSettings.radiusOf("battery")
            tracking: popup.tracking

            // ---- Popup entrance/exit (fade + horizontal motion blur) ----
            property real entranceProgress: 1
            property real exitProgress: 1
            property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
            property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength

            opacity: entranceProgress * exitProgress
            layer.enabled: entranceProgress < 1 || exitProgress < 1
            layer.effect: DirectionalBlur {
                angle: Animations.slideBlurHorizontalAngle
                length: Math.max(glassPanel.entranceBlur, glassPanel.exitBlur)
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

            // stays at the normal size; whatever does not fit (graphs, moved pieces) scrolls
            SmoothFlickable {
                id: scroller
                anchors.fill: parent
                contentWidth: width
                contentHeight: contentCol.implicitHeight
                interactive: contentHeight > height + 0.5

                BatteryContent {
                    id: contentCol
                    width: scroller.width
                    height: implicitHeight
                }
            }
        }
    }
}
