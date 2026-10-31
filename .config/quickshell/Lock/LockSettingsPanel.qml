import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt5Compat.GraphicalEffects
import "../Widgets"
import "../Theme"
import "../Services"
GlassPanel {
    id: root
    property string view: "root" // "root" | "wifi" | "bluetooth"
    property bool shown: false
    // The item holding everything behind the panel (set by LockScreen). The panel draws a blurred
    // copy of the part it covers under its translucent fill, so Transparent blur works on top of a
    // wallpaper or shapes too, not just the blurred screen.
    property Item backdrop: null
    // Only when the background is not the plain blurred screen (a wallpaper or shapes sit behind);
    // with the default lock screen nothing extra is drawn and the panel looks exactly as it always did.
    property bool extraBlur: false
    // offset (px) of everything inside the panel (Settings > Lock screen > Settings button)
    property real contentX: 0
    property real contentY: 0

    // What sits behind the panel in a custom lock screen (set by LockScreen); the panel blurs its own
    // copy of the part it covers. A copy, not a snapshot: no screen capture is involved, so it can't go blank.
    property string wallpaperPath: ""
    property real dim: 0
    property color dimColor: "black"
    property var shapes: []
    property real surfaceW: 0
    property real surfaceH: 0

    Item {
        id: blurUnder
        z: -1
        anchors.fill: parent
        visible: root.extraBlur
        Rectangle { id: blurMask; anchors.fill: parent; radius: root.radius; visible: false; layer.enabled: true }
        Item {
            anchors.fill: parent
            clip: true
            layer.enabled: root.extraBlur
            layer.effect: MultiEffect {
                autoPaddingEnabled: false
                blurEnabled: true
                blur: 1.0
                blurMax: 48
                blurMultiplier: 1.0
                maskEnabled: true
                maskSource: blurMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Item {
                x: -root.x
                y: -root.y
                width: root.surfaceW
                height: root.surfaceH
                Image {
                    anchors.fill: parent
                    visible: root.wallpaperPath !== "" && status === Image.Ready
                    source: root.wallpaperPath !== "" ? "file://" + root.wallpaperPath : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 1920
                }
                Rectangle { anchors.fill: parent; color: root.dimColor; opacity: root.dim; visible: root.wallpaperPath !== "" }
                LockShapes { anchors.fill: parent; shapes: root.shapes }
            }
        }
    }

    implicitWidth: 350
    implicitHeight: (root.view === "root" ? 360 : 300)

    // 1. Drive fluid macro-movement via Behaviors (no more manual opacity = 0 fighting)
    visible: opacity > 0.01
    opacity: shown ? 1.0 : 0.0
    scale: shown ? 1.0 : 0.9

    Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    Behavior on scale {
        NumberAnimation { duration: 160; easing.type: Easing.OutBack }
    }

    property real entranceX: 0
    property real shakeX: 0
    transform: Translate { x: root.entranceX + root.shakeX }

    // Was "true" — permanent shader pass for as long as `shown` stays
    // true, i.e. the entire time the lock screen is up. blurAmount only
    // matters during the brief entrance/exit shake+slide. entranceX
    // animates to a clean "to: 0" target and shakeX moves in discrete
    // PropertyAction steps, so a strict inequality is safe here (no
    // eased-float-residue risk).
    layer.enabled: root.shakeX !== 0 || root.entranceX !== 0
    layer.effect: DirectionalBlur {
        angle: 0
        length: Math.min(14, Math.abs(root.shakeX) * 4 + Math.abs(root.entranceX) * 0.5)
        samples: 20
    }

    // 2. Trigger the entrance blend exactly when the panel state changes
    onShownChanged: {
        entranceAnimation.restart()
    }

    // 3. Slide-in blended with a light settle shake (shared for entrance/exit)
    ParallelAnimation {
        id: entranceAnimation
        NumberAnimation {
            target: root; property: "entranceX"
            from: 16; to: 0
            duration: Animations.scaleDuration(170)
            easing.type: Easing.OutCubic
        }
        SequentialAnimation {
            PropertyAction { target: root; property: "shakeX"; value: 3 }
            PauseAnimation { duration: Animations.scaleDuration(30) }
            PropertyAction { target: root; property: "shakeX"; value: -8 }
            PauseAnimation { duration: Animations.scaleDuration(30) }
            PropertyAction { target: root; property: "shakeX"; value: 5 }
            PauseAnimation { duration: Animations.scaleDuration(25) }
            PropertyAction { target: root; property: "shakeX"; value: -6 }
            PauseAnimation { duration: Animations.scaleDuration(25) }
            PropertyAction { target: root; property: "shakeX"; value: 3 }
            PauseAnimation { duration: Animations.scaleDuration(20) }
            PropertyAction { target: root; property: "shakeX"; value: -3 }
            PauseAnimation { duration: Animations.scaleDuration(18) }
            PropertyAction { target: root; property: "shakeX"; value: 0 }
        }
    }

    Item {
        x: 14 + root.contentX
        y: 14 + root.contentY
        width: parent.width - 28
        height: parent.height - 28

        ColumnLayout {
            id: mainContent
            anchors.fill: parent
            spacing: Theme.gapMd
            visible: opacity > 0.01
            opacity: root.view === "root" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

            // Same snap-jitter as LockWifiDetail/LockBluetoothDetail's entrance:
            // fires the instant this becomes visible again (i.e. when returning
            // from wifi/bluetooth), so coming back to the settings panel is a
            // single connected transition instead of a separate shake-then-switch.
            property real entranceX: 0
            property real shakeX: 0
            transform: Translate { x: mainContent.entranceX + mainContent.shakeX }

            // Same fix as root above.
            layer.enabled: mainContent.shakeX !== 0 || mainContent.entranceX !== 0
            layer.effect: DirectionalBlur {
                angle: 0
                length: Math.min(14, Math.abs(mainContent.shakeX) * 4 + Math.abs(mainContent.entranceX) * 0.5)
                samples: 20
            }

            onVisibleChanged: {
                if (visible) {
                    mainEntrance.restart()
                }
            }

            ParallelAnimation {
                id: mainEntrance
                NumberAnimation {
                    target: mainContent; property: "entranceX"
                    from: 16; to: 0
                    duration: Animations.scaleDuration(170)
                    easing.type: Easing.OutCubic
                }
                SequentialAnimation {
                    PropertyAction { target: mainContent; property: "shakeX"; value: 3 }
                    PauseAnimation { duration: Animations.scaleDuration(30) }
                    PropertyAction { target: mainContent; property: "shakeX"; value: -8 }
                    PauseAnimation { duration: Animations.scaleDuration(30) }
                    PropertyAction { target: mainContent; property: "shakeX"; value: 5 }
                    PauseAnimation { duration: Animations.scaleDuration(25) }
                    PropertyAction { target: mainContent; property: "shakeX"; value: -6 }
                    PauseAnimation { duration: Animations.scaleDuration(25) }
                    PropertyAction { target: mainContent; property: "shakeX"; value: 3 }
                    PauseAnimation { duration: Animations.scaleDuration(20) }
                    PropertyAction { target: mainContent; property: "shakeX"; value: -3 }
                    PauseAnimation { duration: Animations.scaleDuration(18) }
                    PropertyAction { target: mainContent; property: "shakeX"; value: 0 }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 7
                spacing: Theme.gapMd

                LockWifiRow {
                    Layout.preferredWidth: 70
                    onDevicesRequested: root.view = "wifi"
                }
                LockBluetoothRow {
                    Layout.preferredWidth: 70
                    onDevicesRequested: root.view = "bluetooth"
                }
                LockAirplaneRow {
                    Layout.preferredWidth: 70
                }
                LockLightDarkRow {
                    Layout.preferredWidth: 70
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.gapMd + 8

                LockVolumeRow { Layout.fillWidth: true }
                LockBrightnessRow { Layout.fillWidth: true }
            }

            Item { Layout.fillHeight: true } // soak up the fixed extra height
        }

        LockWifiDetail {
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: root.view === "wifi" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            onBack: root.view = "root"
        }

        LockBluetoothDetail {
            anchors.fill: parent
            visible: opacity > 0.01
            opacity: root.view === "bluetooth" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            onBack: root.view = "root"
        }
    }
}
