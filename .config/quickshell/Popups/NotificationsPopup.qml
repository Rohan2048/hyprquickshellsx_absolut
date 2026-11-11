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
    visible: false

    // ---- Fixed sizing ----
    // Sizes are expressed as baseValue * effectiveScale, but effectiveScale
    // is now driven ONLY by userScale below — no per-screen auto-scaling.
    // This keeps the popup the exact same pixel size on every monitor
    // regardless of resolution/height, instead of blowing up on 4K panels.

    // Manual override — bump this up/down to size the popup by hand.
    // 1.0 = base size, 1.3 = 30% bigger, 0.8 = 20% smaller.
    property real userScale: 1.05

    // What everything below actually multiplies against.
    readonly property real effectiveScale: userScale * PopupSettings.scaleOf("notifications")

    // Base (reference) dimensions — reduced from the old 400x600.
    readonly property real baseWidth: 320
    readonly property real baseHeight: 460

    implicitWidth: (baseWidth + PopupSettings.sizeW("notifications")) * effectiveScale
    implicitHeight: (baseHeight + PopupSettings.sizeH("notifications")) * effectiveScale

    property var tracking: null

    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:popup:notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Distance from the screen's right edge to the bell icon's horizontal center.
    property real iconCenterOffset: 0
    // Distance from the screen's bottom edge to the bar's own top edge —
    // live, so the popup rides along with the bar's auto-hide animation.
    property real barBottomOffset: 32 * effectiveScale

    // Max pixels the popup may overhang either side of the bar's own
    // rendered edges (not the screen edges) — keeps it visually anchored
    // to the bar for a tight "floaty" look instead of drifting across the
    // screen when the anchor icon sits near a bar edge.
    readonly property real horizontalOverhang: 5 * effectiveScale

    // Gap between the bar's top edge and the popup's bottom edge, so the
    // popup sits just above the bar instead of flush against it.
    readonly property real verticalGap: 3 * effectiveScale

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

    property real openProgress: 0

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

    // Click-away dismissal: closes the popup the instant you click anywhere
    // outside it — including clicking straight into another widget/popup,
    // since the outside click still reaches whatever's under it.
    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.visible
        onDismissed: popup.close()
    }

    // Staggers each item through its own full dismiss() (slide + collapse +
    // blur + Notifications.close), same path as a manual swipe-dismiss uses.
    function clearAllWithAnimation() {
        let count = 0
        for (let i = 0; i < body.notifRepeater.count; i++) {
            const item = body.notifRepeater.itemAt(i)
            if (!item || item.isEmpty || item.dismissing) continue
                const delay = count * 40
                count++
                staggerTimer.createObject(popup, { targetItem: item, delayMs: delay })
        }
    }

    Component {
        id: staggerTimer
        Timer {
            property var targetItem
            property int delayMs: 0
            interval: delayMs
            running: true
            onTriggered: {
                targetItem.dismiss()
                destroy()
            }
        }
    }

    GlassPanel {
        id: glassPanel
        radius: PopupSettings.radiusOf("notifications")
        tracking: popup.tracking
        width: parent.width
        height: parent.height
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        // ---- Popup entrance/exit: slide up + fade + vertical motion blur ----
        y: (1 - popup.openProgress) * (height + 28 * popup.effectiveScale)
        opacity: popup.openProgress
        property real blurAmount: Math.sin(Math.PI * popup.openProgress) * Animations.slideBlurVerticalLength

        // Was "> 0": blurAmount is a sine curve that's essentially never an
        // exact zero except at the endpoints, so the layer (a full offscreen
        // FBO + shader pass every frame) stayed allocated almost the entire
        // time the popup was open. Same visual result, much less GPU work.
        layer.enabled: glassPanel.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurVerticalAngle
            length: glassPanel.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        NotificationsContent {
            id: body
            anchors.fill: parent
            host: popup
        }

    }
}
