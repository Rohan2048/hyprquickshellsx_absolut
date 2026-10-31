import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"


PanelWindow {
    id: popup
    readonly property real uiScale: PopupSettings.scaleOf("commands")
    property bool shown: false
    property bool hiding: false
    property real openProgress: 0
    visible: shown || hiding
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:commands"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: 0

    // Placement from Settings > Popups > Commands palette. Default = right edge, centred.
    readonly property string placement: PopupSettings.commandsPlacement
    readonly property string pV: placement.split("-")[0]     // top | center | bottom
    readonly property string pH: placement.split("-")[1]     // left | center | right
    readonly property real edgeGap: placement === "center-right" ? 0 : 12
    anchors.left: pH === "left"
    anchors.right: pH === "right"
    anchors.top: pV === "top"
    anchors.bottom: pV === "bottom"
    margins.left: edgeGap
    margins.right: edgeGap
    margins.top: edgeGap
    margins.bottom: edgeGap

    implicitWidth: 220 * uiScale
    implicitHeight: 280 * uiScale

    onShownChanged: {
        if (shown) {
            hiding = false
            closeAnim.stop()
            openAnim.restart()
        } else {
            hiding = true
            hideTimer.restart()
            openAnim.stop()
            closeAnim.restart()
        }
    }
    NumberAnimation {
        id: openAnim
        target: popup; property: "openProgress"
        to: 1
        duration: Animations.slideBlurDuration    // was: slideBlurDuration(50)
        easing.type: Animations.slideBlurEasingOut
    }
    NumberAnimation {
        id: closeAnim
        target: popup; property: "openProgress"
        to: 0
        duration: Animations.slideBlurDuration    // was: slideBlurDuration(50)
        easing.type: Animations.slideBlurEasingIn
    }

    Timer {
        id: hideTimer
        interval: 220
        onTriggered: popup.hiding = false
    }
    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.visible
        onDismissed: popup.shown = false
    }
    IpcHandler {
        target: "commands"
        function toggle() { popup.shown = !popup.shown }

    }

    readonly property real commandsBlurLength: (pH === "center" ? Animations.slideBlurVerticalLength : Animations.slideBlurHorizontalLength) * 1.1 * Animations.blurEnvelope(popup.openProgress)

    PopupScale {
        anchors.fill: parent
        popupId: "commands"

        Item {
            id: content
            anchors.fill: parent
            opacity: popup.openProgress
            // slides in from the side it sits on; centred columns slide in from top / bottom
            x: popup.pH === "left" ? -Animations.slideBlurHorizontalLength * (1 - popup.openProgress)
            : (popup.pH === "right" ? Animations.slideBlurHorizontalLength * (1 - popup.openProgress) : 0)
            y: popup.pH === "center" ? (popup.pV === "top" ? -24 : 24) * (1 - popup.openProgress) : 0

            GlassPanel {
                anchors.fill: parent
                radius: PopupSettings.radiusOf("commands")
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        Text {
                            text: "Commands"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.bold: true
                            font.pixelSize: Theme.fontSize
                            Layout.fillWidth: true
                        }
                        GlassButton {
                            text: "+"
                            elevated: true
                            fontSize: Theme.fontSizeXl -5
                            implicitWidth: 34
                            implicitHeight: 34
                            onClicked: Commands.addNew()
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        model: Commands.groups
                        delegate: CommandGroup {
                            width: ListView.view.width
                            group: modelData.group
                            commands: modelData.commands
                            onLaunched: popup.shown = false
                        }
                    }
                }
            }
        }

        DirectionalBlur {
            anchors.fill: content
            source: content
            visible: popup.commandsBlurLength > 0
            angle: popup.pH === "center" ? Animations.slideBlurVerticalAngle : Animations.slideBlurHorizontalAngle
            length: popup.commandsBlurLength
            samples: Animations.slideBlurSamples
            opacity: content.opacity
            x: content.x
            y: content.y
        }
    }
}
