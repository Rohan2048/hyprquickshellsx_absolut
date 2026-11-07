import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import "../Theme"
import "../Services"

Item {
    id: root
    width: parent ? parent.width : 300
    // FIX: total height is now fixed regardless of how many laps exist —
    // time + buttons get a constant block, laps get their own constant
    // block below. Nothing above the lap area can ever shift.
    implicitHeight: 100

    property real shakeX: 0
    property real blurAmount: Math.abs(shakeX) * (Animations.shakyBlurMaxLength / Animations.shakyJitterMax)

    function playShake() {
        shakeAnim.stop()
        shakeAnim.restart()
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax; duration: Animations.shakyStepDuration; easing.type: Easing.OutBack }
        NumberAnimation { target: root; property: "shakeX"; to: -Animations.shakyJitterMax * 0.7; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax * 0.4; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -Animations.shakyJitterMax * 0.2; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax * 0.1; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: Animations.shakyStepDuration; easing.type: Easing.OutQuad }
    }

    // State and logic live in Services/StopwatchService.qml so the bar can
    // see whether the stopwatch is active. This page is only a view over it.

    Item {
        id: content
        anchors.fill: parent
        x: root.shakeX

        // PERFORMANCE FIX: Only enable the expensive blur layer when shaking.
        // Rendering DirectionalBlur 30 times a second causes massive input lag.
        layer.enabled: root.shakeX !== 0
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: root.blurAmount
            samples: Animations.shakyBlurSamples
            transparentBorder: true
        }

        ColumnLayout {
            anchors.top: parent.top
            width: parent.width
            spacing: 6

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: StopwatchService.timeText
                font.pixelSize: Theme.fontSizeXl
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.foreground
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 20

                // PERFORMANCE FIX: Fixed width wrapper prevents layout thrashing when text changes
                Item {
                    implicitWidth: 60
                    implicitHeight: 30
                    Text {
                        anchors.centerIn: parent
                        text: StopwatchService.running ? "Pause" : "Start"
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                        color: Theme.foreground
                    }
                    MouseArea { anchors.fill: parent; onClicked: StopwatchService.running ? StopwatchService.pause() : StopwatchService.start() }
                }

                Item {
                    implicitWidth: 60
                    implicitHeight: 30
                    Text {
                        anchors.centerIn: parent
                        text: StopwatchService.running ? "Lap" : "Reset"
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                        color: Theme.textMuted
                    }
                    MouseArea { anchors.fill: parent; onClicked: StopwatchService.running ? StopwatchService.lap() : StopwatchService.reset() }
                }
            }

            // FIX: laps now live in their own fixed-size box below the
            // buttons. Its height never changes, so the time/buttons above
            // it never move no matter how many laps get recorded.
            // Sized for a single lap row; extra laps scroll within it.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                Layout.topMargin: 4
                clip: true

                ListView {
                    id: lapListView
                    anchors.fill: parent
                    // Reserve room on the right for the scrollbar so it
                    // doesn't sit on top of (and hide) the time column.
                    anchors.rightMargin: 5
                    model: StopwatchService.lapModel
                    spacing: 4
                    clip: true
                    interactive: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick

                    ScrollBar.vertical: ScrollBar {
                        anchors.leftMargin: 5
                        policy: lapListView.contentHeight > lapListView.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    delegate: RowLayout {
                        width: lapListView.width
                        height: 20

                        Text {
                            text: "Lap " + (StopwatchService.lapModel.count - index)
                            font.pixelSize: Theme.fontSizeSm
                            font.family: Theme.fontFamily
                            color: Theme.textMuted
                            elide: Text.ElideNone
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: StopwatchService.fmt(model.time)
                            font.pixelSize: Theme.fontSizeSm
                            font.family: Theme.fontFamily
                            color: Theme.foreground
                            elide: Text.ElideNone
                        }
                    }
                }
            }
        }
    }
}
