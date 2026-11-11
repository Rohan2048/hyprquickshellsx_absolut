import QtQuick
import Quickshell
import "../../Services"

// Bottom-right battery readout. Reuses the real Battery service (already
// polling sysfs every 10s, no new background work introduced) -- just a
// plain text readout, no icon glyphs/animation/popup. Bolt icon overlays
// the battery glyph while charging; watts shown beside the percentage
// whenever the service reports a nonzero draw.
Row {
    id: root
    readonly property string iconDir: Quickshell.env("HOME") + "/.config/icons"
    spacing: 8
    visible: Battery.hasBattery

    Item {
        width: 22; height: 12
        anchors.verticalCenter: parent.verticalCenter

        Rectangle {
            anchors.fill: parent
            color: "black"
            border.color: "white"
            border.width: 1
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 1
                width: Math.max(1, (parent.width - 2) * (Battery.capacity / 100))
                height: parent.height - 2
                color: "white"
            }
        }

        Image {
            anchors.centerIn: parent
            width: 12; height: 12
            visible: Battery.status === "charging"
            source: "file://" + root.iconDir + "/bolt.svg"
            smooth: true
        }
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        Text {
            text: Battery.capacity + "%" + (Battery.powerWatts > 0 ? " | " + Battery.powerWatts.toFixed(1) + "W" : "")
            color: "white"
            font.pixelSize: 13
            font.family: "SF Pro Display"
        }
        Text {
            visible: Battery.time !== "---"
            text: Battery.time + (Battery.status === "charging" ? " to full" : " remaining")
            color: "white"
            font.pixelSize: 10
            font.family: "SF Pro Display"
        }
    }
}
