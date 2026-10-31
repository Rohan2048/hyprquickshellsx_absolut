import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"

ColumnLayout {
    id: root
    property string group: ""
    property var commands: []
    signal launched()
    spacing: 2

    readonly property bool expanded: Commands.expandedGroup === group

    GlassButton {
        Layout.preferredWidth: 160
        Layout.alignment: Qt.AlignHCenter
        text: (root.expanded ? "▼ " : "▶ ") + root.group
        elevated: true
        inactiveTextColor: Theme.foreground
        onClicked: Commands.toggleGroup(root.group)
    }

    Item {
        id: clipper
        Layout.fillWidth: true
        Layout.leftMargin: 12
        clip: true
        implicitHeight: root.expanded ? listColumn.implicitHeight : 0
        opacity: root.expanded ? 1 : 0

        Behavior on implicitHeight {
            NumberAnimation { duration: Animations.accordionDuration; easing.type: Animations.accordionEasing }
        }
        Behavior on opacity {
            NumberAnimation { duration: Animations.durationFast; easing.type: Animations.easingStandard }
        }

        ColumnLayout {
            id: listColumn
            width: clipper.width
            spacing: 2

            Repeater {
                model: root.commands
                delegate: CommandEntry {
                    Layout.fillWidth: true
                    cmd: modelData.cmd
                    terminal: modelData.terminal
                    onLaunch: {
                        Commands.launch(modelData.cmd, modelData.terminal)
                        root.launched()
                    }
                    onRemove: Commands.remove(root.group, modelData.cmd, modelData.terminal)
                }
            }
        }
    }
}
