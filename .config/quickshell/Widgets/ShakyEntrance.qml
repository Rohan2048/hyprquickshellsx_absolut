import QtQuick
import Qt5Compat.GraphicalEffects
import "../Theme"

// Stationary "shaky" entrance for lock-screen UI. Same DirectionalBlur
// effect VolumePopup's GlassPanel uses for its slide entrance, but angle
// is randomized per discrete step instead of derived from drag direction -
// that's what gives a hand-held shake instead of a directional slide.
//
// Cost: layer + jitter Timer only live for Animations.shakyEntranceDuration
// (~320ms). On finish, layer.enabled flips false and the timer stops -
// after that this is a plain static draw.
Item {
    id: root
    default property alias data: content.data
        implicitWidth: content.implicitWidth
        implicitHeight: content.implicitHeight

        property real entranceProgress: 1
        property real jitterX: 0
        property real jitterY: 0
        property real shakeAngle: 0
        property bool entranceRunning: false

        readonly property real envelope: Animations.blurEnvelope(entranceProgress)

        Item {
            id: content
            anchors.fill: parent
            transform: Translate { x: root.jitterX; y: root.jitterY }
        }

        opacity: 1 - envelope * 0.2

        layer.enabled: entranceRunning
        layer.effect: DirectionalBlur {
            angle: root.shakeAngle
            length: root.envelope * Animations.shakyBlurMaxLength
            samples: Animations.shakyBlurSamples
            transparentBorder: true
        }

        NumberAnimation {
            id: progressAnim
            target: root
            property: "entranceProgress"
            from: 0; to: 1
            duration: Animations.shakyEntranceDuration
            easing.type: Animations.shakyEntranceEasing
            onStopped: root.entranceRunning = false
        }

        Timer {
            id: jitterTimer
            interval: Animations.shakyStepDuration
            repeat: true
            property int step: 0
            onTriggered: {
                step++
                if (step >= Animations.shakyStepCount) {
                    stop()
                    root.jitterX = 0
                    root.jitterY = 0
                    return
                }
                const decay = 1 - (step / Animations.shakyStepCount)
                root.jitterX = (Math.random() * 2 - 1) * Animations.shakyJitterMax * decay
                root.jitterY = (Math.random() * 2 - 1) * Animations.shakyJitterMax * decay
                root.shakeAngle = Math.random() * 360
            }
        }

        function playEntrance() {
            entranceRunning = true
            entranceProgress = 0
            jitterTimer.step = 0
            jitterX = 0; jitterY = 0
            progressAnim.restart()
            jitterTimer.restart()
        }
}
