// VolumePopup.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "../Theme"
import "../Widgets"
import "../Services"

PanelWindow {
    id: popup
    visible: false

    implicitWidth: 260
    implicitHeight: contentCol.implicitHeight + 50
    Behavior on implicitHeight {
        NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard }
    }

    property var tracking: null

    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "volume-popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    property real iconCenterOffset: 0
    property real barBottomOffset: 32

    readonly property real horizontalOverhang: 5
    readonly property real verticalGap: 3

    anchors { bottom: true; right: true }
    readonly property real effectiveRightMargin: {
        var screenW = popup.screen ? popup.screen.width : implicitWidth
        var desired = iconCenterOffset - implicitWidth / 2

        if (!popup.tracking) {
            var maxRight = Math.max(0, screenW - implicitWidth)
            return Math.min(Math.max(0, desired), maxRight)
        }

        var minRightMargin = screenW - (popup.tracking.barRightEdge + horizontalOverhang)
        var maxRightMargin = screenW - implicitWidth - popup.tracking.barLeftEdge + horizontalOverhang
        var lo = Math.min(minRightMargin, maxRightMargin)
        var hi = Math.max(minRightMargin, maxRightMargin)
        return Math.min(Math.max(lo, desired), hi)
    }
    property real smoothedRightMargin: effectiveRightMargin
    Behavior on smoothedRightMargin {
        NumberAnimation { duration: 260; easing.type: Easing.OutQuint }
    }
    margins {
        bottom: barBottomOffset + verticalGap
        right: smoothedRightMargin
    }
    property bool closing: false

    // Guards the sink Repeater's model so it never populates on the same
    // frame the popup (and, after an SBS exit, the whole Bar tree) is
    // freshly constructed -- GlassButton's layer/effect setup needs a real
    // attached window before it styles correctly, and the sink buttons are
    // otherwise the only content in this popup built from data that's
    // already fully populated (Volume.sinks, a singleton) on frame one.
    QtObject {
        id: sinkListReady
        property bool ready: false
    }

    function toggle() {
        if (popup.closing) return
            if (popup.visible) popup.close()
                else popup.open()
    }
    function open() {
        if (popup.closing) return
            popup.visible = true
    }
    function close() {
        popup.closing = true
        glassPanel.playExit()
        closeTimer.restart()
    }

    Timer {
        id: closeTimer
        interval: Animations.slideBlurDuration
        onTriggered: {
            popup.visible = false
            popup.closing = false
        }
    }

    onVisibleChanged: {
        if (visible) {
            glassPanel.playEntrance()
            sinkListReady.ready = false
            Qt.callLater(() => sinkListReady.ready = true)
        }
    }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.visible
        onDismissed: popup.close()
    }
    GlassPanel {
        id: glassPanel
        anchors.fill: parent

        property real entranceProgress: 1
        property real exitProgress: 1
        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength

        opacity: entranceProgress * exitProgress
        readonly property real currentBlur: Math.max(glassPanel.entranceBlur, glassPanel.exitBlur)
        layer.enabled: glassPanel.currentBlur > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: glassPanel.currentBlur
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        NumberAnimation on entranceProgress {
            id: glassPanelEntranceAnim
            from: 0; to: 1
            duration: Animations.slideBlurDuration
            easing.type: Animations.slideBlurEasingOut
            running: false
        }
        NumberAnimation on exitProgress {
            id: glassPanelExitAnim
            from: 1; to: 0
            duration: Animations.slideBlurDuration
            easing.type: Animations.slideBlurEasingIn
            running: false
        }
        function playEntrance() { glassPanelExitAnim.stop(); exitProgress = 1; entranceProgress = 0; glassPanelEntranceAnim.restart() }
        function playExit() { glassPanelEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; glassPanelExitAnim.restart() }

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: Theme.gapMd

            Text {
                text: "Volume"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 1
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.gapSm

                GlassButton {
                    text: Volume.muted ? "🔇" : "🔊"
                    onClicked: Volume.toggleMute()
                    implicitWidth: 34
                    implicitHeight: 34
                    borderWidth: 0
                }

                Item {
                    id: volTrack

                    implicitWidth: 150

                    Layout.alignment: Qt.AlignVCenter

                    implicitHeight: dragArea.pressed ? 34 : 22
                    Behavior on implicitHeight {
                        SpringAnimation {
                            spring: Animations.trackSpring
                            damping: Animations.trackDamping
                            mass: Animations.trackMass
                        }
                    }

                    property real dragValue: Volume.volume
                    readonly property real ratio: Math.max(0, Math.min(1, dragValue / 100))
                    property bool settling: false

                    Binding {
                        target: volTrack
                        property: "dragValue"
                        value: Volume.volume
                        when: !dragArea.pressed && !volTrack.settling
                    }

                    Timer {
                        id: settleTimer
                        interval: 250
                        onTriggered: volTrack.settling = false
                    }

                    readonly property real maxStretch: 10
                    readonly property real stretchConstant: 0.60
                    function rubberBand(distance) {
                        return Animations.rubberBand(distance, maxStretch, stretchConstant)
                    }

                    property real overshoot: 0
                    Behavior on overshoot {
                        SpringAnimation {
                            spring: dragArea.pressed && dragArea.pinnedSide !== 0 ? Animations.pinnedStretchSpring : Animations.overshootSpring
                            damping: dragArea.pressed && dragArea.pinnedSide !== 0 ? Animations.pinnedStretchDamping : Animations.overshootDamping
                            mass: dragArea.pressed && dragArea.pinnedSide !== 0 ? Animations.pinnedStretchMass : Animations.overshootMass
                        }
                    }

                    Rectangle {
                        id: track
                        anchors.fill: parent
                        transform: Translate { x: volTrack.overshoot }
                        radius: height / 2
                        color: Theme.hoverBg
                        clip: true

                        Item {
                            id: fill
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom

                            width: Math.round(volTrack.ratio * parent.width)
                            clip: true

                            Rectangle {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                width: track.width
                                height: track.height
                                radius: track.radius
                                color: Theme.accentActive
                            }

                            Behavior on width {
                                enabled: !dragArea.pressed && !volTrack.settling
                                NumberAnimation {
                                    duration: Animations.durationBase
                                    easing.type: Animations.easingStandard
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        preventStealing: true
                        cursorShape: Qt.PointingHandCursor

                        property int pinnedSide: 0
                        property int lastSentValue: -1

                        function updateFromX(x) {
                            const clampedX = Math.max(0, Math.min(width, x))
                            const r = width > 0 ? clampedX / width : 0
                            volTrack.dragValue = Math.round(r * 100)
                            pinnedSide = x <= 0 ? -1 : (x >= width ? 1 : 0)
                            volTrack.overshoot = pinnedSide * volTrack.maxStretch
                        }

                        onPressed: (mouse) => {
                            updateFromX(mouse.x)
                            Volume.setVolume(volTrack.dragValue)
                            lastSentValue = volTrack.dragValue
                            volumeThrottle.start()
                        }
                        onPositionChanged: (mouse) => { if (pressed) updateFromX(mouse.x) }
                        onReleased: {
                            volumeThrottle.stop()
                            Volume.setVolume(volTrack.dragValue)
                            lastSentValue = volTrack.dragValue
                            pinnedSide = 0
                            volTrack.overshoot = 0
                            volTrack.settling = true
                            settleTimer.restart()
                        }
                    }

                    Timer {
                        id: volumeThrottle
                        interval: 40
                        repeat: true
                        onTriggered: {
                            if (dragArea.lastSentValue !== volTrack.dragValue) {
                                Volume.setVolume(volTrack.dragValue)
                                dragArea.lastSentValue = volTrack.dragValue
                            }
                        }
                    }
                }
            }

            // Scrollable sink list
            ScrollView {
                Layout.fillWidth: true
                Layout.preferredHeight: 70
                clip: false

                ColumnLayout {
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: sinkListReady.ready ? Volume.sinks : []
                        delegate: Item {
                            required property var modelData

                            width: parent.width
                            height: 34

                            GlassButton {
                                anchors.horizontalCenter: parent.horizontalCenter

                                implicitWidth: 180
                                implicitHeight: 30
                                clip: false
                                text: modelData.label
                                active: Volume.sink === modelData.label
                                onClicked: Volume.setSink(modelData.sink, modelData.port)
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "OUTPUT DEVICE"
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.bold: true
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                }

                Item {
                    id: outputDeviceRow
                    Layout.fillWidth: true
                    implicitHeight: outputMarquee.implicitHeight

                    MarqueeText {
                        id: outputMarquee
                        anchors.fill: parent
                        text: Volume.sink
                        textColor: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        active: outputHover.containsMouse
                    }

                    MouseArea {
                        id: outputHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                }
            }
        }

    }
}
