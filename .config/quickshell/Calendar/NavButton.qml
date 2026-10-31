import QtQuick
import QtQuick.Controls
import "../Theme"

// Stand-in for .cal-nav-btn / .cal-refresh-btn. If you already have a
// GlassButton component from the rest of your QuickShell port, swap this
// out for that instead — this exists just to keep the calendar port
// self-contained and runnable on its own.
Rectangle {
    id: root

    signal clicked()
    property string text: ""
    property string tooltipText: ""

    implicitWidth: 28
    implicitHeight: 28
    radius: Theme.radiusMd // scss: border-radius: 12px — matches Theme.radiusMd exactly
    color: area.pressed ? Qt.rgba(0, 0, 0, 0.55)
         : area.containsMouse ? Qt.rgba(0, 0, 0, 0.35)
         : Qt.rgba(1, 1, 1, 0.08)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.15) // scss uses a literal white border here, not $color8/borderMuted

    Text {
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: Theme.fontSize // scss: 13px — matches Theme.fontSize exactly
        font.bold: true
        font.family: Theme.fontFamily
        color: Theme.foreground
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    // Basic tooltip; drop if you have a shared Tooltip component already.
    ToolTip.visible: area.containsMouse && root.tooltipText.length > 0
    ToolTip.text: root.tooltipText
    ToolTip.delay: 400
}
