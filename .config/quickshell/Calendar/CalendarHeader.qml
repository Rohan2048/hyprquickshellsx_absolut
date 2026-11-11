import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"
// CalendarHeader — equivalent of (defwidget calendar-header ...)
Item {
    id: root
    implicitWidth: 260
    implicitHeight: centerCol.implicitHeight

    // Called by CalendarPopup when the panel opens — morphs the month/year
    // label in with the same horizontal blur pop used for month nav, just
    // without any x displacement (fromX: 0) since there's no "old" label to
    // slide away from on first open. Nav buttons + Today intentionally
    // don't participate in this — they stay exactly as they render.
    function playEntrance() {
        monthYearLabel.progress = 0
        monthYearLabel.fromX = 0
        liveLabelSlideAnim.restart()
    }

    NavButton {
        id: prevBtn
        anchors.left: parent.left
        anchors.verticalCenter: centerCol.verticalCenter
        text: "<"
        tooltipText: "Previous month"
        onClicked: CalendarService.goPrev()
    }

    NavButton {
        id: nextBtn
        anchors.right: parent.right
        anchors.verticalCenter: centerCol.verticalCenter
        text: ">"
        tooltipText: "Next month"
        onClicked: CalendarService.goNext()
    }

    ColumnLayout {
        id: centerCol
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        spacing: 2

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            CalRefBtn {
                id: refreshBtn
                tooltipText: "Refresh calendar"
                onClicked: CalendarService.refresh()

                RotationAnimation {
                    target: refreshBtn
                    from: 360; to: 0
                    duration: 800
                    loops: Animation.Infinite
                    running: CalendarService.refreshing
                }
            }

            // Plain Item wrapper — RowLayout manages THIS item's position,
            // not the label's. The label's own x is free to animate inside
            // it without the layout re-asserting over it and dragging
            // refreshBtn along for the ride.
            Item {
                id: monthYearWrap
                implicitWidth: monthYearLabel.implicitWidth
                implicitHeight: monthYearLabel.implicitHeight

                property string outgoingText: ""

                // Outgoing (old) label — starts at progress 0 since it's not
                // shown until a nav actually starts.
                Text {
                    id: outgoingMonthYearLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: monthYearWrap.outgoingText
                    font.pixelSize: Theme.fs(14)
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.foreground
                    visible: false

                    property real progress: 0
                    property int fromX: 0
                    property int toX: 0
                    x: fromX + (toX - fromX) * progress
                    opacity: 1 - progress
                    property real blurAmount: Math.sin(Math.PI * progress) * Animations.slideBlurHorizontalLength

                    layer.enabled: outgoingMonthYearLabel.blurAmount > 0.05

                    layer.effect: DirectionalBlur {
                        angle: Animations.slideBlurHorizontalAngle
                        length: outgoingMonthYearLabel.blurAmount
                        samples: Animations.slideBlurSamples
                        transparentBorder: true
                    }

                    NumberAnimation on progress {
                        id: outgoingLabelSlideAnim
                        from: 0; to: 1
                        duration: Animations.slideBlurDuration
                        easing.type: Animations.slideBlurEasingIn
                        running: false
                        onStopped: outgoingMonthYearLabel.visible = false
                    }
                }

                // Live label — starts at progress 1 (fully visible, at rest).
                // This is the fix for the "shows empty on first load" bug:
                // opacity is derived FROM progress, so if progress defaulted
                // to 0 the label would be invisible until the first slide ran.
                Text {
                    id: monthYearLabel
                    anchors.verticalCenter: parent.verticalCenter
                    text: CalendarService.calendarData.month_name + " "
                    + CalendarService.calendarData.year
                    font.pixelSize: Theme.fs(14)
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.foreground

                    property real progress: 1
                    property int fromX: 0
                    x: fromX * (1 - progress)
                    opacity: progress
                    property real blurAmount: Math.sin(Math.PI * progress) * Animations.slideBlurHorizontalLength

                    layer.enabled: monthYearLabel.blurAmount > 0.05
                    layer.effect: DirectionalBlur {
                        angle: Animations.slideBlurHorizontalAngle
                        length: monthYearLabel.blurAmount
                        samples: Animations.slideBlurSamples
                        transparentBorder: true
                    }

                    NumberAnimation on progress {
                        id: liveLabelSlideAnim
                        from: 0; to: 1
                        duration: Animations.slideBlurDuration
                        easing.type: Animations.slideBlurEasingOut
                        running: false
                    }

                    Connections {
                        target: CalendarService
                        function onAboutToNavigate(dir) {
                            monthYearWrap.outgoingText = monthYearLabel.text
                            outgoingMonthYearLabel.progress = 0
                            outgoingMonthYearLabel.fromX = 0
                            outgoingMonthYearLabel.toX = dir === "left" ? -14 : 14
                            outgoingMonthYearLabel.visible = true
                            outgoingLabelSlideAnim.restart()
                        }

                        function onSlideDirectionChanged() {
                            const dir = CalendarService.slideDirection
                            if (dir !== "left" && dir !== "right") return

                                monthYearLabel.progress = 0
                                monthYearLabel.fromX = dir === "left" ? 14 : -14
                                liveLabelSlideAnim.restart()
                        }
                    }
                }
            }
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: todayLabel.implicitWidth + 20
            implicitHeight: todayLabel.implicitHeight + 4
            radius: Theme.radiusSm
            color: todayArea.containsMouse ? Qt.rgba(0, 0, 0, 0.40) : Qt.rgba(0, 0, 0, 0.20)

            Text {
                id: todayLabel
                anchors.centerIn: parent
                text: "Today"
                font.pixelSize: Theme.fontSizeSm
                font.bold: true
                font.family: Theme.fontFamily
                color: todayArea.containsMouse ? Theme.foreground : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.70)
            }

            MouseArea {
                id: todayArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: CalendarService.goToday()
            }
        }
    }
}
