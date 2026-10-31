import QtQuick
import QtQuick.Layouts
import "../../Services"

// Bottom-left Volume panel. Reuses Volume.qml (the same event-driven
// pactl-subscribe-backed service the normal VolumePopup uses) -- no new
// polling, just a flat non-blurred redraw of the same live data.
Rectangle {
    id: root
    property bool expanded: false

    color: "black"
    border.color: "white"
    border.width: 1
    radius: 4

    implicitWidth: expanded ? 200 : pillIcon.implicitWidth + 20
    implicitHeight: expanded ? col.implicitHeight + 20 : pillIcon.implicitHeight + 14

    Text {
        id: pillIcon
        visible: !root.expanded
        anchors.centerIn: parent
        text: Volume.muted ? "\ud83d\udd07" : "\ud83d\udd0a"
        color: "white"
        font.pixelSize: 16
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.expanded
        onClicked: root.expanded = true
    }

    Column {
        id: col
        visible: root.expanded
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Text {
            text: "Volume  " + Volume.volume + "%" + (Volume.muted ? " (muted)" : "")
            color: "white"
            font.pixelSize: 12
            font.family: "SF Pro Display "
        }

        Rectangle {
            width: parent.width; height: 14
            color: "black"
            border.color: "white"
            border.width: 1
            radius: 3

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 1
                width: Math.max(0, (parent.width - 2) * (Volume.volume / 100))
                color: "white"
            }

            MouseArea {
                anchors.fill: parent
                onClicked: (mouse) => Volume.setVolume(Math.round((mouse.x / width) * 100))
            }
        }

        Text {
            text: "Output Devices"
            color: "white"
            font.pixelSize: 11
            font.family: "SF Pro Display "
        }

        Repeater {
            model: Volume.sinks
            Rectangle {
                required property var modelData
                width: col.width
                height: sinkLabel.implicitHeight + 6
                color: "transparent"
                border.color: modelData === Volume.sink ? "white" : "#555555"
                border.width: 1
                radius: 3

                Text {
                    id: sinkLabel
                    anchors.centerIn: parent
                    text: modelData
                    color: "white"
                    font.pixelSize: 10
                    font.family: "SF Pro Display "
                    elide: Text.ElideRight
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Volume.setSink(modelData)
                }
            }
        }
    }

    function collapse() { root.expanded = false }
}
