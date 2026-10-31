import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import "../Theme"
import "../Widgets"

Rectangle {
    id: root
    signal toggled()
    property bool active: false

    implicitWidth: 40
    implicitHeight: 40
    // Settings > Lock screen > Settings button: corner radius (-1 = normal)
    property real cornerRadius: -1
    radius: cornerRadius >= 0 ? cornerRadius : Theme.radiusSm
    color: mouse.containsMouse ? Theme.hoverBgStrong : "transparent"
    border.width: 1
    border.color: active ? Theme.accentActive : Theme.borderMuted
    Behavior on color { ColorAnimation { duration: 180 } }
    Behavior on border.color { ColorAnimation { duration: 180 } }

    property real shakeX: 0
    transform: Translate { x: root.shakeX }
    layer.enabled: root.shakeX !== 0
    layer.effect: DirectionalBlur {
        angle: 0
        length: Math.min(10, Math.abs(root.shakeX) * 3)
        samples: 16
    }

    scale: mouse.containsMouse ? 1.06 : 1.0
    transformOrigin: Item.Center
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    SequentialAnimation {
        id: clickShake
        running: false
        PropertyAction { target: root; property: "shakeX"; value: 5 }
        PauseAnimation { duration: 30 }
        PropertyAction { target: root; property: "shakeX"; value: -5 }
        PauseAnimation { duration: 30 }
        PropertyAction { target: root; property: "shakeX"; value: 3 }
        PauseAnimation { duration: 25 }
        PropertyAction { target: root; property: "shakeX"; value: -3 }
        PauseAnimation { duration: 25 }
        PropertyAction { target: root; property: "shakeX"; value: 0 }
    }

    // Called from surface.onVisibleChanged in Lock.qml, same place
    // pwShake gets triggered, so the button shakes both when the lock
    // screen appears and when it goes away.
    function triggerShake() {
        clickShake.stop()
        clickShake.start()
    }
    // kept as an alias so any existing callers of the old name still work
    function triggerEntrance() {
        triggerShake()
    }

    // customisable: Settings > Lock screen > Icons
    ThemedIcon {
        anchors.centerIn: parent
        iconId: "lock-settings"
        fallback: "file://" + Quickshell.env("HOME") + "/.config/icons/settings.svg"
        size: 20
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            clickShake.stop()
            clickShake.start()
            root.toggled()
        }
    }
}
