import QtQuick
import "../Theme"
import "../Services"

// Generic rubber-band drag slider, lifted from VolumePopup's volume track.
Item {
    id: root

    property real value: 0
    property real min: 0
    property real max: 100
    signal valueCommitted(real v)
    readonly property bool pressed: dragArea.pressed

    implicitWidth: 150
    implicitHeight: dragArea.pressed ? 34 : 22
    Behavior on implicitHeight {
        SpringAnimation {
            spring: Animations.trackSpring
            damping: Animations.trackDamping
            mass: Animations.trackMass
        }
    }

    property real dragValue: root.value
    readonly property real ratio: max > min ? Math.max(0, Math.min(1, (dragValue - min) / (max - min))) : 0
    property bool settling: false

    Binding {
        target: root
        property: "dragValue"
        value: root.value
        when: !dragArea.pressed && !root.settling
    }

    Timer {
        id: settleTimer
        interval: 250
        onTriggered: root.settling = false
    }

    readonly property real maxStretch: 10
    readonly property real stretchConstant: 0.60
    function rubberBand(distance) {
        return Animations.rubberBand(distance, maxStretch, stretchConstant)
    }

    property real overshoot: 0
    Behavior on overshoot {
        SpringAnimation {
            spring: dragArea.pressed && dragArea.pinnedSide !== 0 ? Animations.pinnedStretchSpring : Animations.overshootSpring
            damping: dragArea.pressed && dragArea.pinnedSide !== 0 ? Animations.pinnedStretchDamping : Animations.overshootDamping
            mass: dragArea.pressed && dragArea.pinnedSide !== 0 ? Animations.pinnedStretchMass : Animations.overshootMass
        }
    }

    Rectangle {
        id: track
        anchors.fill: parent
        transform: Translate { x: root.overshoot }
        radius: height / 2
        color: Theme.hoverBg
        clip: true

        Item {
            id: fill
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            width: Math.round(root.ratio * parent.width)
            clip: true

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                width: track.width
                height: track.height
                radius: track.radius
                color: Theme.accentActive
            }

            Behavior on width {
                enabled: !dragArea.pressed
                NumberAnimation {
                    duration: Animations.durationBase
                    easing.type: Animations.easingStandard
                }
            }
        }
    }

    MouseArea {
        id: dragArea
        anchors.fill: parent
        preventStealing: true
        cursorShape: Qt.PointingHandCursor

        property int pinnedSide: 0
        property real lastSentValue: -1

        function updateFromX(x) {
            const clampedX = Math.max(0, Math.min(width, x))
            const r = width > 0 ? clampedX / width : 0
            root.dragValue = Math.round(root.min + r * (root.max - root.min))
            pinnedSide = x <= 0 ? -1 : (x >= width ? 1 : 0)
            root.overshoot = pinnedSide * root.maxStretch
        }

        onPressed: (mouse) => {
            updateFromX(mouse.x)
            root.valueCommitted(root.dragValue)
            lastSentValue = root.dragValue
            throttle.start()
        }
        onPositionChanged: (mouse) => { if (pressed) updateFromX(mouse.x) }
        onReleased: {
            throttle.stop()
            root.valueCommitted(root.dragValue)
            lastSentValue = root.dragValue
            pinnedSide = 0
            root.overshoot = 0
            root.settling = true
            settleTimer.restart()
        }
    }

    Timer {
        id: throttle
        interval: 40
        repeat: true
        onTriggered: {
            if (dragArea.lastSentValue !== root.dragValue) {
                root.valueCommitted(root.dragValue)
                dragArea.lastSentValue = root.dragValue
            }
        }
    }
}
