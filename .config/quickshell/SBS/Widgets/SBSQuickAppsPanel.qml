import QtQuick
import QtQuick.Layouts
import "../"

// Top-right Quick Apps. Backed by SBSQuickApps.qml (own 4-slot state file,
// independent from the normal 10-slot Shortcuts). Middle-click a filled
// tile to remove it, per the spec; click an empty tile to add.
Rectangle {
    id: root
    property bool expanded: false

    color: "black"
    border.color: "white"
    border.width: 1
    radius: 4

    implicitWidth: expanded ? grid.implicitWidth + 24 : pillLabel.implicitWidth + 24
    implicitHeight: expanded ? grid.implicitHeight + 24 : pillLabel.implicitHeight + 14

    Text {
        id: pillLabel
        visible: !root.expanded
        anchors.centerIn: parent
        text: "Quick Apps"
        color: "white"
        font.pixelSize: 12
        font.family: "SF Pro Display"
    }

    MouseArea {
        anchors.fill: parent
        enabled: !root.expanded
        onClicked: root.expanded = true
    }

    GridLayout {
        id: grid
        visible: root.expanded
        anchors.centerIn: parent
        columns: 2
        rowSpacing: 10
        columnSpacing: 10

        Repeater {
            model: 4

            Rectangle {
                required property int index
                readonly property var app: index < SBSQuickApps.apps.length ? SBSQuickApps.apps[index] : null

                width: 46; height: 46
                color: "black"
                border.color: "white"
                border.width: 1
                radius: 4

                Text {
                    visible: !parent.app
                    anchors.centerIn: parent
                    text: "+"
                    color: "white"
                    font.pixelSize: 20
                }

                Image {
                    visible: !!parent.app
                    anchors.centerIn: parent
                    width: 28; height: 28
                    source: parent.app ? "file://" + parent.app.icon : ""
                    smooth: true
                    asynchronous: true
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.MiddleButton) {
                            if (parent.app) SBSQuickApps.remove(parent.app.id)
                            return
                        }
                        if (parent.app) SBSQuickApps.launch(parent.app.exec)
                        else SBSQuickApps.openAddPicker()
                    }
                }
            }
        }
    }

    function collapse() { root.expanded = false }
}
