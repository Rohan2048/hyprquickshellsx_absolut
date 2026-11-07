import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "../Theme"
import "../Widgets"
import "../Services"
import "../Clock"
import "../Calendar"

PanelWindow {
    id: popup
    visible: false

    implicitWidth: 300
    implicitHeight: stackCol.height + 28

    property var tracking: null

    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "datetime-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Distance from the screen's right edge to the clock icon's horizontal center.
    property real iconCenterOffset: 0
    // Distance from the screen's bottom edge to the bar's own top edge —
    // live, so the popup rides along with the bar's auto-hide animation.
    property real barBottomOffset: 32

    // Max pixels the popup may overhang either side of the bar's own
    // rendered edges (not the screen edges) — keeps it visually anchored
    // to the bar for a tight "floaty" look instead of drifting across the
    // screen when the anchor icon sits near a bar edge.
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

    margins {
        bottom: barBottomOffset + verticalGap
        right: smoothedRightMargin
    }

    property real openProgress: 0

    readonly property var pageSources: [
        "../Clock/ClockPage.qml",
        "../Clock/StopwatchPage.qml",
        "../Clock/TimerPage.qml"
    ]
    property int currentIndex: 0

    function toggle() {
        if (popup.openProgress > 0) {
            openAnim.stop()
            closeAnim.restart()
        } else {
            closeAnim.stop()
            mapDelay.stop()
            popup.visible = true
            mapDelay.restart()
        }
    }

    Timer {
        id: mapDelay
        interval: 32
        onTriggered: {
            openAnim.restart()
        }
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
        onDismissed: popup.toggle()
    }

    Column {
        id: stackCol
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: 300
        spacing: 4

        y: (1 - popup.openProgress) * (height + 28)
        opacity: popup.openProgress
        property real blurAmount: Math.sin(Math.PI * popup.openProgress) * Animations.slideBlurVerticalLength *1.5

        // Was "> 0" — Math.sin(Math.PI * 1) isn't exactly 0 in floating
        // point (Math.PI is itself only an approximation of π), so
        // blurAmount never truly hit zero once openProgress finished
        // animating to 1. The layer stayed enabled permanently at a
        // vanishingly small but nonzero length, softening the text inside
        // it the whole time the popup sat open. Threshold instead of
        // strict-nonzero, matching VolumePopup's currentBlur > 0.05.
        layer.enabled: stackCol.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurVerticalAngle
            length: stackCol.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        // ---- Panel 1: Clock / Stopwatch / Timer pager ----
        GlassPanel {
            id: pagerPanel
            width: parent.width
            height: pagerBox.implicitHeight + 28

            Item {
                id: pagerBox
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 14
                width: parent.width - 28
                implicitHeight: 100
                clip: true // Required to hide off-screen pages

                property real slideProgress: 0
                property real shakeX: 0

                // NATURAL BLUR ENVELOPE:
                // Starts at 0, peaks at 8px (subtle smear) in the middle, returns to 0.
                property real blurAmount: Math.sin(slideProgress * Math.PI) * 8.0

                // Persistent loaders, one per page. Never destroyed/cleared, so
                // Clock/Stopwatch/Timer keep ticking while off-screen behind the pager.
                property var pageLoaders: [loaderClock, loaderStopwatch, loaderTimer]

                Item {
                    id: contentWrapper
                    anchors.fill: parent
                    x: pagerBox.shakeX

                    // Inner item isolates the blur shader from the parent's clip boundary,
                    // which is the root cause of the "vertical streak" Qt bug.
                    Item {
                        anchors.fill: parent
                        // Same float-residue fix as stackCol above — slideProgress
                        // hits exactly 1 at the end of the slide anim, and
                        // Math.sin(1 * Math.PI) isn't exactly 0 either.
                        layer.enabled: pagerBox.blurAmount > 0.05
                        layer.effect: DirectionalBlur {
                            angle: 0 // 0 degrees = strictly horizontal left-to-right
                            length: pagerBox.blurAmount
                            samples: 12 // Lower samples = sharper, cleaner smear
                            transparentBorder: true
                        }

                        Loader {
                            id: loaderClock
                            width: parent.width; height: parent.height
                            source: "../Clock/ClockPage.qml"
                            asynchronous: false
                            z: popup.currentIndex === 0 ? 2 : 1
                        }
                        Loader {
                            id: loaderStopwatch
                            width: parent.width; height: parent.height
                            source: "../Clock/StopwatchPage.qml"
                            asynchronous: false
                            z: popup.currentIndex === 1 ? 2 : 1
                        }
                        Loader {
                            id: loaderTimer
                            width: parent.width; height: parent.height
                            source: "../Clock/TimerPage.qml"
                            asynchronous: false
                            z: popup.currentIndex === 2 ? 2 : 1
                        }
                    }
                }

                Component.onCompleted: {
                    // Park the two inactive pages off-screen so they don't
                    // visually overlap the active one before any nav happens.
                    for (let i = 0; i < pagerBox.pageLoaders.length; i++) {
                        pagerBox.pageLoaders[i].x = (i === popup.currentIndex) ? 0 : pagerBox.width
                    }
                }

                function goTo(newIndex, direction) {
                    let incoming = pagerBox.pageLoaders[newIndex]
                    let outgoing = pagerBox.pageLoaders[popup.currentIndex]

                    // Force stop guarantees immediate responsiveness, even on rapid clicks
                    slideAnim.stop()
                    pagerShakeAnim.stop()

                    // Any loader that isn't part of THIS transition may have been abandoned
                    // mid-slide by a previous rapid click. Park it fully off-screen instead
                    // of leaving it wherever .stop() froze it — otherwise it lingers inside
                    // the clipped, visible region indefinitely.
                    for (let i = 0; i < pagerBox.pageLoaders.length; i++) {
                        let loader = pagerBox.pageLoaders[i]
                        if (loader !== incoming && loader !== outgoing) {
                            loader.x = direction * pagerBox.width
                        }
                    }

                    incoming.x = direction * pagerBox.width
                    outgoing.x = 0

                    pagerBox.shakeX = 0
                    pagerBox.slideProgress = 0

                    slideAnim.targetIn = incoming
                    slideAnim.targetOut = outgoing
                    slideAnim.dir = direction

                    slideAnim.start()
                    pagerShakeAnim.start()

                    popup.currentIndex = newIndex
                }

                // 1. The Slide Animation with natural blur envelope
                ParallelAnimation {
                    id: slideAnim

                    property Item targetIn
                    property Item targetOut
                    property real dir
                    NumberAnimation {
                        target: slideAnim.targetIn
                        property: "x"
                        to: 0
                        duration: Animations.pageSlideDuration
                        easing.type: Animations.pageSlideEasingOut
                    }
                    NumberAnimation {
                        target: slideAnim.targetOut
                        property: "x"
                        to: -slideAnim.dir * pagerBox.width
                        duration: Animations.pageSlideDuration
                        easing.type: Animations.pageSlideEasingIn
                    }
                    NumberAnimation {
                        target: pagerBox
                        property: "slideProgress"
                        from: 0
                        to: 1
                        duration: Animations.pageSlideDuration
                        easing.type: Easing.Linear
                    }

                    onStopped: {
                        pagerBox.shakeX = 0
                        pagerBox.slideProgress = 0
                    }
                }

                // 2. The Punchy Shake Animation (6 steps matching Animations.qml)
                SequentialAnimation {
                    id: pagerShakeAnim
                    NumberAnimation { target: pagerBox; property: "shakeX"; to: Animations.shakyJitterMax; duration: Animations.shakyStepDuration; easing.type: Easing.OutBack }
                    NumberAnimation { target: pagerBox; property: "shakeX"; to: -Animations.shakyJitterMax * 0.7; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: pagerBox; property: "shakeX"; to: Animations.shakyJitterMax * 0.4; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: pagerBox; property: "shakeX"; to: -Animations.shakyJitterMax * 0.2; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: pagerBox; property: "shakeX"; to: Animations.shakyJitterMax * 0.1; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: pagerBox; property: "shakeX"; to: 0; duration: Animations.shakyStepDuration; easing.type: Easing.OutQuad }
                }

                // ---- Cyclic Nav Buttons (Preserved exactly as original) ----
                NavArrow {
                    direction: "left"
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        let newIndex = (popup.currentIndex + popup.pageSources.length - 1) % popup.pageSources.length
                        pagerBox.goTo(newIndex, -1)
                    }
                }

                NavArrow {
                    direction: "right"
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        let newIndex = (popup.currentIndex + 1) % popup.pageSources.length
                        pagerBox.goTo(newIndex, 1)
                    }
                }
            }
        }

        // ---- Panel 2: Calendar, always visible, not paged ----
        GlassPanel {
            id: calendarPanel
            width: parent.width
            height: calendarPageContent.implicitHeight + 28

            CalendarPage {
                id: calendarPageContent
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 14
                width: parent.width - 28
            }
        }
    }
}
