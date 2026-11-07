import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../Theme"
import "../Services"
// CalendarLegend — equivalent of (defwidget calendar-legend ...)
ColumnLayout {
    id: root
    spacing: 4

    // Entrance morph — called by CalendarPopup when the panel opens.
    // Same horizontal blur pop as the header/grid; the legend has no
    // "old vs new" state to slide between (it's static), so this just
    // fades/blurs in place.
    // Entrance morph — called by CalendarPopup when the panel opens.
    property real entranceProgress: 1
    // Refresh blur — pulses when data reloads
    property real refreshBlur: 0

    opacity: entranceProgress
    property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength

    layer.enabled: (root.entranceBlur + root.refreshBlur) > 0.05
    layer.effect: DirectionalBlur {
        angle: Animations.slideBlurHorizontalAngle
        length: root.entranceBlur + root.refreshBlur
        samples: Animations.slideBlurSamples
        transparentBorder: true
    }

    SequentialAnimation {
        id: refreshPulse
        running: false
        NumberAnimation {
            target: root; property: "refreshBlur"
            from: 0; to: Animations.slideBlurHorizontalLength
            duration: Animations.slideBlurDuration / 2
            easing.type: Animations.slideBlurEasingOut
        }
        NumberAnimation {
            target: root; property: "refreshBlur"
            from: Animations.slideBlurHorizontalLength; to: 0
            duration: Animations.slideBlurDuration / 2
            easing.type: Animations.slideBlurEasingOut
        }
    }

    Connections {
        target: CalendarService
        function onAboutToNavigate(dir) {
            root.outgoingDays = root.flatDays
            outgoingLoader.progress = 0
            outgoingLoader.fromX = 0
            outgoingLoader.toX = dir === "left" ? -14 : 14
            outgoingLoader.visible = true
            outgoingSlideAnim.restart()
        }

        function onSlideDirectionChanged() {
            const dir = CalendarService.slideDirection
            if (dir !== "left" && dir !== "right") return
                liveLoader.progress = 0
                liveLoader.fromX = dir === "left" ? 14 : -14
                liveSlideAnim.restart()
        }

        function onRefreshingChanged() {
            if (!CalendarService.refreshing) return
                // refresh started: freeze current grid as "outgoing", blur it
                // out in place (no slide) using the same mechanism as nav
                root.outgoingDays = root.flatDays
                outgoingLoader.progress = 0
                outgoingLoader.fromX = 0
                outgoingLoader.toX = 0
                outgoingLoader.visible = true
                outgoingSlideAnim.restart()
        }

        function onCalendarDataChanged() {
            if (!CalendarService.refreshing) return
                // new data landed mid-refresh: blur the live grid back in
                liveLoader.progress = 0
                liveLoader.fromX = 0
                liveSlideAnim.restart()
        }

    }
    NumberAnimation on entranceProgress {
        id: entranceAnim
        from: 0; to: 1
        duration: Animations.slideBlurDuration
        easing.type: Animations.slideBlurEasingOut
        running: false
    }

    function playEntrance() {
        root.entranceProgress = 0
        entranceAnim.restart()
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: Qt.rgba(1, 1, 1, 0.08) // scss: border-top: 1px solid rgba(255,255,255,0.08)
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 4
        spacing: 14

        ColumnLayout {
            spacing: 2
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Event"
                font.pixelSize: Theme.fontSizeSm
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.foreground
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "\u25CF"
                font.pixelSize: Theme.fs(8)
                color: Qt.rgba(0.361, 0.620, 0.431, 0.90)
            }
        }

        ColumnLayout {
            spacing: 2
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Holiday"
                font.pixelSize: Theme.fontSizeSm
                font.bold: true
                font.family: Theme.fontFamily
                color: Theme.foreground
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "\u25CF"
                font.pixelSize: Theme.fs(8)
                color: Qt.rgba(0.769, 0.659, 0.310, 0.90)
            }
        }
    }
}
