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
    readonly property real effectiveScale: userScale

    // Base (reference) dimensions — reduced from the old 400x600.
    readonly property real baseWidth: 320
    readonly property real baseHeight: 460

    implicitWidth: baseWidth * effectiveScale
    implicitHeight: baseHeight * effectiveScale

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
        for (let i = 0; i < notifRepeater.count; i++) {
            const item = notifRepeater.itemAt(i)
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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8 * popup.effectiveScale
            spacing: 10 * popup.effectiveScale

            RowLayout {
                Layout.fillWidth: true
                spacing: 6 * popup.effectiveScale

                GlassButton {
                    icon: "file://" + Quickshell.env("HOME") + "/.config/icons/DND.svg"
                    iconSize: 16 * popup.effectiveScale
                    implicitWidth: 30 * popup.effectiveScale
                    implicitHeight: 26 * popup.effectiveScale
                    active: Notifications.dndEnabled
                    onClicked: Notifications.toggleDnd()
                }

                Text {
                    text: "Notifications"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 14 * popup.effectiveScale
                    font.bold: true
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }

                GlassButton {
                    text: "\u2715 Clear All"
                    onClicked: clearAllWithAnimation()
                }
            }

            // ---- DND banner: slides down into place on entry, slides up
            // while fading on exit, same opacity+Translate pattern as
            // BluetoothPopup's pairingPrompt — just with an explicit
            // Behavior on y so the slide itself animates instead of
            // snapping alongside the opacity fade. ----
            Item {
                id: dndBanner
                Layout.fillWidth: true
                clip: true

                readonly property bool active: Notifications.dndEnabled

                // implicitHeight animates in lockstep with opacity/y below,
                // so ColumnLayout reflows the ScrollView underneath smoothly
                // instead of snapping it into place the instant `visible`
                // flips false at the end of the fade.
                implicitHeight: active ? dndText.implicitHeight : 0
                Behavior on implicitHeight {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                opacity: active ? 1 : 0
                visible: opacity > 0.01 || implicitHeight > 0.5

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

                transform: Translate {
                    y: dndBanner.active ? 0 : -8 * popup.effectiveScale
                    Behavior on y {
                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                    }
                }

                Text {
                    id: dndText
                    text: "Do Not Disturb is enabled."
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 10 * popup.effectiveScale
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ColumnLayout {
                    width: parent.width
                    spacing: 10 * popup.effectiveScale

                    Repeater {
                        id: notifRepeater
                        model: Notifications.list

                        delegate: Item {
                            id: notifItem
                            required property string title
                            required property string body
                            required property string hash
                            readonly property bool isEmpty: hash === ""
                            readonly property bool expanded: Notifications.expandedHash === hash
                            property bool dismissing: false

                            Layout.fillWidth: true
                            implicitHeight: innerColumn.implicitHeight
                            Layout.preferredHeight: implicitHeight

                            // ---- Entrance: fade for the empty-state placeholder,
                            // slide + fade (+ automatic motion blur via innerColumn's
                            // velocity tracking) for real notifications ----
                            opacity: 1
                            property real emptyBlur: 0

                            // Was "notifItem.isEmpty" alone: that kept this item
                            // layered (full offscreen FBO every frame) for the
                            // entire time the list sits empty, even though
                            // emptyBlur is 0 outside the brief entrance animation.
                            // Now only layered while there's actual blur to render.
                            layer.enabled: notifItem.isEmpty && notifItem.emptyBlur > 0.05
                            layer.effect: DirectionalBlur {
                                angle: Animations.slideBlurVerticalAngle
                                length: notifItem.emptyBlur
                                samples: Animations.slideBlurSamples
                                transparentBorder: true
                            }
                            Component.onCompleted: {
                                if (notifItem.isEmpty) {
                                    notifItem.opacity = 0
                                    emptyEntranceAnim.start()
                                } else {
                                    innerColumn.x = innerColumn.entranceOffset
                                    innerColumn.opacity = 0
                                    itemEntranceAnim.start()
                                }
                            }

                            ParallelAnimation {
                                id: emptyEntranceAnim
                                NumberAnimation {
                                    target: notifItem; property: "opacity"; to: 1
                                    duration: Animations.slideBlurDuration
                                    easing.type: Animations.slideBlurEasingOut
                                }
                                SequentialAnimation {
                                    NumberAnimation {
                                        target: notifItem; property: "emptyBlur"; to: Animations.slideBlurVerticalLength
                                        duration: 0
                                    }
                                    NumberAnimation {
                                        target: notifItem; property: "emptyBlur"; to: 0
                                        duration: Animations.slideBlurDuration
                                        easing.type: Animations.slideBlurEasingOut
                                    }
                                }
                            }

                            // NOTE: runs while innerColumn.settled is still false, so the
                            // release-pop Behavior below is disabled and won't fight this
                            // animation over the x property (was the cause of items
                            // visibly jumping/misaligning on entrance).
                            ParallelAnimation {
                                id: itemEntranceAnim
                                NumberAnimation {
                                    target: innerColumn; property: "x"; to: 0
                                    duration: Animations.itemDismissDuration
                                    easing.type: Animations.slideBlurEasingOut
                                }
                                NumberAnimation {
                                    target: innerColumn; property: "opacity"; to: 1
                                    duration: Animations.itemDismissDuration
                                    easing.type: Animations.slideBlurEasingOut
                                }
                                onStopped: innerColumn.settled = true
                            }

                            function dismiss() {
                                if (dismissing) return
                                    dismissing = true
                                    dismissAnim.start()
                            }

                            SequentialAnimation {
                                id: dismissAnim
                                NumberAnimation {
                                    target: innerColumn
                                    property: "x"
                                    to: notifItem.width * Animations.itemDismissDistanceFactor
                                    duration: Animations.itemDismissDuration
                                    easing.type: Animations.itemDismissEasing
                                }
                                NumberAnimation {
                                    target: notifItem
                                    property: "Layout.preferredHeight"
                                    to: 0
                                    duration: Animations.itemDismissCollapseDuration
                                    easing.type: Easing.InOutCubic
                                }
                                ScriptAction {
                                    script: {
                                        notifItem.visible = false
                                        Notifications.close(notifItem.hash)
                                    }
                                }
                            }

                            ColumnLayout {
                                id: innerColumn
                                width: notifItem.width
                                spacing: 0

                                readonly property real entranceOffset: 36 * popup.effectiveScale

                                // Stays false until itemEntranceAnim finishes, so the spring
                                // below can't collide with the entrance NumberAnimation over
                                // the same "x" property (that collision was the alignment bug).
                                property bool settled: false

                                Behavior on x {
                                    enabled: innerColumn.settled && !itemMouse.drag.active && !notifItem.dismissing
                                    SpringAnimation {
                                        spring: Animations.releasePopSpring
                                        damping: Animations.releasePopDamping
                                        mass: Animations.releasePopMass
                                    }
                                }

                                // ---- Motion blur while sliding (drag, release spring,
                                // programmatic dismiss, or entrance) ----
                                // blurLen tracks how fast x is actually moving, not what
                                // caused it, so every kind of horizontal motion above gets
                                // the same trailing blur for free.
                                readonly property real maxBlurLen: 14 * popup.effectiveScale
                                readonly property real blurVelocityFactor: 0.35
                                property real blurLen: 0
                                property real lastX: 0
                                property real lastMoveTime: 0

                                layer.enabled: innerColumn.blurLen > 0.5
                                layer.effect: DirectionalBlur {
                                    angle: Animations.slideBlurHorizontalAngle
                                    length: innerColumn.blurLen
                                    samples: Animations.slideBlurSamples
                                    transparentBorder: true
                                }

                                Timer {
                                    id: blurIdleTimer
                                    interval: 80
                                    onTriggered: innerColumn.blurLen = 0
                                }

                                Behavior on blurLen {
                                    NumberAnimation { duration: 100; easing.type: Easing.OutQuad }
                                }

                                onXChanged: {
                                    const now = Date.now()
                                    const dt = innerColumn.lastMoveTime > 0 ? now - innerColumn.lastMoveTime : 16
                                    if (dt > 0) {
                                        const velocity = Math.abs(innerColumn.x - innerColumn.lastX) / dt
                                        innerColumn.blurLen = Math.min(innerColumn.maxBlurLen, velocity * innerColumn.blurVelocityFactor * 40)
                                    }
                                    innerColumn.lastX = innerColumn.x
                                    innerColumn.lastMoveTime = now
                                    blurIdleTimer.restart()
                                }

                                // Single card: header + expandable body live inside
                                // ONE bordered Rectangle now, so the border itself
                                // grows/shrinks instead of body text floating below it.
                                Rectangle {
                                    Layout.fillWidth: true
                                    implicitHeight: cardColumn.implicitHeight
                                    radius: 8 * popup.effectiveScale
                                    color: notifItem.isEmpty ? "transparent"
                                    : (itemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.04))
                                    border.width: notifItem.isEmpty ? 0 : 1
                                    border.color: itemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08)
                                    clip: true

                                    Behavior on color { ColorAnimation { duration: 200 } }
                                    Behavior on implicitHeight {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                    }

                                    ColumnLayout {
                                        id: cardColumn
                                        width: parent.width
                                        spacing: 0

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 40 * popup.effectiveScale
                                            Layout.leftMargin: 6 * popup.effectiveScale
                                            Layout.rightMargin: 6 * popup.effectiveScale
                                            spacing: 6 * popup.effectiveScale

                                            Text {
                                                id: expandArrow
                                                visible: !notifItem.isEmpty
                                                text: "\u25b8"
                                                color: Theme.foreground
                                                font.pixelSize: 11 * popup.effectiveScale
                                                Layout.preferredWidth: 30 * popup.effectiveScale
                                                Layout.preferredHeight: 16 * popup.effectiveScale
                                                horizontalAlignment: Text.AlignHCenter

                                                rotation: notifItem.expanded ? 90 : 0
                                                Behavior on rotation {
                                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: Notifications.toggleExpand(notifItem.hash)
                                                }
                                            }

                                            Text {
                                                text: notifItem.title
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 14 * popup.effectiveScale
                                                font.bold: true
                                                wrapMode: Text.Wrap
                                                horizontalAlignment: Text.AlignHCenter
                                                Layout.fillWidth: true
                                            }

                                            GlassButton {
                                                visible: !notifItem.isEmpty
                                                text: "\ud83d\udccb"
                                                implicitWidth: 30 * popup.effectiveScale
                                                implicitHeight: 26 * popup.effectiveScale
                                                onClicked: Notifications.copy(notifItem.hash)
                                            }
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            clip: true
                                            implicitHeight: (notifItem.expanded && notifItem.body !== "")
                                            ? bodyText.implicitHeight + 12 * popup.effectiveScale : 0
                                            Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                            Text {
                                                id: bodyText
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: 6 * popup.effectiveScale
                                                text: notifItem.body
                                                textFormat: Text.PlainText
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 12 * popup.effectiveScale
                                                wrapMode: Text.Wrap
                                                horizontalAlignment: Text.AlignHCenter

                                                opacity: notifItem.expanded ? 1 : 0
                                                Behavior on opacity {
                                                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: itemMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        drag.target: notifItem.isEmpty ? null : innerColumn
                                        drag.axis: Drag.XAxis
                                        drag.minimumX: 0
                                        drag.maximumX: notifItem.width * Animations.itemDismissDistanceFactor
                                        z: -1

                                        onReleased: {
                                            if (innerColumn.x > notifItem.width * 0.35) {
                                                notifItem.dismiss()
                                            } else {
                                                innerColumn.x = 0
                                            }
                                        }

                                        // Tap anywhere on the card toggles expand, same
                                        // action as clicking the arrow. Only fires on a
                                        // clean tap — MouseArea suppresses onClicked when
                                        // the press moved past the drag threshold, so this
                                        // never fights the swipe-to-dismiss gesture above.
                                        onClicked: {
                                            if (!notifItem.isEmpty)
                                                Notifications.toggleExpand(notifItem.hash)
                                        }

                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
