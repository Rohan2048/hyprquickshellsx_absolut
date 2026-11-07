import QtQuick

// SBSPanel.qml — shared black-bg/white-border container, factored out
// of the repeated `color: "black"; border.color: "white"; border.width:
// 1; radius: 4` block used for every pill/panel/box in SBSShell.qml.
// Purely a styled Rectangle -- width/height/z/anchors/children all set
// per-instance exactly as before.
Rectangle {
    color: "black"
    border.color: "white"
    border.width: 1
    radius: 4
}
