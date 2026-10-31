import QtQuick
import "../Theme"

Rectangle {
    id: root
    property string cmd: ""
    property bool terminal: false
    signal launch()
    signal remove()
    readonly property bool hovered: mouse.containsMouse
    radius: Theme.radiusSm
    border.width: 0
    color: hovered ? Theme.hoverBgStrong : "transparent"
    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
    transformOrigin: Item.Center
    scale: hovered ? 1.035 : 1.0
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 3 } }
    implicitHeight: label.implicitHeight + type.implicitHeight + 10
    implicitWidth: 150
    Column {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        Text {
            id: label
            text: root.cmd
            width: parent.width
            elide: Text.ElideRight
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        Text {
            id: type
            text: root.terminal ? "  console" : "  direct"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 3
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (event) => event.button === Qt.MiddleButton ? root.remove() : root.launch()
    }
}
