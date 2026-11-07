import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../Theme"
import "../Widgets"
import "../Services"
import "../SBS"

// Everything inside the Battery popup's panel: the numbers, the buttons and the optional graphs.
// Used by BatteryPopup.qml and, unchanged, by the live preview in Settings > Popups > Popup styles,
// so what you arrange there is exactly what the popup shows.
//
// Movable pieces (Widgets/PopupElement, ids): percent, remaining, turbo, mode, sbs, graphLevel, graphEnergy,
// prioritise, optimise. Each can be moved / scaled in Settings; the popup grows to fit the layout.
Item {
    id: root

    readonly property real baseWidth: 360
    readonly property bool isCharging: Battery.status === "charging"
    readonly property bool lowBattery: Battery.capacity < 20 && Battery.status !== "charging"
    // false in the Settings preview: nothing there should switch turbo mode, governors and so on
    property bool interactive: true
    // keep the history fresh while this is on screen
    property bool live: true
    readonly property bool wantsGraphs: PopupSettings.batteryGraphLevel || PopupSettings.batteryGraphEnergy

    implicitWidth: baseWidth
    implicitHeight: contentCol.implicitHeight + 28
    // the popup's normal height: the same layout without the optional graphs (the popup scrolls past it)
    readonly property real baseHeight: implicitHeight
        - (graphLevelEl.visible ? graphLevelEl.implicitHeight + contentCol.spacing : 0)
        - (graphEnergyEl.visible ? graphEnergyEl.implicitHeight + contentCol.spacing : 0)

    Timer {
        interval: 30000
        running: root.live && root.wantsGraphs && root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: BatteryInfo.refreshHistory()
    }

    component Graph: PopupElement {
        id: g
        property string title: ""
        property string mode: "level"
        Layout.fillWidth: true
        implicitWidth: root.baseWidth - 32
        ColumnLayout {
            width: g.width
            spacing: 2
            Text {
                text: g.title
                color: Theme.foreground
                opacity: 0.75
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
                font.bold: true
            }
            BatteryChart {
                Layout.fillWidth: true
                compact: true
                today: true
                interactive: root.interactive
                mode: g.mode
                points: BatteryInfo.hist.points ?? []
                now: BatteryInfo.hist.now ?? 0
            }
        }
    }

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: 16
        spacing: 20

        ColumnLayout {
            spacing: 6
            PopupElement {
                elementId: "percent"
                Text {
                    text: Battery.capacity + "%"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXl
                    font.bold: true
                }
            }
            PopupElement {
                elementId: "remaining"
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
                        width: root.isCharging || boltInner.opacity > 0 ? 16 : 0
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
                                if (root.isCharging) {
                                    boltInner.opacity = 1
                                    boltShakeAnim.start()
                                }
                            }

                            Connections {
                                target: root
                                function onIsChargingChanged() {
                                    if (root.isCharging) {
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
        }

        Graph { id: graphLevelEl; visible: PopupSettings.batteryGraphLevel; elementId: "graphLevel"; title: "Battery today"; mode: "level" }
        Graph { id: graphEnergyEl; visible: PopupSettings.batteryGraphEnergy; elementId: "graphEnergy"; title: "Energy used today"; mode: "energy" }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Theme.gapSm

            PopupElement {
                elementId: "turbo"
                visible: Battery.turboMode !== "UNSUPPORTED"
                GlassButton {
                    active: Battery.turboMode === "ON"
                    disabled: root.lowBattery && Battery.turboMode === "OFF"
                    variant: "toggle"
                    defaultRadius: Theme.radiusPill
                    text: (Battery.turboMode === "ON" ? "\u25cf " : "\u25cb ") +
                          (root.lowBattery && Battery.turboMode === "OFF" ? "\u26a0 Low Battery" : "Turbo Mode")
                    onClicked: if (root.interactive) Battery.toggleTurbo()
                }
            }
            PopupElement {
                elementId: "mode"
                GlassButton {
                    variant: "toggle"
                    defaultRadius: Theme.radiusPill
                    text: (Theme.isDark ? "\u2600 " : "\u263e ") + (Theme.isDark ? "Light Mode" : "Dark Mode")
                    onClicked: if (root.interactive) Theme.toggleMode()
                }
            }
            PopupElement {
                elementId: "sbs"
                GlassButton {
                    active: SBSState.active
                    variant: "toggle"
                    defaultRadius: Theme.radiusPill
                    text: (SBSState.active ? "\u25cf " : "\u25cb ") + "Go SBS"
                    onClicked: if (root.interactive) SBSState.toggle()
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 40

            PopupElement {
                elementId: "prioritise"
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
                            onClicked: if (root.interactive) Battery.setGovernor(modelData.key)
                        }
                    }
                }
            }

            PopupElement {
                elementId: "optimise"
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
                            onClicked: if (root.interactive) Battery.setTuned(modelData.key)
                        }
                    }
                }
            }
        }
    }
}
