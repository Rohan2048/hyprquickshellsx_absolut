import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "../Theme"
import "../Widgets"
import "../Services"

// Everything inside the notifications popup's panel. Used by NotificationsPopup.qml and, unchanged, by the live preview in
// Settings > Popups > Popup styles, so what you arrange there is exactly what the popup shows.
// `host` is the popup window (a stand-in in the preview). Widgets/PopupArrange makes the pieces movable.
Item {
    id: root

    property var host: null
    readonly property real baseWidth: 320
    property alias notifRepeater: notifRepeater

    implicitWidth: 320
    implicitHeight: 460

    ColumnLayout {
        id: arrangeCol
        anchors.fill: parent
        anchors.margins: 8 * host.effectiveScale
        spacing: 10 * host.effectiveScale

        RowLayout {
            Layout.fillWidth: true
            spacing: 6 * host.effectiveScale

            GlassButton {
                icon: "file://" + Quickshell.env("HOME") + "/.config/icons/DND.svg"
                iconSize: 16 * host.effectiveScale
                implicitWidth: 30 * host.effectiveScale
                implicitHeight: 26 * host.effectiveScale
                active: Notifications.dndEnabled
                onClicked: Notifications.toggleDnd()
            }

            Text {
                text: "Notifications"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(14) * host.effectiveScale
                font.bold: true
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }

            GlassButton {
                text: "\u2715 Clear All"
                onClicked: host.clearAllWithAnimation()
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
                y: dndBanner.active ? 0 : -8 * host.effectiveScale
                Behavior on y {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }
            }

            Text {
                id: dndText
                text: "Do Not Disturb is enabled."
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fs(10) * host.effectiveScale
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
                spacing: 10 * host.effectiveScale

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

                            readonly property real entranceOffset: 36 * host.effectiveScale

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
                            readonly property real maxBlurLen: 14 * host.effectiveScale
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
                                radius: 8 * host.effectiveScale
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
                                        Layout.preferredHeight: 40 * host.effectiveScale
                                        Layout.leftMargin: 6 * host.effectiveScale
                                        Layout.rightMargin: 6 * host.effectiveScale
                                        spacing: 6 * host.effectiveScale

                                        Text {
                                            id: expandArrow
                                            visible: !notifItem.isEmpty
                                            text: "\u25b8"
                                            color: Theme.foreground
                                            font.pixelSize: Theme.fs(11) * host.effectiveScale
                                            Layout.preferredWidth: 30 * host.effectiveScale
                                            Layout.preferredHeight: 16 * host.effectiveScale
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
                                            font.pixelSize: Theme.fs(14) * host.effectiveScale
                                            font.bold: true
                                            wrapMode: Text.Wrap
                                            horizontalAlignment: Text.AlignHCenter
                                            Layout.fillWidth: true
                                        }

                                        GlassButton {
                                            visible: !notifItem.isEmpty
                                            text: "\ud83d\udccb"
                                            implicitWidth: 30 * host.effectiveScale
                                            implicitHeight: 26 * host.effectiveScale
                                            onClicked: Notifications.copy(notifItem.hash)
                                        }
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        clip: true
                                        implicitHeight: (notifItem.expanded && notifItem.body !== "")
                                        ? bodyText.implicitHeight + 12 * host.effectiveScale : 0
                                        Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                                        Text {
                                            id: bodyText
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 6 * host.effectiveScale
                                            text: notifItem.body
                                            textFormat: Text.PlainText
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fs(12) * host.effectiveScale
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

    PopupArrange { containers: [arrangeCol] }
}
