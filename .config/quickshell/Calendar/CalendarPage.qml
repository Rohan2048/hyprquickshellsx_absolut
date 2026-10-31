import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../Theme"
import "../Widgets"
import "../Services"
import "../Calendar"

Item {
    id: root
    width: parent ? parent.width : 300
    implicitHeight: monthContentCol.implicitHeight
    clip: true

    Item {
        id: monthPage
        width: root.width
        height: root.implicitHeight

        readonly property int offsetSide: -1
        property real offsetProgress: 0
        x: offsetSide * root.width * offsetProgress
        opacity: 1 - offsetProgress
        property real blurAmount: Math.sin(Math.PI * offsetProgress) * Animations.slideBlurHorizontalLength

        layer.enabled: monthPage.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: monthPage.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        ColumnLayout {
            id: monthContentCol
            width: parent.width
            spacing: 4
            CalendarHeader { id: calendarHeaderContent; Layout.fillWidth: true }
            CalendarGrid { id: calendarGridContent; Layout.fillWidth: true }
            CalendarLegend { id: calendarLegendContent; Layout.fillWidth: true }
        }
    }

    Item {
        id: detailPage
        width: root.width
        height: root.implicitHeight

        readonly property int offsetSide: 1
        property real offsetProgress: 1
        x: offsetSide * root.width * offsetProgress
        opacity: 1 - offsetProgress
        property real blurAmount: Math.sin(Math.PI * offsetProgress) * Animations.slideBlurHorizontalLength

        layer.enabled: detailPage.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: detailPage.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        CalendarDetail {
            id: calendarDetailContent
            width: parent.width
        }
    }

    NumberAnimation { id: monthExitAnim; target: monthPage; property: "offsetProgress"; to: 1; duration: Animations.pageSlideDuration; easing.type: Animations.pageSlideEasingIn }
    NumberAnimation { id: detailEnterAnim; target: detailPage; property: "offsetProgress"; to: 0; duration: Animations.pageSlideDuration; easing.type: Animations.pageSlideEasingOut }
    NumberAnimation { id: detailExitAnim; target: detailPage; property: "offsetProgress"; to: 1; duration: Animations.pageSlideDuration; easing.type: Animations.pageSlideEasingIn }
    NumberAnimation { id: monthEnterAnim; target: monthPage; property: "offsetProgress"; to: 0; duration: Animations.pageSlideDuration; easing.type: Animations.pageSlideEasingOut }

    Timer {
        id: detailEntranceTimer
        interval: Animations.pageSlideDuration
        onTriggered: calendarDetailContent.playEntrance()
    }

    Connections {
        target: CalendarService
        function onViewChanged() {
            if (CalendarService.view === "detail") {
                calendarDetailContent.resetEntrance()
                monthExitAnim.start()
                detailEnterAnim.start()
                detailEntranceTimer.restart()
            } else {
                detailExitAnim.start()
                monthEnterAnim.start()
            }
        }
    }

    Component.onCompleted: {
        calendarHeaderContent.playEntrance()
        calendarGridContent.playEntrance()
        calendarLegendContent.playEntrance()
    }
}
