import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Services"
import "../Widgets"

GridView {
    id: root

    property int cellSize: 48
    cellHeight: cellSize
    clip: true

    readonly property int columns: Math.max(1, Math.floor(width / cellSize))
    cellWidth: width / columns

    // ---- Entrance / exit triggers ----
    // Parent (Applications.qml) increments these on open()/close().
    property int introTrigger: 0
    property int outroTrigger: 0

    readonly property int staggerPerRowMs: 18
    readonly property int maxStaggerRows: 6
    readonly property int entranceDuration: Animations.durationBase

    readonly property int outroDuration: entranceDuration + maxStaggerRows * staggerPerRowMs

    signal activated(var itemData, int index)

    delegate: Item {
        id: cell
        required property var modelData
        required property int index
        width: root.cellWidth
        height: root.cellHeight

        readonly property int row: Math.floor(index / Math.max(root.columns, 1))

        opacity: 0
        scale: 0.94

        function playIntro() {
            const delayRows = Math.min(cell.row, root.maxStaggerRows)
            introTimer.interval = delayRows * root.staggerPerRowMs
            introTimer.restart()
        }
        function playOutro() {
            const delayRows = Math.min(cell.row, root.maxStaggerRows)
            outroTimer.interval = delayRows * root.staggerPerRowMs
            outroTimer.restart()
        }

        Component.onCompleted: cell.playIntro()

        Connections {
            target: root
            function onIntroTriggerChanged() { cell.playIntro() }
            function onOutroTriggerChanged() { cell.playOutro() }
        }

        Timer {
            id: introTimer
            interval: 0
            repeat: false
            onTriggered: { fadeIn.start(); popIn.start() }
        }
        Timer {
            id: outroTimer
            interval: 0
            repeat: false
            onTriggered: { fadeOut.start(); popOut.start() }
        }

        NumberAnimation {
            id: fadeIn
            target: cell; property: "opacity"
            from: 0; to: 1
            duration: root.entranceDuration
            easing.type: Animations.easingStandard
        }
        NumberAnimation {
            id: popIn
            target: cell; property: "scale"
            from: 0.94; to: 1
            duration: root.entranceDuration
            easing.type: Easing.OutBack
        }
        NumberAnimation {
            id: fadeOut
            target: cell; property: "opacity"
            from: 1; to: 0
            duration: root.entranceDuration
            easing.type: Easing.InCubic
        }
        NumberAnimation {
            id: popOut
            target: cell; property: "scale"
            from: 1; to: 0.94
            duration: root.entranceDuration
            easing.type: Easing.InCubic
        }

        MouseArea {
            id: hoverArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.activated(cell.modelData, cell.index)

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 6

                Image {
                    id: icon
                    Layout.alignment: Qt.AlignHCenter
                    source: cell.modelData && cell.modelData.icon ? cell.modelData.icon : ""
                    Layout.preferredWidth: root.cellSize * 0.5
                    Layout.preferredHeight: root.cellSize * 0.5
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true

                    readonly property real iconHoverScale: 1.18

                    scale: hoverArea.containsMouse ? icon.iconHoverScale : 1.0

                    Behavior on scale {
                        NumberAnimation {
                            duration: Animations.hoverScaleDuration
                            easing.type: Animations.hoverScaleEasing
                        }
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: root.cellSize - 8
                    text: cell.modelData && cell.modelData.name ? cell.modelData.name : ""
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }
            }
        }
    }
}
