pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../Services"
import "../Theme"
import "../Widgets"

PanelWindow {
    id: popup
    visible: false

    property var tracking: null

    WlrLayershell.namespace: "quickshell:musicPopup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    property real iconCenterOffset: 0
    property real barBottomOffset: 32
    readonly property real horizontalOverhang: 5
    readonly property real verticalGap: 3

    anchors { bottom: true; left: true }

    readonly property real effectiveLeftMargin: {
        var screenW = popup.screen ? popup.screen.width : implicitWidth
        var desired = iconCenterOffset - implicitWidth / 2

        if (!popup.tracking) {
            var maxLeft = Math.max(0, screenW - implicitWidth)
            return Math.min(Math.max(0, desired), maxLeft)
        }

        var minLeftMargin = popup.tracking.barLeftEdge - horizontalOverhang
        var maxLeftMargin = popup.tracking.barRightEdge + horizontalOverhang - implicitWidth

        var lo, hi
        if (maxLeftMargin >= minLeftMargin) {
            lo = minLeftMargin
            hi = maxLeftMargin
        } else {
            lo = minLeftMargin
            hi = minLeftMargin
        }
        return Math.min(Math.max(lo, desired), hi)
    }

    property real smoothedLeftMargin: effectiveLeftMargin
    Behavior on smoothedLeftMargin {
        NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
    }

    margins {
        bottom: barBottomOffset + verticalGap
        left: smoothedLeftMargin
    }

    implicitWidth: 340
    implicitHeight: content.implicitHeight
    color: "transparent"

    property real openProgress: 0

    function open() {
        closeAnim.stop()
        popup.visible = true
        openAnim.restart()
    }
    function close() {
        openAnim.stop()
        closeAnim.restart()
    }
    function toggle() {
        if (popup.openProgress > 0) popup.close()
            else popup.open()
    }

    NumberAnimation {
        id: openAnim
        target: popup; property: "openProgress"
        to: 1
        duration: Animations.pageSlideDuration
        easing.type: Animations.pageSlideEasingOut
    }
    NumberAnimation {
        id: closeAnim
        target: popup; property: "openProgress"
        to: 0
        duration: Animations.pageSlideDuration
        easing.type: Animations.pageSlideEasingIn
        onStopped: popup.visible = false
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "musicPopupToggle"
        description: "Toggle music player popup"
        onPressed: popup.toggle()
    }

    IpcHandler {
        target: "musicPopup"
        function toggle() { popup.toggle() }
        function open() { popup.open() }
        function close() { popup.close() }
    }

    Connections {
        target: MusicPlayerService
        function onActiveChanged() {
            if (!MusicPlayerService.active)
                popup.close()
        }
    }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.visible
        onDismissed: popup.close()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: popup.close()
        z: -1
    }

    GlassPanel {
        id: content
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: 340
        implicitHeight: rootCol.implicitHeight + 36
        radius: 20

        y: (1 - popup.openProgress) * (height + 36)
        opacity: popup.openProgress
        property real blurAmount: Math.sin(Math.PI * popup.openProgress) * Animations.slideBlurVerticalLength

        layer.enabled: content.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurVerticalAngle
            length: content.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            id: rootCol
            anchors.centerIn: parent
            width: parent.width - 36
            spacing: 14

            ColumnLayout {
                id: headerCol
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                Rectangle {
                    id: artBox
                    Layout.preferredHeight: 140
                    Layout.preferredWidth: artImg.status === Image.Ready && artImg.sourceSize.height > 0
                    ? Layout.preferredHeight * (artImg.sourceSize.width / artImg.sourceSize.height)
                    : 140
                    Layout.maximumWidth: rootCol.width
                    Layout.alignment: Qt.AlignHCenter
                    radius: 16
                    clip: true
                    color: Qt.rgba(0.4, 0.4, 0.4, 0.20)

                    property real blurLen: 0
                    property real swapOpacity: 1

                    opacity: swapOpacity
                    layer.enabled: artBox.blurLen > 0
                    layer.effect: DirectionalBlur {
                        angle: Animations.slideBlurHorizontalAngle
                        length: artBox.blurLen
                        samples: Animations.slideBlurSamples
                        transparentBorder: true
                    }

                    Connections {
                        target: MusicPlayerService
                        function onArtChanged() { artSwap.restart() }
                    }

                    SequentialAnimation {
                        id: artSwap
                        ParallelAnimation {
                            NumberAnimation { target: artBox; property: "blurLen"; to: Animations.trackSwapBlurLength; duration: Animations.trackSwapOutDuration; easing.type: Animations.trackSwapOutEasing }
                            NumberAnimation { target: artBox; property: "swapOpacity"; to: 0; duration: Animations.trackSwapOutDuration; easing.type: Animations.trackSwapOutEasing }
                        }
                        ScriptAction {
                            script: {
                                artImg.displayArt = MusicPlayerService.art
                            }
                        }
                        ParallelAnimation {
                            NumberAnimation { target: artBox; property: "blurLen"; to: 0; duration: Animations.trackSwapInDuration; easing.type: Animations.trackSwapInEasing }
                            NumberAnimation { target: artBox; property: "swapOpacity"; to: 1; duration: Animations.trackSwapInDuration; easing.type: Animations.trackSwapInEasing }
                        }
                    }

                    Image {
                        id: artImg
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false

                        property string displayArt: MusicPlayerService.art
                        property string targetUrl: {
                            const a = artImg.displayArt
                            if (a === "") return ""
                                return (a.startsWith("http://") || a.startsWith("https://") || a.startsWith("file://"))
                                ? a : "file://" + a
                        }
                        property int retries: 0
                        readonly property int maxRetries: 12

                        source: targetUrl
                        onTargetUrlChanged: retries = 0

                        onStatusChanged: {
                            if (status === Image.Error && targetUrl !== "" && retries < maxRetries) {
                                retries += 1
                                retryTimer.interval = Math.min(2000, 200 * Math.pow(1.5, retries))
                                retryTimer.restart()
                            }
                        }

                        Timer {
                            id: retryTimer
                            interval: 200
                            onTriggered: {
                                artImg.source = ""
                                artImg.source = Qt.binding(function() { return artImg.targetUrl })
                            }
                        }

                        visible: artImg.displayArt !== "" && status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !artImg.visible
                        text: "♪"
                        font.pixelSize: 36
                        font.family: Theme.fontFamily
                        color: Theme.color8 ?? Theme.foreground
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 5

                    Text {
                        id: titleText
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: "Not Playing"
                        color: Theme.foreground
                        font.pixelSize: 15
                        font.family: Theme.fontFamily
                        font.bold: true
                        elide: Text.ElideRight

                        property real blurLen: 0
                        property real swapOpacity: 1

                        opacity: swapOpacity
                        layer.enabled: titleText.blurLen > 0.05
                        layer.effect: DirectionalBlur {
                            angle: Animations.slideBlurHorizontalAngle
                            length: titleText.blurLen
                            samples: Animations.slideBlurSamples
                            transparentBorder: true
                        }

                        Component.onCompleted: text = MusicPlayerService.title !== "" ? MusicPlayerService.title : "Not Playing"

                        Connections {
                            target: MusicPlayerService
                            function onTitleChanged() { titleSwap.restart() }
                        }

                        SequentialAnimation {
                            id: titleSwap
                            PauseAnimation { duration: 30 }
                            ParallelAnimation {
                                NumberAnimation { target: titleText; property: "blurLen"; to: Animations.trackSwapBlurLength; duration: Animations.trackSwapOutDuration; easing.type: Animations.trackSwapOutEasing }
                                NumberAnimation { target: titleText; property: "swapOpacity"; to: 0; duration: Animations.trackSwapOutDuration; easing.type: Animations.trackSwapOutEasing }
                            }
                            ScriptAction {
                                script: {
                                    titleText.text = MusicPlayerService.title !== "" ? MusicPlayerService.title : "Not Playing"
                                }
                            }
                            ParallelAnimation {
                                NumberAnimation { target: titleText; property: "blurLen"; to: 0; duration: Animations.trackSwapInDuration; easing.type: Animations.trackSwapInEasing }
                                NumberAnimation { target: titleText; property: "swapOpacity"; to: 1; duration: Animations.trackSwapInDuration; easing.type: Animations.trackSwapInEasing }
                            }
                        }
                    }

                    Text {
                        id: artistText
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: ""
                        color: Theme.foreground
                        font.pixelSize: 12
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight

                        property real blurLen: 0
                        property real swapOpacity: 1

                        opacity: swapOpacity
                        layer.enabled: artistText.blurLen > 0.05
                        layer.effect: DirectionalBlur {
                            angle: Animations.slideBlurHorizontalAngle
                            length: artistText.blurLen
                            samples: Animations.slideBlurSamples
                            transparentBorder: true
                        }

                        Component.onCompleted: text = MusicPlayerService.artist

                        Connections {
                            target: MusicPlayerService
                            function onArtistChanged() { artistSwap.restart() }
                        }

                        SequentialAnimation {
                            id: artistSwap
                            PauseAnimation { duration: 55 }
                            ParallelAnimation {
                                NumberAnimation { target: artistText; property: "blurLen"; to: Animations.trackSwapBlurLength; duration: Animations.trackSwapOutDuration; easing.type: Animations.trackSwapOutEasing }
                                NumberAnimation { target: artistText; property: "swapOpacity"; to: 0; duration: Animations.trackSwapOutDuration; easing.type: Animations.trackSwapOutEasing }
                            }
                            ScriptAction {
                                script: {
                                    artistText.text = MusicPlayerService.artist
                                }
                            }
                            ParallelAnimation {
                                NumberAnimation { target: artistText; property: "blurLen"; to: 0; duration: Animations.trackSwapInDuration; easing.type: Animations.trackSwapInEasing }
                                NumberAnimation { target: artistText; property: "swapOpacity"; to: 1; duration: Animations.trackSwapInDuration; easing.type: Animations.trackSwapInEasing }
                            }
                        }
                    }

                    Text {
                        id: albumText
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: MusicPlayerService.album
                        color: Theme.foreground
                        font.pixelSize: 10
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                    }
                }
            }

            ColumnLayout {
                id: seekGroup
                Layout.fillWidth: true
                spacing: 2

                Item {
                    id: seekTrack
                    Layout.fillWidth: true
                    implicitHeight: 16

                    property bool dragging: false
                    readonly property real ratio: MusicPlayerService.duration > 0
                    ? Math.min(1, Math.max(0, MusicPlayerService.position / MusicPlayerService.duration))
                    : 0

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.rgba(0.5, 0.5, 0.5, 0.35)
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * seekTrack.ratio
                        height: 4
                        radius: 2
                        color: Theme.color1
                    }

                    Rectangle {
                        width: 12
                        height: 12
                        radius: 6
                        color: Theme.foreground
                        anchors.verticalCenter: parent.verticalCenter
                        x: Math.min(parent.width - width, Math.max(0, parent.width * seekTrack.ratio - width / 2))
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPressed: mouse => {
                            seekTrack.dragging = true
                            MusicPlayerService.seeking = true
                            const percent = Math.min(100, Math.max(0, (mouse.x / width) * 100))
                            MusicPlayerService.position = (percent / 100) * MusicPlayerService.duration
                        }
                        onPositionChanged: mouse => {
                            if (!seekTrack.dragging) return
                                const percent = Math.min(100, Math.max(0, (mouse.x / width) * 100))
                                MusicPlayerService.position = (percent / 100) * MusicPlayerService.duration
                                MusicPlayerService.positionFmt = MusicPlayerService.fmt(MusicPlayerService.position)
                        }
                        onReleased: mouse => {
                            const percent = Math.min(100, Math.max(0, (mouse.x / width) * 100))
                            MusicPlayerService.seek(percent)
                            seekTrack.dragging = false
                            MusicPlayerService.seeking = false
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: MusicPlayerService.positionFmt
                        color: Theme.foreground
                        font.pixelSize: 10
                        font.family: Theme.fontFamily
                    }
                    Text {
                        text: MusicPlayerService.durationFmt
                        color: Theme.foreground
                        font.pixelSize: 10
                        font.family: Theme.fontFamily
                    }
                }
            }

            RowLayout {
                id: controlsRow
                Layout.alignment: Qt.AlignHCenter
                spacing: 10

                Rectangle {
                    width: 38; height: 38; radius: 19
                    color: prevArea.containsMouse ? Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.25) : "transparent"
                    Text { anchors.centerIn: parent; text: "⏮"; font.pixelSize: 16; font.family: Theme.fontFamily; color: Theme.foreground }
                    MouseArea { id: prevArea; anchors.fill: parent; hoverEnabled: true; onClicked: MusicPlayerService.previous() }
                }

                Rectangle {
                    width: 46; height: 46; radius: 23
                    color: Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, playArea.containsMouse ? 0.55 : 0.25)
                    border.width: 1.5
                    border.color: Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.70)
                    Text {
                        anchors.centerIn: parent
                        text: MusicPlayerService.playing ? "⏸" : "▶"
                        font.pixelSize: 18
                        font.family: Theme.fontFamily
                        color: Theme.foreground
                    }
                    MouseArea { id: playArea; anchors.fill: parent; hoverEnabled: true; onClicked: MusicPlayerService.playPause() }
                }

                Rectangle {
                    width: 38; height: 38; radius: 19
                    color: nextArea.containsMouse ? Qt.rgba(Theme.color1.r, Theme.color1.g, Theme.color1.b, 0.25) : "transparent"
                    Text { anchors.centerIn: parent; text: "⏭"; font.pixelSize: 16; font.family: Theme.fontFamily; color: Theme.foreground }
                    MouseArea { id: nextArea; anchors.fill: parent; hoverEnabled: true; onClicked: MusicPlayerService.next() }
                }
            }
        }
    }
}
