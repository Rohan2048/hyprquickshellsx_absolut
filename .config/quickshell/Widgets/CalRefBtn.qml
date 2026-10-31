import QtQuick
import QtQuick.Controls
import "../Theme"

// CalRefBtn — refresh-style icon button with no resting background.
// Hover state is a perfect circle (radius: width/2), not the rounded-square
// look NavButton uses. Icon color is baked into two inline SVGs (dark/light
// mode variants) switched at runtime by Theme.background.hslLightness.
Item {
    id: root

    signal clicked()
    property int iconSize: 16
    property string tooltipText: ""

    readonly property string darkSvg: "data:image/svg+xml;utf8," +
    "<svg width='24' height='24' viewBox='0 0 24 24' fill='none' xmlns='http://www.w3.org/2000/svg'>" +
    "<path d='M3 12C3 16.9706 7.02944 21 12 21C14.3051 21 16.4077 20.1334 18 18.7083L21 16M21 12C21 7.02944 16.9706 3 12 3C9.69494 3 7.59227 3.86656 6 5.29168L3 8M21 21V16M21 16H16M3 3V8M3 8H8' stroke='%23aaaaaa' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/>" +
    "</svg>"

    readonly property string lightSvg: "data:image/svg+xml;utf8," +
    "<svg width='24' height='24' viewBox='0 0 24 24' fill='none' xmlns='http://www.w3.org/2000/svg'>" +
    "<path d='M3 12C3 16.9706 7.02944 21 12 21C14.3051 21 16.4077 20.1334 18 18.7083L21 16M21 12C21 7.02944 16.9706 3 12 3C9.69494 3 7.59227 3.86656 6 5.29168L3 8M21 21V16M21 16H16M3 3V8M3 8H8' stroke='%23555555' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'/>" +
    "</svg>"

    readonly property string icon: Theme.background.hslLightness < 0.5 ? darkSvg : lightSvg

    implicitWidth: 30
    implicitHeight: 30

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: area.pressed ? Qt.rgba(1, 1, 1, 0.05)
        : area.containsMouse ? Qt.rgba(0, 0, 0, 0.05)
        : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    Image {
        id: iconImg
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        source: root.icon
        sourceSize.width: root.iconSize
        sourceSize.height: root.iconSize
        smooth: true
        fillMode: Image.PreserveAspectFit
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: false
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    ToolTip.visible: area.containsMouse && root.tooltipText.length > 0
    ToolTip.text: root.tooltipText
    ToolTip.delay: 400
}
