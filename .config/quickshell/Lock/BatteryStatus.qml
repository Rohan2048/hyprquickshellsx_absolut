import QtQuick
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import "../Theme"
import "../Widgets"
import "../Services"
import Quickshell

// Reads the same live Battery singleton the bar's battery popup uses —
// no separate script/poller needed here.
Item {
    id: root
    implicitWidth: pill.implicitWidth
    implicitHeight: pill.implicitHeight

    readonly property bool charging: Battery.status === "charging" || Battery.status === "full"
    readonly property string iconDir: "file://" + Quickshell.env("HOME") + "/.config/icons/"

    // Capacity buckets only now — charging is shown separately via the
    // bolt icon beside it, not via separate -chg icon variants.
    // same slots as the bar's battery (Settings > Lock screen > Icons)
    function slotFor(capacity, status) {
        if (status === "full") return "battery-full"
            if (capacity >= 85) return "battery-above85"
                if (capacity >= 70) return "battery-high"
                    if (capacity >= 50) return "battery-med"
                        if (capacity >= 40) return "battery-half"
                            if (capacity >= 20) return "battery-below-half"
                                if (capacity >= 10) return "battery-low"
                                    return "battery-very-low"
    }

    function iconFor(capacity, status) {
        if (status === "full") return "full-battery.svg"

            if (capacity >= 85) return "above85.svg"
                if (capacity >= 70) return "high-battery.svg"
                    if (capacity >= 50) return "med-battery.svg"
                        if (capacity >= 40) return "half-battery.svg"
                            if (capacity >= 20) return "below-half-battery.svg"
                                if (capacity >= 10) return "low-battery.svg"
                                    return "very-low-battery.svg"
    }

    Rectangle {
        id: pill
        radius: Theme.radiusSm
        color: "transparent"
        implicitWidth: row.implicitWidth + 20
        implicitHeight: row.implicitHeight + 12

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6

            // ---- Charging bolt — own slot to the left of the battery
            // icon, same slide+blur+shake treatment as Bar.qml's bolt.
            // boltSlot is what Row positions; boltInner is free to wobble
            // without fighting Row's own layout of this slot. ----
            Item {
                id: boltSlot
                width: root.charging || boltInner.opacity > 0 ? 10 : 0
                height: 10
                anchors.verticalCenter: parent.verticalCenter
                visible: boltInner.opacity > 0
                Behavior on width { NumberAnimation { duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut } }

                Item {
                    id: boltInner
                    width: 10; height: 10
                    opacity: 0

                    readonly property real blurMagnitude: Animations.slideBlurHorizontalLength
                    property real blurLength: 0
                    property bool boltBlurActive: false

                    layer.enabled: boltBlurActive
                    layer.effect: DirectionalBlur {
                        angle: Animations.slideBlurHorizontalAngle
                        length: boltInner.blurLength
                        samples: Animations.slideBlurSamples
                    }

                    ThemedIcon {
                        anchors.fill: parent
                        iconId: "battery-charging"
                        fallback: root.iconDir + "bolt.svg"
                        size: 10
                    }

                    // icon/pct shake immediately on Component.onCompleted with
                    // no fade-in. boltEnterAnim's slide+blur was delaying the
                    // bolt's shake until after that finished, so it landed
                    // late instead of together with the other two. Match
                    // their pattern instead: appear instantly, shake now.
                    Component.onCompleted: if (root.charging) { opacity = 1; boltShakeAnim.restart() }

                    Connections {
                        target: root
                        function onChargingChanged() {
                            if (root.charging) {
                                boltExitAnim.stop()
                                boltShakeAnim.stop()
                                boltInner.x = 0
                                boltEnterAnim.restart()
                            } else {
                                boltEnterAnim.stop()
                                boltShakeAnim.stop()
                                boltInner.x = 0
                                boltExitAnim.restart()
                            }
                        }
                    }

                    SequentialAnimation {
                        id: boltEnterAnim
                        PropertyAction { target: boltInner; property: "boltBlurActive"; value: true }
                        PropertyAction { target: boltInner; property: "blurLength"; value: boltInner.blurMagnitude }
                        ParallelAnimation {
                            NumberAnimation {
                                target: boltInner; property: "opacity"; to: 1
                                duration: Animations.slideBlurDuration
                                easing.type: Animations.slideBlurEasingOut
                            }
                            NumberAnimation {
                                target: boltInner; property: "blurLength"; to: 0
                                duration: Animations.slideBlurDuration
                                easing.type: Animations.slideBlurEasingOut
                            }
                        }
                        PropertyAction { target: boltInner; property: "boltBlurActive"; value: false }
                        ScriptAction { script: boltShakeAnim.restart() }
                    }

                    SequentialAnimation {
                        id: boltExitAnim
                        ScriptAction { script: boltShakeAnim.restart() }
                        PauseAnimation { duration: Animations.scaleDuration(275) }
                        PropertyAction { target: boltInner; property: "boltBlurActive"; value: true }
                        ParallelAnimation {
                            NumberAnimation {
                                target: boltInner; property: "opacity"; to: 0
                                duration: Animations.slideBlurDuration
                                easing.type: Animations.slideBlurEasingIn
                            }
                            NumberAnimation {
                                target: boltInner; property: "blurLength"; to: boltInner.blurMagnitude
                                duration: Animations.slideBlurDuration
                                easing.type: Animations.slideBlurEasingIn
                            }
                        }
                        PropertyAction { target: boltInner; property: "boltBlurActive"; value: false }
                        PropertyAction { target: boltInner; property: "blurLength"; value: 0 }
                    }

                    // Little charging-plug "shake" once the slide-in settles.
                    SequentialAnimation {
                        id: boltShakeAnim
                        NumberAnimation { target: boltInner; property: "x"; to: -2.5; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                        NumberAnimation { target: boltInner; property: "x"; to: 2.5; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                        NumberAnimation { target: boltInner; property: "x"; to: -1.2; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                        NumberAnimation { target: boltInner; property: "x"; to: 1.2; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                        NumberAnimation { target: boltInner; property: "x"; to: 0; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                    }
                }
            }

            Item {
                id: iconWrap
                width: 20
                height: 20
                anchors.verticalCenter: parent.verticalCenter

                property real shakeX: 0
                transform: Translate { x: iconWrap.shakeX }

                layer.enabled: iconWrap.shakeX !== 0
                layer.effect: DirectionalBlur {
                    angle: 0
                    length: Math.min(24, Math.abs(iconWrap.shakeX) * 5)
                    samples: 20
                }

                ThemedIcon {
                    anchors.fill: parent
                    iconId: root.slotFor(Battery.capacity, Battery.status)
                    fallback: root.iconDir + root.iconFor(Battery.capacity, Battery.status)
                    size: 20
                }

                SequentialAnimation {
                    id: iconShake
                    PropertyAction { target: iconWrap; property: "shakeX"; value: 6 }
                    PauseAnimation { duration: Animations.scaleDuration(30) }
                    PropertyAction { target: iconWrap; property: "shakeX"; value: -10 }
                    PauseAnimation { duration: Animations.scaleDuration(30) }
                    PropertyAction { target: iconWrap; property: "shakeX"; value: 6 }
                    PauseAnimation { duration: Animations.scaleDuration(25) }
                    PropertyAction { target: iconWrap; property: "shakeX"; value: -4 }
                    PauseAnimation { duration: Animations.scaleDuration(25) }
                    PropertyAction { target: iconWrap; property: "shakeX"; value: 0 }
                }

                Connections {
                    target: Battery
                    function onCapacityChanged() { iconShake.start() }
                }

                Component.onCompleted: iconShake.start()
            }

            Item {
                id: pctWrap
                width: pctText.implicitWidth
                height: pctText.implicitHeight
                anchors.verticalCenter: parent.verticalCenter

                property real shakeX: 0
                transform: Translate { x: pctWrap.shakeX }

                layer.enabled: pctWrap.shakeX !== 0
                layer.effect: DirectionalBlur {
                    angle: 0
                    length: Math.min(24, Math.abs(pctWrap.shakeX) * 5)
                    samples: 20
                }

                Text {
                    id: pctText
                    text: Battery.capacity + "%"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fs(14)
                }

                SequentialAnimation {
                    id: pctShake
                    PropertyAction { target: pctWrap; property: "shakeX"; value: 6 }
                    PauseAnimation { duration: Animations.scaleDuration(30) }
                    PropertyAction { target: pctWrap; property: "shakeX"; value: -10 }
                    PauseAnimation { duration: Animations.scaleDuration(30) }
                    PropertyAction { target: pctWrap; property: "shakeX"; value: 6 }
                    PauseAnimation { duration: Animations.scaleDuration(25) }
                    PropertyAction { target: pctWrap; property: "shakeX"; value: -4 }
                    PauseAnimation { duration: Animations.scaleDuration(25) }
                    PropertyAction { target: pctWrap; property: "shakeX"; value: 0 }
                }

                Connections {
                    target: Battery
                    function onCapacityChanged() { pctShake.start() }
                }

                Component.onCompleted: pctShake.start()
            }
        }
    }
}
