import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "../Theme"
import "../Widgets"
import "../Services"

// Single-page version of DateTimePopup: same window, positioning against the
// bar (PopupTracking), slide-up + vertical blur open/close, and click-away
// closing, but it hosts just one Clock page (TimerPage / StopwatchPage) with
// no pager arrows and no calendar.
//
// Used by the bar's timer and stopwatch buttons, which only exist while the
// timer / stopwatch is active. `pageActive` is wired to that; when it goes
// false the popup closes itself (same as MusicPopup does for music).
PanelWindow {
    id: popup
    readonly property real uiScale: PopupSettings.scaleOf("clock")
    visible: false

    implicitWidth: 300 * uiScale
    implicitHeight: (stackCol.height + 28) * uiScale

    property var tracking: null

    // e.g. "../Clock/TimerPage.qml" (resolves the same from Bar/ and Popups/).
    property url pageSource: ""
    property bool pageActive: true

    color: "transparent"
    exclusiveZone: 0

    // Deliberately the same namespace as DateTimePopup so whatever compositor
    // layer rules (blur etc.) you already have for it apply here too.
    WlrLayershell.namespace: "datetime-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Distance from the screen's right edge to the button's horizontal center.
    property real iconCenterOffset: 0
    // Distance from the screen's bottom edge to the bar's own top edge.
    property real barBottomOffset: 32

    readonly property real horizontalOverhang: 5
    readonly property real verticalGap: 3
    anchors { bottom: true; left: false; right: true }
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

    property real openProgress: 0

    function toggle() {
        if (popup.openProgress > 0) {
            popup.close()
        } else {
            closeAnim.stop()
            mapDelay.stop()
            popup.visible = true
            mapDelay.restart()
        }
    }

    function close() {
        mapDelay.stop()
        openAnim.stop()
        if (popup.openProgress > 0) closeAnim.restart()
            else popup.visible = false
    }

    // The button this popup hangs off disappears when the timer/stopwatch is
    // reset, so don't leave the popup floating over nothing.
    onPageActiveChanged: {
        if (!pageActive && popup.visible) popup.close()
    }

    Timer {
        id: mapDelay
        interval: 32
        onTriggered: openAnim.restart()
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

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.visible
        onDismissed: popup.close()
    }

    PopupScale {
        anchors.fill: parent
        popupId: "clock"

        Column {
            id: stackCol
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 300
            spacing: 4

            y: (1 - popup.openProgress) * (height + 28)
            opacity: popup.openProgress
            property real blurAmount: Math.sin(Math.PI * popup.openProgress) * Animations.slideBlurVerticalLength * 1.5

            // Threshold rather than > 0: sin(PI * 1) isn't exactly 0 in floating
            // point (see DateTimePopup), so a strict check would leave the layer
            // on, softening the text, the whole time the popup sits open.
            layer.enabled: stackCol.blurAmount > 0.05
            layer.effect: DirectionalBlur {
                angle: Animations.slideBlurVerticalAngle
                length: stackCol.blurAmount
                samples: Animations.slideBlurSamples
                transparentBorder: true
            }

            GlassPanel {
                radius: PopupSettings.radiusOf("clock")
                tracking: popup.tracking
                width: parent.width
                height: pageBox.implicitHeight + 28

                Item {
                    id: pageBox
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 14
                    width: parent.width - 28
                    implicitHeight: pageLoader.item ? pageLoader.item.implicitHeight : 0
                    clip: true

                    // Persistent (never torn down), like DateTimePopup's loaders,
                    // so opening the popup doesn't pay a QML instantiation cost.
                    // The page is a stateless view over TimerService /
                    // StopwatchService, so keeping it alive costs nothing.
                    Loader {
                        id: pageLoader
                        width: parent.width
                        height: item ? item.implicitHeight : 0
                        source: popup.pageSource
                        asynchronous: false
                    }
                }
            }
        }
    }
}
