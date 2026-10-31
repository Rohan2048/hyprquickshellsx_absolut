import QtQuick
import QtQuick.Controls
import "../Services"
import "../Theme"

// CalendarDayCell — equivalent of (defwidget calendar-day [day] ...)
//
// NOTE: `modelData` is declared here (not `day`) because CalendarDayCell is
// an externally-defined component used as a Repeater delegate. Qt6 only
// auto-injects `modelData`/`index` into delegates written inline inside the
// Repeater itself — for external component delegates like this one, Qt
// requires the component to declare `required property var modelData`
// itself, or the binding silently fails (ReferenceError: modelData / every
// downstream `day.*` read becomes undefined). `day` is kept as an alias so
// nothing else in this file has to change.
Item {
    id: root
    required property var modelData
    readonly property var day: modelData

    implicitWidth: 32
    implicitHeight: 32

    readonly property bool isFiller: day.filler === true
    readonly property bool clickable: !isFiller && (day.has_event || day.has_holiday)

    readonly property color todayBg: dayArea.pressed
        ? Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.45)
        : Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.35)

        readonly property bool isDarkMode: Theme.background.hslLightness < 0.5

        readonly property color numColor: {
            if (isFiller) return "transparent"
                if (day.today) return Theme.foreground
                    if (day.has_holiday) return Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.75)
                        if (day.weekday === 6) return isDarkMode
                            ? Qt.rgba(0.786, 0.361, 0.749, 0.80)   // sun-day, dark mode
                            : Qt.rgba(0.55, 0.15, 0.55, 0.90)      // sun-day, light mode — darker/more saturated
                            if (day.weekday === 5) return isDarkMode
                                ? Qt.rgba(0.510, 0.498, 0.769, 0.80)   // sat-day, dark mode
                                : Qt.rgba(0.20, 0.20, 0.55, 0.90)      // sat-day, light mode — darker/more saturated
                                return Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.75)
        }

    opacity: isFiller ? 0 : 1

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: root.day.today ? root.todayBg : "transparent"
    }

    Column {
        anchors.centerIn: parent
        spacing: 1

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.isFiller ? "" : String(root.day.date)
            font.pixelSize: Theme.fs(12)
            font.bold: true
            font.family: Theme.fontFamily
            color: root.numColor
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            height: 5

            Rectangle {
                width: 4; height: 4; radius: 2
                anchors.verticalCenter: parent.verticalCenter
                color: (!root.isFiller && root.day.has_event) ? Qt.rgba(0.361, 0.620, 0.431, 0.90) : "transparent"
            }
            Rectangle {
                width: 4; height: 4; radius: 2
                anchors.verticalCenter: parent.verticalCenter
                color: (!root.isFiller && root.day.has_holiday) ? Qt.rgba(0.769, 0.659, 0.310, 0.90) : "transparent"
            }
        }
    }

    MouseArea {
        id: dayArea
        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: root.clickable
        cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: CalendarService.selectDay(root.day)
    }

    ToolTip.visible: dayArea.containsMouse && tooltipText().length > 0
    ToolTip.text: tooltipText()
    ToolTip.delay: 400

    function tooltipText() {
        if (isFiller) return ""
        if (day.has_holiday && day.has_event) return day.holiday_name + " \u00B7 " + day.events[0]
        if (day.has_holiday) return day.holiday_name
        if (day.has_event) return day.events[0]
        return ""
    }
}
