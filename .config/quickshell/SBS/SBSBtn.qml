import QtQuick

// SBSBtn.qml — shared black-bg/white-border click button, factored out
// of the many near-identical Rectangle+Text+MouseArea blocks across
// SBSShell/SBSWifi/SBSBluetooth/SBSLockScreen (adjust/start/stop/
// reset/confirm/reject/submit/connect/etc).
//
// Default size mirrors the one place in SBSShell.qml that sized off
// its label instead of a fixed width/height (the Exit button):
// implicitWidth/Height track the label + fixed padding. Every other
// caller sets explicit width/height, which overrides these implicit
// values exactly like it would on a plain Rectangle -- so this default
// formula only ever applies where the original code relied on it.
Rectangle {
    id: root
    property alias text: label.text
    property color fg: "white"
    property color bc: "white"
    property int size: 10
    property bool bold: false
    property int cursorShape: Qt.ArrowCursor
    signal clicked()

    implicitWidth: label.implicitWidth + 20
    implicitHeight: label.implicitHeight + 12
    color: "black"
    border.color: bc
    border.width: 1
    radius: 4

    SBSText {
        id: label
        anchors.centerIn: parent
        color: root.fg
        size: root.size
        font.bold: root.bold
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.cursorShape
        onClicked: root.clicked()
    }
}
