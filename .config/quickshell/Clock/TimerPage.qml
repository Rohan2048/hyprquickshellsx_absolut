import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import "../Theme"
import "../Services"
import "../Widgets"

Item {
    id: root
    width: parent ? parent.width : 300
    implicitHeight: 75

    property real shakeX: 0
    property real blurAmount: Math.abs(shakeX) * (Animations.shakyBlurMaxLength / Animations.shakyJitterMax)

    function playShake() {
        shakeAnim.stop()
        shakeAnim.restart()
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax; duration: Animations.shakyStepDuration; easing.type: Easing.OutBack }
        NumberAnimation { target: root; property: "shakeX"; to: -Animations.shakyJitterMax * 0.5; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax * 0.4; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -Animations.shakyJitterMax * 0.2; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax * 0.1; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
    }

    // Snap-style jitter for the "Time's Up!" entrance — separate property
    // from shakeX so it doesn't fight with playShake()'s tweened shake.
    property real timesUpShakeX: 0

    SequentialAnimation {
        id: timesUpShakeAnim
        NumberAnimation { target: root; property: "timesUpShakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: 3; duration: Animations.scaleDuration(28); easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: -3; duration: Animations.scaleDuration(25); easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
    }

    // State and logic live in Services/TimerService.qml so the bar can see
    // whether a timer is active. This page is only a view over it.
    Connections {
        target: TimerService
        function onTimesUpChanged() {
            if (TimerService.timesUp) timesUpShakeAnim.start()
        }
    }

    Item {
        id: content
        anchors.fill: parent
        x: root.shakeX

        layer.enabled: root.shakeX !== 0
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: root.blurAmount
            samples: Animations.shakyBlurSamples
            transparentBorder: true
        }

        // Normal timer view
        ColumnLayout {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 6
            visible: !TimerService.timesUp

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: TimerService.timeText
                font.pixelSize: Theme.fontSizeXl
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.foreground
            }

            // FIX: this row now actually collapses (height animates to 0)
            // once the timer starts, instead of just fading out while still
            // holding its layout space. Because the ColumnLayout is
            // vertically centered in the 75px widget, collapsing this row
            // shrinks the column and the whole thing re-centers — which is
            // what pulls the countdown text down toward center.
            property bool adjustVisible: !TimerService.running && TimerService.remainingMs === TimerService.durationMs

            RowLayout {
                id: adjustRow
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredHeight: parent.adjustVisible ? implicitHeight : 0
                spacing: 16
                clip: true
                opacity: parent.adjustVisible ? 1 : 0
                enabled: parent.adjustVisible

                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }

                Item {
                    implicitWidth: 40
                    implicitHeight: 30
                    Text {
                        anchors.centerIn: parent
                        text: "-1h"
                        font.pixelSize: Theme.fontSizeSm
                        font.family: Theme.fontFamily
                        color: Theme.textMuted
                    }
                    MouseArea { anchors.fill: parent; onClicked: TimerService.adjust(-3600000) }
                }
                Item {
                    implicitWidth: 40
                    implicitHeight: 30
                    Text {
                        anchors.centerIn: parent
                        text: "-1m"
                        font.pixelSize: Theme.fontSizeSm
                        font.family: Theme.fontFamily
                        color: Theme.textMuted
                    }
                    MouseArea { anchors.fill: parent; onClicked: TimerService.adjust(-60000) }
                }
                Item {
                    implicitWidth: 40
                    implicitHeight: 30
                    Text {
                        anchors.centerIn: parent
                        text: "+1m"
                        font.pixelSize: Theme.fontSizeSm
                        font.family: Theme.fontFamily
                        color: Theme.textMuted
                    }
                    MouseArea { anchors.fill: parent; onClicked: TimerService.adjust(60000) }
                }
                Item {
                    implicitWidth: 40
                    implicitHeight: 30
                    Text {
                        anchors.centerIn: parent
                        text: "+1h"
                        font.pixelSize: Theme.fontSizeSm
                        font.family: Theme.fontFamily
                        color: Theme.textMuted
                    }
                    MouseArea { anchors.fill: parent; onClicked: TimerService.adjust(3600000) }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 20

                Item {
                    implicitWidth: 60
                    implicitHeight: 30
                    Text {
                        anchors.centerIn: parent
                        text: TimerService.running ? "Pause" : "Start"
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                        color: Theme.foreground
                    }
                    MouseArea { anchors.fill: parent; onClicked: TimerService.running ? TimerService.pause() : TimerService.start() }
                }
                Item {
                    implicitWidth: 60
                    implicitHeight: 30
                    Text {
                        anchors.centerIn: parent
                        text: "Reset"
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                        color: Theme.textMuted
                    }
                    MouseArea { anchors.fill: parent; onClicked: TimerService.reset() }
                }
            }
        }

        // FIX: inline "Time's Up" state — occupies the same 75px area,
        // no overlay, no z-ordering, no anchors.fill on an ancestor.
        ColumnLayout {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 8
            visible: TimerService.timesUp
            transform: Translate { x: root.timesUpShakeX }

            layer.enabled: root.timesUpShakeX !== 0
            layer.effect: DirectionalBlur {
                angle: 0
                length: Math.min(28, Math.abs(root.timesUpShakeX) * 5)
                samples: 21
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Time's Up!"
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.foreground
            }

            GlassButton {
                Layout.alignment: Qt.AlignHCenter
                text: "OK"
                onClicked: TimerService.reset()
            }
        }
    }
}
