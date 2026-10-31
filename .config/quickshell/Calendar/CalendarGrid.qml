import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../Services"
import "../Theme"

Rectangle {
    id: root
    color: Theme.background.hslLightness < 0.5
    ? Qt.rgba(1, 1, 1, 0.03)
    : Qt.rgba(0, 0, 0, 0.05)
    radius: 10
    implicitHeight: (liveLoader.item ? liveLoader.item.implicitHeight : 0) + 8
    clip: true
    readonly property var flatDays: {
        const cd = CalendarService.calendarData
        return [].concat(cd.week0, cd.week1, cd.week2, cd.week3, cd.week4, cd.week5)
    }

    property var outgoingDays: []

    // Called by CalendarPopup when the panel opens — reuses the same
    // horizontal blur pop the grid already does on month nav, just with
    // fromX: 0 so it fades/blurs in place instead of sliding sideways.
    function playEntrance() {
        liveLoader.progress = 0
        liveLoader.fromX = 0
        liveSlideAnim.restart()
    }

    Component {
        id: gridContentComponent
        ColumnLayout {
            id: contentRoot
            property var days: []
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
                    delegate: Item {
                        Layout.fillWidth: true
                        implicitHeight: wdLabel.implicitHeight
                        Text {
                            id: wdLabel
                            anchors.centerIn: parent
                            text: modelData
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: true
                            font.family: Theme.fontFamily
                            color: {
                                const isDark = Theme.background.hslLightness < 0.5
                                if (modelData === "Sat") return isDark
                                    ? Qt.rgba(0.310, 0.498, 0.769, 0.75)
                                    : Qt.rgba(0.20, 0.20, 0.55, 0.90)
                                    if (modelData === "Sun") return isDark
                                        ? Qt.rgba(0.486, 0.361, 0.749, 0.75)
                                        : Qt.rgba(0.55, 0.15, 0.55, 0.90)
                                        return Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.70)
                            }
                        }
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 7
                rowSpacing: 0
                columnSpacing: 0
                Repeater {
                    model: contentRoot.days
                    delegate: CalendarDayCell { Layout.fillWidth: true }
                }
            }
        }
    }

    // Outgoing (old) content — static snapshot, slides away
    Loader {
        id: outgoingLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 4
        anchors.top: parent.top
        anchors.topMargin: 4
        sourceComponent: gridContentComponent
        visible: false
        onLoaded: item.days = Qt.binding(() => root.outgoingDays)

        property real progress: 1
        property int fromX: 0
        property int toX: 0
        x: fromX + (toX - fromX) * progress
        opacity: 1 - progress
        property real blurAmount: Math.sin(Math.PI * progress) * Animations.slideBlurHorizontalLength

        layer.enabled: outgoingLoader.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: outgoingLoader.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        NumberAnimation on progress {
            id: outgoingSlideAnim
            from: 0; to: 1
            duration: Animations.slideBlurDuration
            easing.type: Animations.slideBlurEasingIn
            running: false
            onStopped: outgoingLoader.visible = false
        }
    }

    // Live content — always bound to current calendarData, slides in
    Loader {
        id: liveLoader
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 4
        anchors.top: parent.top
        anchors.topMargin: 4
        sourceComponent: gridContentComponent
        onLoaded: item.days = Qt.binding(() => root.flatDays)

        property real progress: 1
        property int fromX: 0
        x: fromX * (1 - progress)
        opacity: progress
        property real blurAmount: Math.sin(Math.PI * progress) * Animations.slideBlurHorizontalLength

        layer.enabled: liveLoader.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: liveLoader.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }
        Binding {
            target: liveLoader.item
            property: "days"
            value: root.flatDays
            when: liveLoader.item !== null
        }
        NumberAnimation on progress {
            id: liveSlideAnim
            from: 0; to: 1
            duration: Animations.slideBlurDuration
            easing.type: Animations.slideBlurEasingOut
            running: false
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
    }
}
