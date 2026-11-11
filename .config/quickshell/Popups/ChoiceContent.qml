import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// Everything inside the choice popup's panel. Used by ChoicePopup.qml and, unchanged, by the live preview in
// Settings > Popups > Popup styles, so what you arrange there is exactly what the popup shows.
// `host` is the popup window (a stand-in in the preview). Widgets/PopupArrange makes the pieces movable.
Item {
    id: root

    property var host: null
    readonly property real baseWidth: (host && host.mode === "input") ? 320 : 300
    property alias col: col
    property alias field: field

    implicitWidth: (host && host.mode === "input") ? 320 : 300
    implicitHeight: col.implicitHeight + 32

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 16
        spacing: 8

        GradientText {
            text: host.title
            visible: host.title !== ""
            font.family: Theme.fontFamily
            font.bold: true
            font.pixelSize: Theme.fontSizeLg
            Layout.alignment: Qt.AlignHCenter
        }

        Repeater {
            model: host.mode === "list" ? host.items : []
            delegate: GlassButton {
                required property int index
                required property string modelData
                Layout.fillWidth: true
                implicitHeight: 38
                arrangeId: "item" + (index + 1)     // by position: the real labels come from the script, the preview's are samples
                text: modelData
                active: host.current === index
                onHoveredChanged: if (hovered) host.current = index
                onClicked: host.finish(modelData)
            }
        }

        TextField {
            id: field
            visible: host.mode === "input"
            Layout.fillWidth: true
            implicitHeight: 34
            selectByMouse: true
            horizontalAlignment: TextInput.AlignHCenter
            placeholderText: host.placeholder
            color: Theme.foreground
            placeholderTextColor: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            background: Rectangle {
                radius: Theme.radiusSm
                color: "transparent"
                border.width: 1
                border.color: field.activeFocus ? Theme.accentActive : Theme.borderMuted
            }
            Keys.onReturnPressed: host.finish(text.trim())
            Keys.onEnterPressed: host.finish(text.trim())
            Keys.onEscapePressed: host.cancel()
        }
    }

    PopupArrange { containers: [col] }
}
