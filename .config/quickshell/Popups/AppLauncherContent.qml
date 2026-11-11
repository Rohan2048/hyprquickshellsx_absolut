import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// Everything inside the apps popup's panel. Used by AppLauncherPopup.qml and, unchanged, by the live preview in
// Settings > Popups > Popup styles, so what you arrange there is exactly what the popup shows.
// `host` is the popup window (a stand-in in the preview). Widgets/PopupArrange makes the pieces movable.
Item {
    id: root

    property var host: null
    readonly property real baseWidth: 1100
    // this popup has no PopupScale around it, so say which popup these pieces belong to
    property string popupId: "apps"
    property alias picker: picker

    implicitWidth: 1100
    implicitHeight: 648

    AppPicker {
        id: picker
        anchors.fill: parent
        anchors.margins: 14
        host: root.host
        suggest: PopupSettings.appsSuggest
        onPicked: (entry) => { PopupSettings.bumpApp(entry.id); host.close(); entry.execute() }
        onDismissed: host.close()
    }

    // the apps in the grid / list / suggestions are not objects of their own: the pieces are the search, the view button,
    // the suggestions row and the list as a whole
    PopupArrange { containers: [picker.topCol]; skipListButtons: true }
}
