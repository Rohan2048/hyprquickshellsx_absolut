import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// Everything inside the shortcuts popup's panel. Used by ShortcutPickerPopup.qml and, unchanged, by the live preview in
// Settings > Popups > Popup styles, so what you arrange there is exactly what the popup shows.
// `host` is the popup window (a stand-in in the preview). Widgets/PopupArrange makes the pieces movable.
Item {
    id: root

    property var host: null
    readonly property real baseWidth: 1000
    // this popup has no PopupScale around it, so say which popup these pieces belong to
    property string popupId: "shortcuts"
    property alias picker: picker

    implicitWidth: 1000
    implicitHeight: 648

    AppPicker {
        id: picker
        anchors.fill: parent
        anchors.margins: 14
        placeholder: "Search an app to add as a shortcut..."
        onPicked: (entry) => { if (Shortcuts.addFromEntry(entry)) host.close() }
        onDismissed: host.close()
    }

    PopupArrange { containers: [picker.topCol] }
}
