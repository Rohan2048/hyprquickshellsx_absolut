import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "../Theme"
import "../Widgets"
import "../Services"
import "../SBS"

// Direct port of (defwidget battery-popup-widget) — the "47% / 1:24 remaining /
// Turbo Mode / Prioritise / Optimise For" panel from the screenshot.
PanelWindow {
    id: popup
    visible: false

    implicitWidth: 360
    implicitHeight: contentCol.implicitHeight + 28

    property var tracking: null

    property real iconCenterOffset: 0

    property real barBottomOffset: 32

    // Max pixels the popup may overhang either side of the bar's own
    // rendered edges (not the screen edges) — keeps it visually anchored
    // to the bar for a tight "floaty" look instead of drifting across the
    // screen when the anchor icon sits near a bar edge.
    readonly property real horizontalOverhang: 5

    // Gap between the bar's top edge and the popup's bottom edge, so the
    // popup sits just above the bar instead of flush against it.
    readonly property real verticalGap: 3

    readonly property real effectiveRightMargin: {
        var screenW = popup.screen ? popup.screen.width : implicitWidth
        var desired = iconCenterOffset - implicitWidth / 2

        if (!popup.tracking) {
            var maxRight = Math.max(0, screenW - implicitWidth)
            return Math.min(Math.max(0, desired), maxRight)
        }

        // rightMargin is measured from the screen's right edge, so bar
        // edges (measured from the screen's left edge) need converting:
        //   popup's right edge may sit at most `horizontalOverhang` px
        //   past the bar's right edge  -> sets the minimum right margin
        //   popup's left edge may sit at most `horizontalOverhang` px
        //   past the bar's left edge   -> sets the maximum right margin
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

    // Horizontal tail position, measured from the popup's own left edge.
    // Clamped inward so it never renders past the panel's rounded corners.


    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:popup:battery"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // eww: (geometry :anchor "bottom right") — bar sits at the screen bottom
    anchors { bottom: true; right: true; left: false }
    margins {
        bottom: barBottomOffset + verticalGap
        right: smoothedRightMargin
    }
    property bool closing: false
    readonly property bool isCharging: Battery.status === "charging"

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
        }
    }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.visible
        onDismissed: popup.close()
    }
    readonly property bool lowBattery: Battery.capacity < 20 && Battery.status !== "charging"

    GlassPanel {
        id: glassPanel
        anchors.fill: parent

        // ---- Popup entrance/exit (fade + horizontal motion blur) ----
        property real entranceProgress: 1
        property real exitProgress: 1
        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength

        opacity: entranceProgress * exitProgress
        layer.enabled: entranceProgress < 1 || exitProgress < 1
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: Math.max(glassPanel.entranceBlur, glassPanel.exitBlur)
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
            anchors.margins: 16
            spacing: 20

            ColumnLayout {
                spacing: 6
                Text {
                    text: Battery.capacity + "%"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXl
                    font.bold: true
                }
                RowLayout {
                    spacing: 6
                    Text {
                        text: Battery.time === "---" ? "---" : (Battery.time + " remaining, " + Battery.powerWatts.toFixed(1) + "W")
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeLg
                    }
                    Item {
                        id: boltSlot
                        width: popup.isCharging || boltInner.opacity > 0 ? 16 : 0
                        height: 16
                        visible: boltInner.opacity > 0

                        Behavior on width {
                            NumberAnimation {
                                duration: Animations.scaleDuration(150)
                                easing.type: Animations.slideBlurEasingOut
                            }
                        }

                        Item {
                            id: boltInner
                            width: 16; height: 16
                            opacity: 0

                            property real shakeX: 0
                            transform: Translate { x: boltInner.shakeX }

                            layer.enabled: boltInner.opacity > 0
                            layer.effect: DirectionalBlur {
                                angle: Animations.slideBlurHorizontalAngle
                                length: Math.max(
                                    (1 - boltInner.opacity) * 15,
                                                 Math.abs(boltInner.shakeX) * 4
                                )
                                samples: 16
                            }

                            Image {
                                id: boltImg
                                anchors.fill: parent
                                source: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='%23ffffff'%3E%3Cpath d='M13 2L3 14h9l-1 8 10-12h-9l1-8z'/%3E%3C/svg%3E"
                                sourceSize.width: 16
                                sourceSize.height: 16
                                visible: false
                            }

                            ColorOverlay {
                                anchors.fill: boltImg
                                source: boltImg
                                color: Theme.iconColor
                            }

                            Component.onCompleted: {
                                if (popup.isCharging) {
                                    boltInner.opacity = 1
                                    boltShakeAnim.start()
                                }
                            }

                            Connections {
                                target: popup
                                function onIsChargingChanged() {
                                    if (popup.isCharging) {
                                        boltExitAnim.stop()
                                        boltShakeAnim.stop()
                                        boltInner.shakeX = 0
                                        boltEnterAnim.restart()
                                    } else {
                                        boltEnterAnim.stop()
                                        boltShakeAnim.stop()
                                        boltInner.shakeX = 0
                                        boltExitAnim.restart()
                                    }
                                }
                            }

                            SequentialAnimation {
                                id: boltEnterAnim
                                NumberAnimation {
                                    target: boltInner; property: "opacity"; to: 1
                                    duration: Animations.scaleDuration(120)
                                    easing.type: Animations.slideBlurEasingOut
                                }
                                ScriptAction { script: boltShakeAnim.start() }
                            }

                            SequentialAnimation {
                                id: boltExitAnim
                                ScriptAction { script: boltShakeAnim.start() }
                                PauseAnimation { duration: Animations.scaleDuration(275) }
                                NumberAnimation {
                                    target: boltInner; property: "opacity"; to: 0
                                    duration: Animations.scaleDuration(120)
                                    easing.type: Animations.slideBlurEasingIn
                                }
                            }

                            SequentialAnimation {
                                id: boltShakeAnim
                                NumberAnimation { target: boltInner; property: "shakeX"; to: -2.5; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                                NumberAnimation { target: boltInner; property: "shakeX"; to: 2.5; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                                NumberAnimation { target: boltInner; property: "shakeX"; to: -1.2; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                                NumberAnimation { target: boltInner; property: "shakeX"; to: 1.2; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                                NumberAnimation { target: boltInner; property: "shakeX"; to: 0; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.gapSm

                GlassButton {
                    visible: Battery.turboMode !== "UNSUPPORTED"
                    active: Battery.turboMode === "ON"
                    disabled: popup.lowBattery && Battery.turboMode === "OFF"
                    variant: "toggle"
                    radius: Theme.radiusPill
                    text: (Battery.turboMode === "ON" ? "\u25cf " : "\u25cb ") +
                    (popup.lowBattery && Battery.turboMode === "OFF" ? "\u26a0 Low Battery" : "Turbo Mode")
                    onClicked: Battery.toggleTurbo()
                }

                GlassButton {
                    variant: "toggle"
                    radius: Theme.radiusPill
                    text: (Theme.isDark ? "\u2600 " : "\u263e ") + (Theme.isDark ? "Light Mode" : "Dark Mode")
                    onClicked: Theme.toggleMode()
                }
                GlassButton {
                    active: SBSState.active
                    variant: "toggle"
                    radius: Theme.radiusPill
                    text: (SBSState.active ? "\u25cf " : "\u25cb ") + "Go SBS"
                    onClicked: SBSState.toggle()
                }
            }


            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 40

                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "Prioritise"
                        color: Theme.isDark ? Theme.foreground : Qt.darker(Theme.foreground, 1.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Repeater {
                        model: [
                            { key: "powersave", label: "Powersave" },
                            { key: "balanced", label: "Balanced" },
                            { key: "performance", label: "Performance" }
                        ]
                        delegate: GlassButton {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitWidth: 130
                            text: modelData.label
                            active: Battery.cpuGovernor === modelData.key
                            inactiveTextColor: Theme.isDark ? Theme.textMuted : Qt.darker(Theme.textMuted, 1.5)
                            onClicked: Battery.setGovernor(modelData.key)
                        }
                    }
                }

                ColumnLayout {
                    spacing: 4
                    Text {
                        text: "Optimise For"
                        color: Theme.isDark ? Theme.foreground : Qt.darker(Theme.foreground, 1.5)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Repeater {
                        model: [
                            { key: "powersave", label: "Powersave" },
                            { key: "balanced", label: "Balanced" },
                            { key: "desktop", label: "Desktop" },
                            { key: "latency-performance", label: "Latency" },
                            { key: "throughput-performance", label: "Max Performance" },
                            { key: "virtual-host", label: "VM Host" }
                        ]
                        delegate: GlassButton {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitWidth: 130
                            text: modelData.label
                            active: Battery.tunedProfile === modelData.key
                            inactiveTextColor: Theme.isDark ? Theme.textMuted : Qt.darker(Theme.textMuted, 1.5)
                            onClicked: Battery.setTuned(modelData.key)
                        }
                    }
                }
            }
        }
    }
}
