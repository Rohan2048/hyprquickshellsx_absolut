import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../Theme"
import "../Services"

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
        NumberAnimation { target: root; property: "shakeX"; to: -Animations.shakyJitterMax * 0.7; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax * 0.4; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -Animations.shakyJitterMax * 0.2; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax * 0.1; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: Animations.shakyStepDuration; easing.type: Easing.OutQuad }
    }

    property date now: new Date()

    // Bound by DateTimePopup to popup.visible, so the 1 s tick only runs
    // while the popup is on screen (triggeredOnStart refreshes `now` on open).
    property bool ticking: true

    Timer {
        interval: 1000
        // running: true
        running: root.ticking
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    function pad(n) { return n < 10 ? "0" + n : "" + n }

    readonly property string timeString: pad(root.now.getHours()) + ":" + pad(root.now.getMinutes()) + ":" + pad(root.now.getSeconds())
    readonly property string dateString: Qt.formatDate(root.now, "dddd, d MMMM yyyy")

    Item {
        id: content
        anchors.fill: parent
        x: root.shakeX

        // Was "true" — permanent shader pass ticking every second forever,
        // on the page shown by default when the popup opens. blurAmount
        // is 0 whenever shakeX is 0 (i.e. always, except during
        // playShake()). Same fix as StopwatchPage/TimerPage already have.
        layer.enabled: root.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: root.blurAmount
            samples: Animations.shakyBlurSamples
            transparentBorder: true
        }

        ColumnLayout {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 4

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.timeString
                font.pixelSize: Theme.fs(40)
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.foreground
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.dateString
                font.pixelSize: Theme.fontSizeSm
                font.family: Theme.fontFamily
                color: Theme.textMuted
            }
        }
    }
}
