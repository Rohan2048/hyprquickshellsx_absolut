pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import "../Services"
import "../Widgets"
import "../Theme"
import "./logic/apply.js" as ApplyLogic

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "osd-popup"
    exclusiveZone: 0
    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }
    margins.bottom: 50

    implicitHeight: 56

    visible: false

    mask: Region {}

    property bool showPill: false
    property real pillValue: 0
    property string kind: ""
    property bool rapidUpdate: false
    property real lastApplyTime: 0

    // Keep in sync with VOLUME_OSD_LIMIT (default 1.25) in volume-osd.c
    readonly property real volumeLimit: 1.25

    readonly property color fgColor: Theme.isDark ? "#ffffff" : "#000000"
    readonly property color pillTrackColor: Theme.isDark ? "#40ffffff" : "#40000000"
    readonly property color pillDangerColor: "#ff4d4d"

    // Red as soon as we're past 100%
    readonly property bool volumeBoosted: root.kind === "volume" && root.pillValue > 1.0
    // "Max" text only once the hard limit is actually reached
    readonly property bool volumeAtLimit: root.kind === "volume" && root.pillValue >= (root.volumeLimit - 0.001)

    // Wider labels that need extra room since they have no pill to anchor width to
    readonly property bool needsWideLabel: root.kind === "vnc_on" || root.kind === "vnc_off"

    readonly property string iconSource: {
        const home = Quickshell.env("HOME")
        if (root.kind === "volume") return "file://" + home + "/.config/icons/sound.svg"
            if (root.kind === "volume_muted") return "file://" + home + "/.config/icons/sound-off.svg"
                if (root.kind === "volume_unmuted") return "file://" + home + "/.config/icons/sound.svg"
                    if (root.kind === "brightness") return "file://" + home + "/.config/icons/brightness.svg"
                        if (root.kind === "mic_on") return "file://" + home + "/.config/icons/microphone-on.svg"
                            if (root.kind === "mic_off") return "file://" + home + "/.config/icons/microphone-off.svg"
                                if (root.kind === "touchpad_on") return "file://" + home + "/.config/icons/touchpad.svg"
                                    if (root.kind === "touchpad_off") return "file://" + home + "/.config/icons/touchpad-off.svg"
                                        if (root.kind === "vnc_on") return "file://" + home + "/.config/icons/vnc-on.svg"
                                            if (root.kind === "vnc_off") return "file://" + home + "/.config/icons/vnc-off.svg"
                                                return ""
    }
    Timer {
        id: hideTimer
        interval: 1700
        onTriggered: root._playExit()
    }

    IpcHandler {
        target: "osd"

        function show(kind: string, value: string): void {
            const v = (value && value.length > 0) ? parseFloat(value) : 0
            root._apply(kind, isNaN(v) ? 0 : v)
        }
    }

    function _apply(kind, value) {
        const now = Date.now()
        rapidUpdate = (now - lastApplyTime) < 120
        lastApplyTime = now

        root.kind = kind
        ApplyLogic.apply({ root: root, glyph: glyph, label: label }, kind, value)

        hideTimer.restart()
        if (!root.visible) {
            root.visible = true
            _playEntrance()
        }
    }

    NumberAnimation {
        id: entranceFade
        target: content
        property: "opacity"
        from: 0
        to: 1
        duration: Animations.panelFadeDuration
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: exitFade
        target: content
        property: "opacity"
        from: 1
        to: 0
        duration: Animations.panelFadeDuration
        easing.type: Easing.InCubic
        onRunningChanged: if (!running) root.visible = false
    }

    function _playEntrance() {
        content.y = content.restY
        entranceFade.start()
    }

    function _playExit() {
        exitFade.start()
    }

    Item {
        id: content
        anchors.horizontalCenter: parent.horizontalCenter
        // Grows to make room for "Max" instead of touching the bars at all.
        readonly property int baseWidth: 180
        readonly property int maxLabelSpace: 35
        readonly property int wideLabelSpace: 25
        readonly property real pillRowWidth: baseWidth - 16 - 16 - 20 - 15

        width: baseWidth
        + (root.volumeAtLimit ? maxLabelSpace : 0)
        + (root.needsWideLabel ? wideLabelSpace : 0)

        Behavior on width {
            NumberAnimation {
                duration: Animations.durationBase
                easing.type: Animations.easingStandard
            }
        }

        property real restY: (root.implicitHeight - height) / 2
        y: restY
        opacity: 0
        height: 48

        GlassPanel {
            id: glassBackground
            anchors.fill: parent
        }

        Item {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16

            Item {
                id: iconArea
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20

                readonly property bool needsThemeTint: true

                Image {
                    id: iconImage
                    anchors.fill: parent
                    source: root.iconSource
                    visible: root.iconSource.length > 0 && !iconArea.needsThemeTint
                    sourceSize.width: 40
                    sourceSize.height: 40
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                ColorOverlay {
                    anchors.fill: iconImage
                    source: iconImage
                    color: root.fgColor
                    visible: iconArea.needsThemeTint
                }

                Text {
                    id: glyph
                    anchors.centerIn: parent
                    font.pixelSize: Theme.fs(20)
                    color: root.fgColor
                    visible: root.iconSource.length === 0
                }
            }

            Column {
                id: textColumn
                anchors.left: iconArea.right
                anchors.right: parent.right
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Text {
                    id: statusLabel
                    width: parent.width
                    color: root.fgColor
                    font.pixelSize: Theme.fs(14)
                    horizontalAlignment: Text.AlignHCenter
                    visible: text.length > 0
                }

                Row {
                    id: pillContainer
                    width: parent.width
                    height: Math.max(pillRow.height, maxLabel.implicitHeight)
                    visible: root.showPill
                    spacing: 8

                    Row {
                        id: pillRow
                        // Always fixed — computed from baseWidth, so bar
                        // sizes never move regardless of Max/color state.
                        width: content.pillRowWidth
                        height: 4
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        readonly property int segments: 10
                        readonly property int activeSegments:
                        Math.round(Math.max(0, Math.min(1, root.pillValue)) * segments)

                        Repeater {
                            model: pillRow.segments

                            delegate: Rectangle {
                                required property int index
                                width: (pillRow.width - (pillRow.segments - 1) * pillRow.spacing) / pillRow.segments
                                height: parent.height
                                radius: 0
                                color: index < pillRow.activeSegments
                                ? (root.volumeBoosted ? root.pillDangerColor : root.fgColor)
                                : root.pillTrackColor

                                Behavior on color {
                                    enabled: !root.rapidUpdate
                                    ColorAnimation {
                                        duration: Animations.durationBase
                                        easing.type: Animations.easingStandard
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        id: maxLabel
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Max"
                        visible: opacity > 0
                        opacity: root.volumeAtLimit ? 1 : 0
                        color: root.pillDangerColor
                        font.pixelSize: Theme.fs(11)
                        font.bold: true

                        Behavior on opacity {
                            NumberAnimation {
                                duration: Animations.durationBase
                                easing.type: Animations.easingStandard
                            }
                        }
                    }
                }

                // kept for ApplyLogic compatibility — mirrors statusLabel,
                // invisible, never shown
                Text {
                    id: label
                    visible: false
                    onTextChanged: statusLabel.text = text
                }
            }
        }
    }
}
