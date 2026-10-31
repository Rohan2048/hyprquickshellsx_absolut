import QtQuick
import Quickshell
import "../Services"

// SBSLockBatteryStatus.qml — same drawn battery glyph as
// SBSBatteryCorner.qml (the main SBS screen's battery widget): a
// black/white rectangle bar, not an svg icon set. bolt.svg is the
// only svg used here, for the charging overlay. No shake, no
// animation. Unlike SBSBatteryCorner, just the percentage -- no
// wattage, no time-remaining line.
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

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: Battery.capacity + "%"
        color: "white"
        font.pixelSize: 13
        font.family: "SF Pro Display"
    }
}
