import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../Services"
import "../Theme"

// CalendarDetail — equivalent of (defwidget calendar-detail ...)
ColumnLayout {
    id: root
    spacing: 10

    readonly property var day: CalendarService.selectedDay

    // Called synchronously the instant the view change fires — snaps the
    // blocks back to their hidden state immediately, before detailPage even
    // starts sliding in. Without this, a block left at opacity:1 from the
    // PREVIOUS day selection would render fully visible during the slide,
    // then playEntrance() (which only fires after the slide finishes) would
    // replay the pop on top of already-visible content.
    function resetEntrance() {
        holidayBlock.opacity = 0
        holidayBlock.scale = 0.9
        holidayBlock.entranceProgress = 0
        eventBlock.opacity = 0
        eventBlock.scale = 0.9
        eventBlock.entranceProgress = 0
    }

    // Called once the page-slide-in has actually finished — plays the
    // real pop-in animation on top of the already-hidden state set by
    // resetEntrance().
    function playEntrance() {
        if (day.has_holiday) holidayPopAnim.restart()
            if (day.has_event) eventPopAnim.restart()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        NavButton {
            text: "\u2190" // ←
            tooltipText: "Back to calendar"
            onClicked: CalendarService.backToMonth()
        }

        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: CalendarService.calendarData.month_name + " "
            + root.day.date + ", " + CalendarService.calendarData.year
            font.pixelSize: Theme.fs(14)
            font.bold: true
            font.family: Theme.fontFamily
            color: Theme.foreground
        }

        Item { implicitWidth: 28 }
    }

    // holiday block
    Rectangle {
        id: holidayBlock
        Layout.fillWidth: true
        visible: root.day.has_holiday
        implicitHeight: holidayRow.implicitHeight + 16
        radius: 8
        color: Theme.background.hslLightness < 0.5
        ? Qt.rgba(1, 1, 1, 0.04)
        : Qt.rgba(0, 0, 0, 0.05)

        opacity: 0
        scale: 0.9
        transformOrigin: Item.Center

        property real entranceProgress: 1
        property real blurAmount: Math.sin(Math.PI * holidayBlock.entranceProgress) * Animations.slideBlurHorizontalLength

        layer.enabled: holidayBlock.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: holidayBlock.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: parent.radius
            anchors.bottomMargin: parent.radius
            width: 2
            color: Qt.rgba(0.769, 0.659, 0.310, 0.60)
        }

        RowLayout {
            id: holidayRow
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: 12
            spacing: 8

            Text {
                text: "\u25CF"
                font.pixelSize: Theme.fs(8)
                color: Qt.rgba(0.769, 0.659, 0.310, 0.90)
            }
            ColumnLayout {
                spacing: 2
                Text {
                    text: "Holiday"
                    font.pixelSize: Theme.fontSizeXs
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.foreground
                }
                Text {
                    text: root.day.holiday_name
                    font.pixelSize: Theme.fs(12)
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.foreground
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
        }

        SequentialAnimation {
            id: holidayPopAnim
            PropertyAction { target: holidayBlock; property: "opacity"; value: 0 }
            PropertyAction { target: holidayBlock; property: "scale"; value: 0.9 }
            PropertyAction { target: holidayBlock; property: "entranceProgress"; value: 0 }
            ParallelAnimation {
                NumberAnimation { target: holidayBlock; property: "opacity"; to: 1; duration: Animations.panelFadeDuration }
                SpringAnimation { target: holidayBlock; property: "scale"; to: 1; spring: Animations.panelSlideSpring; damping: Animations.panelSlideDamping; mass: Animations.panelSlideMass }
                NumberAnimation { target: holidayBlock; property: "entranceProgress"; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut }
            }
        }
    }

    // event block
    Rectangle {
        id: eventBlock
        Layout.fillWidth: true
        visible: root.day.has_event
        implicitHeight: eventCol.implicitHeight + 16
        radius: 8
        color: Theme.background.hslLightness < 0.5
        ? Qt.rgba(1, 1, 1, 0.04)
        : Qt.rgba(0, 0, 0, 0.05)
        opacity: 0
        scale: 0.9
        transformOrigin: Item.Center

        property real entranceProgress: 1
        property real blurAmount: Math.sin(Math.PI * eventBlock.entranceProgress) * Animations.slideBlurHorizontalLength

        layer.enabled: eventBlock.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: eventBlock.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: parent.radius
            anchors.bottomMargin: parent.radius
            width: 2
            color: Qt.rgba(0.361, 0.620, 0.431, 0.60)
        }

        ColumnLayout {
            id: eventCol
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: 12
            spacing: 6

            RowLayout {
                spacing: 8
                Text { text: "\u25CF"; font.pixelSize: Theme.fs(8); color: Qt.rgba(0.361, 0.620, 0.431, 0.90) }
                Text {
                    text: "Events"
                    font.pixelSize: Theme.fontSizeXs
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.foreground
                }
            }

            Repeater {
                model: root.day.events
                delegate: Text {
                    Layout.fillWidth: true
                    text: "\u00B7 " + modelData
                    font.pixelSize: Theme.fs(12)
                    font.bold: true
                    font.family: Theme.fontFamily
                    color:Theme.foreground
                    wrapMode: Text.WordWrap
                }
            }
        }

        SequentialAnimation {
            id: eventPopAnim
            PropertyAction { target: eventBlock; property: "opacity"; value: 0 }
            PropertyAction { target: eventBlock; property: "scale"; value: 0.9 }
            PropertyAction { target: eventBlock; property: "entranceProgress"; value: 0 }
            PauseAnimation { duration: 70 }
            ParallelAnimation {
                NumberAnimation { target: eventBlock; property: "opacity"; to: 1; duration: Animations.panelFadeDuration }
                SpringAnimation { target: eventBlock; property: "scale"; to: 1; spring: Animations.panelSlideSpring; damping: Animations.panelSlideDamping; mass: Animations.panelSlideMass }
                NumberAnimation { target: eventBlock; property: "entranceProgress"; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut }
            }
        }
    }
}
