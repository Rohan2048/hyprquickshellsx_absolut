import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// Everything inside the commands popup's panel. Used by CommandsPopup.qml and, unchanged, by the live preview in
// Settings > Popups > Popup styles, so what you arrange there is exactly what the popup shows.
// `host` is the popup window (a stand-in in the preview). Widgets/PopupArrange makes the pieces movable.
Item {
    id: root

    property var host: null
    readonly property real baseWidth: 220

    implicitWidth: 220
    implicitHeight: 280

    ColumnLayout {
        id: arrangeCol
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 4
            Text {
                text: "Commands"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: Theme.fontSize
                Layout.fillWidth: true
            }
            GlassButton {
                text: "+"
                elevated: true
                fontSize: Theme.fontSizeXl -5
                implicitWidth: 34
                implicitHeight: 34
                onClicked: Commands.addNew()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            model: Commands.groups
            delegate: CommandGroup {
                width: ListView.view.width
                group: modelData.group
                commands: modelData.commands
                onLaunched: host.shown = false
            }
        }
    }

    PopupArrange { containers: [arrangeCol] }
}
