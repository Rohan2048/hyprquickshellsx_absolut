import QtQuick

// SBSLockSettingsButton.qml — gear toggle for the SBS lock screen's
// quick-settings panel.
//
// Uses the same "\u2699" text glyph SBSShell.qml's own settings gear
// uses, instead of loading settings.svg through an Image + ColorOverlay
// — one less asset, one less effect, and it matches the rest of SBS.
// No hover/click shake, no border-color Behavior.
Rectangle {
    id: root
    signal toggled()
    property bool active: false

    implicitWidth: 40
    implicitHeight: 40
    radius: 4
    color: "black"
    border.width: 1
    border.color: "white"

    Text {
        anchors.centerIn: parent
        text: "\u2699"
        color: "white"
        font.pixelSize: 18
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
