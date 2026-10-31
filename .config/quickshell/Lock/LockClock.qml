import QtQuick
import Qt5Compat.GraphicalEffects
import "../Theme"
import "../Services"
import "../Widgets"

Column {
    id: root
    spacing: 4
    property date now: new Date()
    // Settings > Lock screen: hide the date line
    property bool showDate: true
    // Settings > Lock screen > Text colour: a solid colour, or a real gradient (GradientText),
    // never a tint laid over the text. null / Theme.foreground = as always.
    property var textGrad: null
    property color textColor: Theme.foreground

    // Track the current minute to detect exactly when it changes
    property int currentMinute: now.getMinutes()

    property real shakeX: 0
    transform: Translate { x: root.shakeX }

    // Was "true" — permanent shader pass on a large always-visible clock,
    // ticking every second forever, while shakeX is only ever nonzero for
    // a fraction of a second once a minute. shakeX moves in discrete
    // PropertyAction steps (no eased tweening through it), so a strict
    // !== 0 check is safe here — no float-residue risk like an eased
    // Math.sin(...) blur amount would have.
    layer.enabled: root.shakeX !== 0
    layer.effect: DirectionalBlur {
        angle: 0
        length: Math.min(28, Math.abs(root.shakeX) * 5)
        samples: 21
    }

    GradientText {
        anchors.horizontalCenter: parent.horizontalCenter
        textGrad: root.textGrad
        fallbackColor: root.textColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(95)
        font.weight: Font.Medium
        text: Qt.formatTime(root.now, "HH:mm")
    }

    GradientText {
        visible: root.showDate
        anchors.horizontalCenter: parent.horizontalCenter
        textGrad: root.textGrad
        fallbackColor: root.textColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(35)
        font.weight: Font.Light
        text: Qt.formatDate(root.now, "dd MMMM, yyyy")
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            root.now = new Date()
            // Explicitly update to guarantee the change signal fires
            // and bypasses QML Date binding quirks
            root.currentMinute = root.now.getMinutes()
        }
    }

    // Trigger the animation exactly when the minute changes
    onCurrentMinuteChanged: {
        shakeAnimation.start()
    }

    // Subtle ambient jitter -- abrupt snaps, not tweened motion.
    // Triggered manually on minute change to guarantee zero desync.
    SequentialAnimation {
        id: shakeAnimation

        PropertyAction { target: root; property: "shakeX"; value: 6 }
        PauseAnimation { duration: Animations.scaleDuration(35) }
        PropertyAction { target: root; property: "shakeX"; value: -18 }
        PauseAnimation { duration: Animations.scaleDuration(35) }
        PropertyAction { target: root; property: "shakeX"; value: 12 }
        PauseAnimation { duration: Animations.scaleDuration(30) }
        PropertyAction { target: root; property: "shakeX"; value: -14 }
        PauseAnimation { duration: Animations.scaleDuration(30) }
        PropertyAction { target: root; property: "shakeX"; value: 8 }
        PauseAnimation { duration: Animations.scaleDuration(28) }
        PropertyAction { target: root; property: "shakeX"; value: -6 }
        PauseAnimation { duration: Animations.scaleDuration(25) }
        PropertyAction { target: root; property: "shakeX"; value: 0 }
    }

    // Optional: Uncomment the line below if you also want the jitter
    // to play immediately when the component first loads.
    // Component.onCompleted: shakeAnimation.start()
}
