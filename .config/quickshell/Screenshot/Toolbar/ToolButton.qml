pragma ComponentBehavior: Bound
import QtQuick
import "../../Services"
import "../../Theme"
Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property bool checkable: false
    property bool checked: false
    property bool enabled: true

    signal clicked()

    implicitWidth: content.implicitWidth + 20
    implicitHeight: 36
    radius: Theme.radiusMd
    color: root.checked ? Theme.color3
    : mouseArea.containsMouse ? Theme.hoverBgStrong
    : "transparent"
    opacity: root.enabled ? 1.0 : 0.4

   Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Text {
            visible: root.icon !== ""
            text: root.icon
            color: root.checked ? Theme.textOnAccent : Theme.foreground
            font.pixelSize: Theme.fs(16)
        }
        Text {
            visible: root.label !== ""
            text: root.label
            color: root.checked ? Theme.textOnAccent : Theme.foreground
            font.pixelSize: Theme.fs(13)
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
