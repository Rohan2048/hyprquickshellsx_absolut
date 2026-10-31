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
    implicitHeight: 220
    // Behavior on implicitHeight {
    //     NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard }
    // }

    property var tracking: null

    // 0 = devices page, 1 = raw-ports (settings) page
    property int page: 0

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
    // freshly constructed -- VolBtn's layer/effect setup needs a real
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
            popup.page = 0
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

            // ── Header: title + settings toggle ──────────────────────────
            Item {
                Layout.fillWidth: true
                implicitHeight: headerTitle.implicitHeight

                Text {
                    id: headerTitle
                    anchors.centerIn: parent
                    text: popup.page === 0 ? "Volume" : "Output Ports"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }

                Item {
                    id: defaultButton
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: defaultLabel.implicitWidth + 12
                    implicitHeight: 24

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: defaultArea.containsMouse ? Theme.hoverBg : "transparent"
                        Behavior on color { ColorAnimation { duration: Animations.durationBase } }
                    }

                    Text {
                        id: defaultLabel
                        anchors.centerIn: parent
                        text: "Default"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                    }

                    MouseArea {
                        id: defaultArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // Unconditional: always reverts to the built-in laptop
                        // speakers, regardless of what's currently active.
                        onClicked: Volume.resetToDefault()
                    }
                }

                Item {
                    id: settingsButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 24
                    implicitHeight: 24

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: settingsArea.containsMouse || popup.page === 1 ? Theme.hoverBg : "transparent"
                        Behavior on color { ColorAnimation { duration: Animations.durationBase } }
                    }

                    Image {
                        id: settingsIcon
                        anchors.centerIn: parent
                        width: 15
                        height: 15
                        sourceSize: Qt.size(15, 15)
                        smooth: true
                        source: "file://" + Quickshell.env("HOME") + "/.config/icons/settings.svg"
                        rotation: popup.page === 1 ? 90 : 0
                        Behavior on rotation {
                            NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard }
                        }
                        visible: false
                    }
                    ColorOverlay {
                        anchors.fill: settingsIcon
                        source: settingsIcon
                        color: Theme.foreground
                        rotation: settingsIcon.rotation
                    }

                    MouseArea {
                        id: settingsArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: popup.page = popup.page === 0 ? 1 : 0
                    }
                }
            }

            // ── Pager: slides between the devices page and the ports page ─
            Item {
                id: pager
                Layout.fillWidth: true
                clip: true
                implicitHeight: popup.page === 0 ? page0Col.implicitHeight : page1Col.implicitHeight
                Behavior on implicitHeight {
                    NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard }
                }

                // ── Page 0: devices ────────────────────────────────────
                Item {
                    id: page0Wrap
                    width: pager.width
                    height: page0Col.implicitHeight
                    x: popup.page === 0 ? 0 : -pager.width
                    opacity: popup.page === 0 ? 1 : 0
                    Behavior on x { NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard } }
                    Behavior on opacity { NumberAnimation { duration: Animations.durationBase } }

                    ColumnLayout {
                        id: page0Col
                        width: parent.width
                        spacing: Theme.gapMd

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Theme.gapSm

                            VolBtn {
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

                        // Scrollable device list: live sinks + pinned (always-on) ports
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 70
                            clip: false

                            ColumnLayout {
                                width: parent.width
                                spacing: 2

                                Repeater {
                                    model: sinkListReady.ready ? Volume.sinks.filter((s) => s !== "Speakers") : []
                                    delegate: Item {
                                        required property string modelData

                                        width: parent.width
                                        height: 34

                                        VolBtn {
                                            anchors.horizontalCenter: parent.horizontalCenter

                                            implicitWidth: 180
                                            implicitHeight: 30

                                            text: modelData
                                            active: Volume.sink === modelData
                                            onClicked: Volume.setSink(modelData)
                                        }
                                    }
                                }

                                // Always-present entries (e.g. built-in speakers) that
                                // don't survive a profile switch away from analog-stereo,
                                // so they can't come from the sinks list above.
                                Repeater {
                                    model: sinkListReady.ready ? Volume.pinned.filter((p) => p.label !== "Speakers") : []
                                    delegate: Item {
                                        required property var modelData

                                        width: parent.width
                                        height: 34

                                        VolBtn {
                                            anchors.horizontalCenter: parent.horizontalCenter

                                            implicitWidth: 180
                                            implicitHeight: 30

                                            text: modelData.label
                                            active: modelData.active
                                            onClicked: Volume.setPort(modelData.card, modelData.port)
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

                            Text {
                                text: Volume.sink
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1
                                font.bold: true
                                wrapMode: Text.Wrap
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }

                // ── Page 1: raw ports (HDMI / aux / etc) ───────────────
                Item {
                    id: page1Wrap
                    width: pager.width
                    height: page1Col.implicitHeight
                    x: popup.page === 1 ? 0 : pager.width
                    opacity: popup.page === 1 ? 1 : 0
                    Behavior on x { NumberAnimation { duration: Animations.durationBase; easing.type: Animations.easingStandard } }
                    Behavior on opacity { NumberAnimation { duration: Animations.durationBase } }

                    ColumnLayout {
                        id: page1Col
                        width: parent.width
                        spacing: Theme.gapSm

                        ScrollView {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 150
                            clip: false

                            ColumnLayout {
                                width: parent.width
                                spacing: 4

                                Repeater {
                                    model: popup.page === 1 ? Volume.ports : []
                                    delegate: Item {
                                        required property var modelData

                                        width: parent.width
                                        height: 34

                                        VolBtn {
                                            anchors.horizontalCenter: parent.horizontalCenter

                                            implicitWidth: 220
                                            implicitHeight: 30

                                            text: modelData.cardLabel
                                            ? modelData.label + "  ·  " + modelData.cardLabel
                                            : modelData.label
                                            active: modelData.active
                                            onClicked: Volume.setPort(modelData.card, modelData.port)
                                        }
                                    }
                                }

                                Text {
                                    visible: popup.page === 1 && Volume.ports.length === 0
                                    text: "No other output ports detected"
                                    color: Theme.textDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 1
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
