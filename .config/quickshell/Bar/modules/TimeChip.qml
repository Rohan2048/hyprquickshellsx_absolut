import QtQuick
import "../../Theme"
import "../../Services"

Item {
    id: root

    property string text: ""
    property string templateText: "00:00"
    property bool chip: false
    property color chipColor: "#e5484d"
    property color chipTextColor: "white"
    signal activated()

    property var cfg: BarSettings
    readonly property bool vertical: cfg.vertical
    readonly property real _inner: metrics.advanceWidth + (chip ? 12 : 0)

    implicitWidth: vertical ? cfg.thickness : Math.max(34, _inner + 10)
    implicitHeight: vertical ? (chip ? 18 : 14) + 16 : cfg.thickness
    width: implicitWidth
    height: implicitHeight

    TextMetrics {
        id: metrics
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
        font.bold: root.chip
        text: root.templateText
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: mouse.containsMouse ? Theme.hoverBg : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    Rectangle {
        visible: root.chip
        anchors.centerIn: parent
        width: root.vertical ? Math.min(root._inner, root.width - 6) : root._inner
        height: 18
        radius: 4
        color: root.chipColor
    }

    Text {
        anchors.centerIn: parent
        width: root.vertical ? root.width - 8 : implicitWidth
        horizontalAlignment: Text.AlignHCenter
        fontSizeMode: root.vertical ? Text.HorizontalFit : Text.FixedSize
        minimumPixelSize: 6
        text: root.text
        color: root.chip ? root.chipTextColor : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
        font.bold: root.chip
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
