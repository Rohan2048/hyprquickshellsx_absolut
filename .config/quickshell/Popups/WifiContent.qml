import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import "../Theme"
import "../Widgets"
import "../Services"

// Everything inside the wifi popup's panel. Used by WifiPopup.qml and, unchanged, by the live preview in
// Settings > Popups > Popup styles, so what you arrange there is exactly what the popup shows.
// `host` is the popup window (a stand-in in the preview). Widgets/PopupArrange makes the pieces movable.
Item {
    id: root

    property var host: null
    // 0 / 1 = show only the first (live scan) / second (saved) page, for the Settings preview that shows both pages side by side;
    // -1 = as the service says (the real popup)
    property int page: -1
    readonly property bool liveShown: root.page >= 0 ? root.page === 0 : Wifi.liveMode
    readonly property real baseWidth: 300
    property alias contentCol: contentCol
    property alias emptyStateText: emptyStateText
    property alias gearBtn: gearBtn
    property alias headerTitle: headerTitle
    property alias newNetworksLabel: newNetworksLabel
    property alias newNetworksRepeater: newNetworksRepeater
    property alias radioBtn: radioBtn
    property alias savedNetworksLabel: savedNetworksLabel
    property alias savedRepeater: savedRepeater
    property alias speedRow: speedRow
    property alias statusOverlay: statusOverlay

    implicitWidth: 300
    implicitHeight: contentCol.implicitHeight + 20

    ColumnLayout {
        id: contentCol
        anchors.fill: parent
        anchors.margins: 10
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            anchors.margins: 10

            Text {
                id: headerTitle
                text: "Wi-Fi"
                color: Theme.foreground
                font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.bold: true
                Layout.fillWidth: true

                property real entranceProgress: 1; property real exitProgress: 1
                opacity: entranceProgress * exitProgress
                property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                layer.enabled: entranceProgress < 1 || exitProgress < 1
                layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(headerTitle.entranceBlur, headerTitle.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                NumberAnimation on entranceProgress { id: headerTitleEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                NumberAnimation on exitProgress { id: headerTitleExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                function playEntrance() { headerTitleExitAnim.stop(); exitProgress = 1; entranceProgress = 0; headerTitleEntranceAnim.restart() }
                function playExit() { headerTitleEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; headerTitleExitAnim.restart() }
            }

            Item {
                id: gearBtn
                implicitWidth: gearInner.styledWidth; implicitHeight: gearInner.styledHeight

                property real entranceProgress: 1; property real exitProgress: 1
                opacity: entranceProgress * exitProgress
                property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                layer.enabled: entranceProgress < 1 || exitProgress < 1
                layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(gearBtn.entranceBlur, gearBtn.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                NumberAnimation on entranceProgress { id: gearBtnEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                NumberAnimation on exitProgress { id: gearBtnExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                function playEntrance() { gearBtnExitAnim.stop(); exitProgress = 1; entranceProgress = 0; gearBtnEntranceAnim.restart() }
                function playExit() { gearBtnEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; gearBtnExitAnim.restart() }

                GlassButton {
                    id: gearInner
                    objectName: "settings"
                    anchors.fill: parent
                    implicitWidth: 30; implicitHeight: 26
                    active: root.liveShown
                    onClicked: { instantColor = true; Wifi.toggleLiveMode() }

                    scale: gearHover.hovered ? 1.06 : 1.0
                    transformOrigin: Item.Center
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    HoverHandler { id: gearHover }

                    Image {
                        id: gearIcon
                        anchors.centerIn: parent
                        source: "file://" + Quickshell.env("HOME") + "/.config/icons/settings.svg"
                        sourceSize.width: 14; sourceSize.height: 14
                        width: 14; height: 14
                        visible: false
                        Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                        Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    ColorOverlay { anchors.fill: gearIcon; source: gearIcon; color: Theme.foreground; rotation: gearIcon.rotation; opacity: gearIcon.opacity; scale: gearIcon.scale }
                }
            }

            Item {
                id: radioBtn
                implicitWidth: radioBtnInner.styledWidth; implicitHeight: radioBtnInner.styledHeight

                property real entranceProgress: 1; property real exitProgress: 1
                opacity: entranceProgress * exitProgress
                property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                layer.enabled: entranceProgress < 1 || exitProgress < 1
                layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(radioBtn.entranceBlur, radioBtn.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                NumberAnimation on entranceProgress { id: radioBtnEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                NumberAnimation on exitProgress { id: radioBtnExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                function playEntrance() { radioBtnExitAnim.stop(); exitProgress = 1; entranceProgress = 0; radioBtnEntranceAnim.restart() }
                function playExit() { radioBtnEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; radioBtnExitAnim.restart() }

                GlassButton {
                    id: radioBtnInner
                    arrangeId: "radio"
                    anchors.fill: parent
                    variant: "toggle"
                    active: Wifi.radioOn
                    text: (Wifi.radioOn ? "\u25cf ON" : "\u25cb OFF")
                    onClicked: { instantColor = true; Wifi.toggleRadio() }

                    scale: radioHover.hovered ? 1.06 : 1.0
                    transformOrigin: Item.Center
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    HoverHandler { id: radioHover }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: 194

            ColumnLayout {
                id: liveSection
                anchors.fill: parent
                spacing: 4
                opacity: root.liveShown ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                property real crossfadeBlur: Math.sin(Math.PI * opacity) * Animations.slideBlurHorizontalLength
                layer.enabled: opacity < 1
                layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: liveSection.crossfadeBlur; samples: Animations.slideBlurSamples; transparentBorder: true }

                Text {
                    id: newNetworksLabel
                    text: "New Networks"
                    color: Theme.foreground
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true

                    property real entranceProgress: 1; property real exitProgress: 1
                    opacity: entranceProgress * exitProgress
                    property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                    property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                    layer.enabled: entranceProgress < 1 || exitProgress < 1
                    layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(newNetworksLabel.entranceBlur, newNetworksLabel.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                    NumberAnimation on entranceProgress { id: newNetworksLabelEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                    NumberAnimation on exitProgress { id: newNetworksLabelExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                    function playEntrance() { newNetworksLabelExitAnim.stop(); exitProgress = 1; entranceProgress = 0; newNetworksLabelEntranceAnim.restart() }
                    function playExit() { newNetworksLabelEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; newNetworksLabelExitAnim.restart() }
                }
                Text {
                    id: statusOverlay
                    Layout.fillWidth: true
                    z: 10
                    text: {
                        if (Wifi.connecting) return "Connecting to " + Wifi.connectingSsid + "\u2026"
                            if (Wifi.authError !== "") return "Authentication Error"
                                return ""
                    }
                    visible: text.length > 0
                    color: (Wifi.authError !== "") ? "#ff6b6b" : Theme.foreground
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2

                    property real shakeX: 0
                    property real entranceProgress: 1; property real exitProgress: 1
                    opacity: entranceProgress * exitProgress
                    property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                    property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                    property real shakeBlur: Math.min(28, Math.abs(shakeX) * 5)
                    transform: Translate { x: statusOverlay.shakeX }

                    layer.enabled: entranceProgress < 1 || exitProgress < 1 || shakeX !== 0
                    layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(statusOverlay.entranceBlur, statusOverlay.exitBlur, statusOverlay.shakeBlur); samples: Animations.slideBlurSamples; transparentBorder: true }

                    NumberAnimation on entranceProgress { id: statusOverlayEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                    NumberAnimation on exitProgress { id: statusOverlayExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                    function playEntrance() { statusOverlayExitAnim.stop(); exitProgress = 1; entranceProgress = 0; statusOverlayEntranceAnim.restart() }
                    function playExit() { statusOverlayEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; statusOverlayExitAnim.restart() }

                    SequentialAnimation {
                        id: statusShakeAnim
                        NumberAnimation { target: statusOverlay; property: "shakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
                        NumberAnimation { target: statusOverlay; property: "shakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
                        NumberAnimation { target: statusOverlay; property: "shakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                        NumberAnimation { target: statusOverlay; property: "shakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                        NumberAnimation { target: statusOverlay; property: "shakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
                    }

                    onVisibleChanged: if (visible) { statusShakeAnim.stop(); statusShakeAnim.start() }
                }


                ScrollView {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    Layout.preferredHeight: 170
                    clip: true

                    ColumnLayout {
                        width: parent.width - 10
                        x: 4; y: 3
                        spacing: 4

                        Text {
                            id: emptyStateText
                            visible: host.newNetworks.length === 0
                            text: Wifi.scanList.length === 0 ? "Scanning\u2026" : "No new networks nearby"
                            color: Theme.foreground
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1

                            property real entranceProgress: 1; property real exitProgress: 1
                            opacity: entranceProgress * exitProgress
                            property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                            property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                            layer.enabled: entranceProgress < 1 || exitProgress < 1
                            layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(emptyStateText.entranceBlur, emptyStateText.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                            NumberAnimation on entranceProgress { id: emptyStateEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                            NumberAnimation on exitProgress { id: emptyStateExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                            function playEntrance() { emptyStateExitAnim.stop(); exitProgress = 1; entranceProgress = 0; emptyStateEntranceAnim.restart() }
                            function playExit() { emptyStateEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; emptyStateExitAnim.restart() }
                        }

                        Repeater {
                            id: newNetworksRepeater
                            model: host.newNetworks

                            delegate: ColumnLayout {
                                id: entry
                                required property var modelData
                                readonly property bool secured: modelData.security !== "Open" && modelData.security !== "none"
                                readonly property bool expanded: host.expandedSsid === modelData.ssid
                                Layout.fillWidth: true
                                spacing: 4

                                property bool hoverSuppressed: false

                                property real entranceProgress: 1; property real exitProgress: 1
                                opacity: entranceProgress * exitProgress
                                property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                                property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                                layer.enabled: entranceProgress < 1 || exitProgress < 1
                                layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(entry.entranceBlur, entry.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                                NumberAnimation on entranceProgress { id: entryEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false; onRunningChanged: if (!running) entry.hoverSuppressed = false }
                                NumberAnimation on exitProgress { id: entryExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                                function playEntrance() { entryExitAnim.stop(); exitProgress = 1; entranceProgress = 0; entry.hoverSuppressed = true; entryEntranceAnim.restart() }
                                function playExit() { entryEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; entryExitAnim.restart() }
                                Component.onCompleted: playEntrance()

                                onExpandedChanged: { if (expanded) { pwField.text = ""; pwField.forceActiveFocus() } else { Wifi.dismissAuthError() } }

                                ScanNewButton {
                                    id: scanBtn
                                    active: entry.expanded
                                    width: 320 - 100
                                    hoverEnabled: !entry.hoverSuppressed
                                    text: entry.modelData.ssid + "  \u00b7  " + entry.modelData.signal + "%" + (entry.secured ? "  \ud83d\udd12" : "")
                                    onClicked: {
                                        if (entry.secured) host.expandedSsid = entry.expanded ? "" : entry.modelData.ssid
                                            else Wifi.connectTo(entry.modelData.ssid)
                                    }

                                    scale: scanBtnHover.hovered ? 1.03 : 1.0
                                    transformOrigin: Item.Center
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    HoverHandler { id: scanBtnHover }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 8
                                    clip: false
                                    implicitHeight: entry.expanded ? pwRow.implicitHeight +5 : 0
                                    Behavior on implicitHeight { NumberAnimation { duration: Animations.accordionDuration; easing.type: Animations.accordionEasing } }

                                    RowLayout {
                                        id: pwRow
                                        width: parent.width
                                        y: 2
                                        spacing: 2
                                        x: -1.1
                                        // Fade + slide down from above on open, back out on close. One progress value drives
                                        // both so they stay in step; ease-out going in, ease-in going out (same easings and
                                        // duration the other slide/blur transitions in this popup use).
                                        property real reveal: entry.expanded ? 1 : 0
                                        Behavior on reveal { NumberAnimation { duration: Animations.accordionDuration; easing.type: entry.expanded ? Animations.slideBlurEasingOut : Animations.slideBlurEasingIn } }
                                        opacity: reveal
                                        transform: Translate { y: Math.round((1 - pwRow.reveal) * -12) }

                                        TextField {
                                            id: pwField
                                            Layout.fillWidth: true
                                            implicitHeight: 27
                                            echoMode: TextInput.Password
                                            placeholderText: "Password"
                                            focus: entry.expanded
                                            color: Theme.foreground
                                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                                            background: Rectangle { radius: Theme.radiusSm; color: "transparent"; border.width: 1; border.color: Theme.borderMuted }
                                            onTextChanged: Wifi.dismissAuthError()
                                            onAccepted: Wifi.connectWithPassword(entry.modelData.ssid, text)
                                        }
                                        GlassButton {
                                            text: "Connect"
                                            implicitHeight: 27
                                            hoverEnabled: !entry.hoverSuppressed
                                            onClicked: Wifi.connectWithPassword(entry.modelData.ssid, pwField.text)

                                            scale: connectHover.hovered ? 1.04 : 1.0
                                            transformOrigin: Item.Center
                                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                            HoverHandler { id: connectHover }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: savedSection
                anchors.fill: parent
                spacing: 4
                opacity: root.liveShown ? 0 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                property real crossfadeBlur: Math.sin(Math.PI * opacity) * Animations.slideBlurHorizontalLength
                layer.enabled: opacity < 1
                layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: savedSection.crossfadeBlur; samples: Animations.slideBlurSamples; transparentBorder: true }

                Text {
                    id: savedNetworksLabel
                    text: "Saved Networks"
                    color: Theme.foreground
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true

                    property real entranceProgress: 1; property real exitProgress: 1
                    opacity: entranceProgress * exitProgress
                    property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                    property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                    layer.enabled: entranceProgress < 1 || exitProgress < 1
                    layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(savedNetworksLabel.entranceBlur, savedNetworksLabel.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                    NumberAnimation on entranceProgress { id: savedNetworksLabelEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                    NumberAnimation on exitProgress { id: savedNetworksLabelExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                    function playEntrance() { savedNetworksLabelExitAnim.stop(); exitProgress = 1; entranceProgress = 0; savedNetworksLabelEntranceAnim.restart() }
                    function playExit() { savedNetworksLabelEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; savedNetworksLabelExitAnim.restart() }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    Layout.preferredHeight: 170
                    clip: true

                    ColumnLayout {
                        width: parent.width - 6
                        x: 4; y: 3
                        spacing: 4

                        Repeater {
                            id: savedRepeater
                            model: host.savedNetworks

                            delegate: RowLayout {
                                id: savedEntry
                                required property var modelData
                                Layout.fillWidth: true
                                width: parent ? parent.width : implicitWidth
                                spacing: 4

                                property bool hoverSuppressed: false

                                property real entranceProgress: 1; property real exitProgress: 1
                                opacity: entranceProgress * exitProgress
                                property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                                property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                                layer.enabled: entranceProgress < 1 || exitProgress < 1
                                layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(savedEntry.entranceBlur, savedEntry.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                                NumberAnimation on entranceProgress { id: savedEntryEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false; onRunningChanged: if (!running) savedEntry.hoverSuppressed = false }
                                NumberAnimation on exitProgress { id: savedEntryExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                                function playEntrance() { savedEntryExitAnim.stop(); exitProgress = 1; entranceProgress = 0; savedEntry.hoverSuppressed = true; savedEntryEntranceAnim.restart() }
                                function playExit() { savedEntryEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; savedEntryExitAnim.restart() }
                                Component.onCompleted: playEntrance()

                                NameEntryButton {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 160
                                    implicitHeight: 36
                                    text: modelData.ssid + (modelData.signal != null ? "  \u00b7  " + modelData.signal + "%" : "")
                                    active: Wifi.ssid === modelData.ssid
                                    inactiveTextColor: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.7)
                                    onClicked: Wifi.forceConnectTo(modelData.ssid)

                                    scale: nameHover.hovered ? 1.02 : 1.0
                                    transformOrigin: Item.Center
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    HoverHandler { id: nameHover }
                                }

                                GlassButton {
                                    implicitHeight: 36; implicitWidth: 34
                                    text: "\u2715"
                                    hoverEnabled: !savedEntry.hoverSuppressed
                                    onClicked: Wifi.disconnect(modelData.ssid)

                                    scale: disconnectHover.hovered ? 1.08 : 1.0
                                    transformOrigin: Item.Center
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    HoverHandler { id: disconnectHover }
                                }

                                GlassButton {
                                    implicitHeight: 36
                                    text: "Forget"
                                    hoverBorderColor: "red"
                                    hoverEnabled: !savedEntry.hoverSuppressed
                                    onClicked: { hoverEnabled = false; forgetHover.enabled = false; instantColor = true; Wifi.forget(modelData.ssid) }

                                    scale: forgetHover.hovered ? 1.04 : 1.0
                                    transformOrigin: Item.Center
                                    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                                    HoverHandler { id: forgetHover; enabled: !savedEntry.hoverSuppressed }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Live download / upload speed, bottom-left. Fed by Wifi.downBps /
        // Wifi.upBps (scripts/wifi-speed.sh, only runs while this popup is open).
        RowLayout {
            id: speedRow
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 14

            property real entranceProgress: 1; property real exitProgress: 1
            opacity: entranceProgress * exitProgress
            property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
            property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
            layer.enabled: entranceProgress < 1 || exitProgress < 1
            layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(speedRow.entranceBlur, speedRow.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
            NumberAnimation on entranceProgress { id: speedRowEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
            NumberAnimation on exitProgress { id: speedRowExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
            function playEntrance() { speedRowExitAnim.stop(); exitProgress = 1; entranceProgress = 0; speedRowEntranceAnim.restart() }
            function playExit() { speedRowEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; speedRowExitAnim.restart() }

            Text {
                // Fixed width so the digits changing never nudge the upload text.
                Layout.preferredWidth: 82
                text: "\u2193 " + Wifi.formatSpeed(Wifi.downBps)
                color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.7)
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
            }
            Text {
                Layout.preferredWidth: 82
                text: "\u2191 " + Wifi.formatSpeed(Wifi.upBps)
                color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.7)
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2
            }
            Item { Layout.fillWidth: true }
        }
    }

    PopupArrange { containers: [contentCol] }
}
