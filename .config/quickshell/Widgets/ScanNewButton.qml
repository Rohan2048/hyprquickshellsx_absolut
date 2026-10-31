import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Services"

// Edge-to-edge list button, purpose-built for "New Networks" (Wi-Fi)
// and "New Devices" (Bluetooth) rows. Unlike NameEntryButton, this has
// no internal padding/implicitWidth that can cause a gap against the
// container edge — it anchors.fill to whatever width it's given.
Item {
    id: control

    signal clicked()

    property string text: ""
    property bool active: false
    property color inactiveTextColor: Theme.foreground
    property bool instantColor: false
    property alias hoverEnabled: mouseArea.hoverEnabled

    property real defaultRadius: Theme.radiusSm
    readonly property var _st: PopupSettings.styleFor(control, control.defaultRadius)
    implicitWidth: 270 * control._st.w
    implicitHeight: 36 * control._st.h
    y:10
    x:3
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: control._st.r
        color: mouseArea.containsMouse && !control.active ? Theme.hoverBgStrong : "transparent"
        border.width: 1

        border.color: control.active
        ? Theme.foreground
        : (mouseArea.containsMouse ? Theme.accentActive : Theme.borderMuted)
        opacity: control.active ? 1.0 : 0.85

        Behavior on color { enabled: !control.instantColor; ColorAnimation { duration: 150 } }
        Behavior on border.color { enabled: !control.instantColor; ColorAnimation { duration: 150 } }
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }

    Text {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 10 + control._st.dx
        anchors.rightMargin: 10 - control._st.dx
        anchors.verticalCenterOffset: control._st.dy
        text: control.text
        color: control.active ? Theme.foreground : control.inactiveTextColor
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        elide: Text.ElideRight
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.clicked()
    }

    states: State {
        name: "hovered"
        when: mouseArea.containsMouse && !control.active
        PropertyChanges { target: bg; opacity: 1.0 }
    }
}
