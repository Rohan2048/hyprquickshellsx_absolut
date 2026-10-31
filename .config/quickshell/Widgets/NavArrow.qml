import QtQuick
import "../Theme"

Item {
    id: root
    property string direction: "right" // "left" or "right"
    signal clicked()

    implicitWidth: label.implicitWidth + 12
    implicitHeight: label.implicitHeight + 12

    scale: mouseArea.containsMouse ? 1.15 : 1.0
    Behavior on scale {
        NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.direction === "left" ? "‹" : "›"
        font.pixelSize: Theme.fs(42)
        font.bold: true
        color: Theme.foreground
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
