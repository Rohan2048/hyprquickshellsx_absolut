import QtQuick
import QtQuick.Layouts
import "../../Services"

// Left-side Commands list. Reuses Commands.qml (same groups/expandedGroup/
// launch() as the normal CommandsPopup) -- just a flat, blur-free redraw
// of the same data, per the mockup's "Commands" accordion.
Rectangle {
    id: root
    property bool expanded: false

    color: "black"
    border.color: "white"
    border.width: 1
    radius: 4

    implicitWidth: expanded ? 220 : pillLabel.implicitWidth + 24
    implicitHeight: expanded ? Math.min(340, col.implicitHeight + 20) : pillLabel.implicitHeight + 14

    Text {
        id: pillLabel
        visible: !root.expanded
        anchors.centerIn: parent
        text: "Commands"
        color: "white"
        font.pixelSize: 12
        font.family: "SF Pro Display"
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.expanded
        onClicked: root.expanded = true
    }

    Column {
        visible: root.expanded
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        Row {
            width: parent.width
            height: Math.max(headerLabel.implicitHeight, addBtn.implicitHeight)

            Text {
                id: headerLabel
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - addBtn.implicitWidth
                text: "Commands"
                color: "white"
                font.pixelSize: 12
                font.bold: true
                font.family: "SF Pro Display"
            }

            Rectangle {
                id: addBtn
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                color: "transparent"
                border.color: "white"
                border.width: 1
                radius: 3
                implicitWidth: 22
                implicitHeight: 22

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: "white"
                    font.pixelSize: 13
                    font.family: "SF Pro Display"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Commands.addNew()
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: "white"; opacity: 0.3 }

        Flickable {
            width: parent.width
            height: parent.height - headerLabel.implicitHeight - 12
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true

            Column {
                id: col
                width: parent.width
                spacing: 6

                Repeater {
                    model: Commands.groups

                    Column {
                        required property var modelData
                        width: col.width
                        spacing: 4

                        Row {
                            width: parent.width
                            MouseArea {
                                width: parent.width; height: groupLabel.implicitHeight + 4
                                onClicked: Commands.toggleGroup(modelData.group)
                                Text {
                                    id: groupLabel
                                    text: (Commands.expandedGroup === modelData.group ? "\u25bd " : "\u25b7 ") + modelData.group
                                    color: "white"
                                    font.pixelSize: 12
                                    font.family: "SF Pro Display"
                                }
                            }
                        }

                        Column {
                            visible: Commands.expandedGroup === modelData.group
                            width: parent.width
                            leftPadding: 14
                            spacing: 2

                            Repeater {
                                model: modelData.commands
                                Rectangle {
                                    required property var modelData
                                    width: col.width - 14
                                    height: cmdLabel.implicitHeight + 8
                                    color: "transparent"
                                    border.color: "white"
                                    border.width: 1
                                    radius: 3

                                    Text {
                                        id: cmdLabel
                                        anchors.centerIn: parent
                                        width: parent.width - 12
                                        text: modelData.cmd
                                        color: "white"
                                        font.pixelSize: 11
                                        font.family: "SF Pro Display"
                                        wrapMode: Text.Wrap
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: Commands.launch(modelData.cmd, modelData.terminal)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function collapse() { root.expanded = false }
}
