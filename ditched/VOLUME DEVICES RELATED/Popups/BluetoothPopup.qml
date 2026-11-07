import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Qt5Compat.GraphicalEffects
import Quickshell.Wayland
import "../Theme"
import "../Widgets"
import "../Services"

PanelWindow {
    id: popup
    visible: false

    implicitWidth: 300
    implicitHeight: contentCol.implicitHeight + 20

    property var tracking: null

    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:popup:bluetooth"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property real iconCenterOffset: 0
    property real barBottomOffset: 32

    readonly property real horizontalOverhang: 5
    readonly property real verticalGap: 3

    anchors { bottom: true; left: false; right: true }

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
    Behavior on smoothedRightMargin { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }

    margins { bottom: barBottomOffset + verticalGap; right: smoothedRightMargin }
    property bool closing: false

    function toggle() { if (closing) return; if (visible) close(); else visible = true }
    function close() {
        closing = true
        headerTitle.playExit(); gearBtn.playExit(); radioBtn.playExit()
        newDevicesLabel.playExit(); pairedDevicesLabel.playExit(); emptyStateText.playExit()
        pairingStatusOverlay.playExit(); pairStatusOverlay.playExit(); pairConfirmRow.playExit()
        connectedStatusOverlay.playExit()
        pairingStatusOverlay2.playExit(); pairStatusOverlay2.playExit(); pairConfirmRow2.playExit()
        connectedStatusOverlay2.playExit()
        for (let i = 0; i < newDevicesRepeater.count; i++) newDevicesRepeater.itemAt(i).playExit()
            for (let i = 0; i < pairedRepeater.count; i++) pairedRepeater.itemAt(i).playExit()
                closeTimer.restart()
    }

    Timer { id: closeTimer; interval: Animations.slideBlurDuration; onTriggered: { popup.visible = false; popup.closing = false } }

    onVisibleChanged: {
        if (visible) {
            headerTitle.playEntrance(); gearBtn.playEntrance(); radioBtn.playEntrance()
            newDevicesLabel.playEntrance(); pairedDevicesLabel.playEntrance(); emptyStateText.playEntrance()
            pairingStatusOverlay.playEntrance(); pairStatusOverlay.playEntrance(); pairConfirmRow.playEntrance()
            connectedStatusOverlay.playEntrance()
            pairingStatusOverlay2.playEntrance(); pairStatusOverlay2.playEntrance(); pairConfirmRow2.playEntrance()
            connectedStatusOverlay2.playEntrance()
            for (let i = 0; i < newDevicesRepeater.count; i++) newDevicesRepeater.itemAt(i).playEntrance()
                for (let i = 0; i < pairedRepeater.count; i++) pairedRepeater.itemAt(i).playEntrance()
        }
    }

    ClickAwayCloser { targetWindows: [popup]; active: popup.visible; onDismissed: popup.close() }

    property var newDevices: []
    function recomputeNewDevices() {
        const filtered = Bluetooth.scanList.filter(d => !Bluetooth.history.some(h => h.mac === d.mac))
        const oldIds = newDevices.map(d => d.mac)
        const newIds = filtered.map(d => d.mac)
        if (oldIds.join(",") === newIds.join(",")) return

            const removedIds = oldIds.filter(id => !newIds.includes(id))
            if (removedIds.length > 0) {
                removedIds.forEach(id => {
                    const idx = oldIds.indexOf(id)
                    const item = newDevicesRepeater.itemAt(idx)
                    if (item) item.playExit()
                })
                removeTimer.restart()
            } else {
                newDevices = filtered
            }
    }

    Timer {
        id: removeTimer
        interval: Animations.slideBlurDuration
        onTriggered: { const filtered = Bluetooth.scanList.filter(d => !Bluetooth.history.some(h => h.mac === d.mac)); popup.newDevices = filtered }
    }
    Connections {
    target: Bluetooth
    function onScanListChanged() {
        popup.recomputeNewDevices()

    }
    function onHistoryChanged() {
        popup.recomputeNewDevices()

    }
    }
    Component.onCompleted: recomputeNewDevices()

    property string pinDraft: ""
    property bool pairDismissed: false

    GlassPanel {
        anchors.fill: parent

        ColumnLayout {
            id: contentCol
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            RowLayout {
                id: headerRow
                Layout.fillWidth: true
                spacing: 6

                Text {
                    id: headerTitle
                    text: "Bluetooth"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: 13
                    font.bold: true
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
                    implicitWidth: 30
                    implicitHeight: 26

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
                        anchors.fill: parent
                        active: Bluetooth.liveMode
                        onClicked: { instantColor = true; Bluetooth.toggleLiveMode() }

                        scale: gearHover.hovered ? 1.06 : 1.0
                        transformOrigin: Item.Center
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        HoverHandler { id: gearHover }

                        Image { id: gearIcon; anchors.centerIn: parent; source: "file://" + Quickshell.env("HOME") + "/.config/icons/settings.svg"; sourceSize.width: 14; sourceSize.height: 14; width: 14; height: 14; visible: false }

                        ColorOverlay { anchors.fill: gearIcon; source: gearIcon; color: Theme.foreground }
                    }
                }

                Item {
                    id: radioBtn
                    implicitWidth: radioBtnInner.implicitWidth
                    implicitHeight: radioBtnInner.implicitHeight

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
                        anchors.fill: parent
                        variant: "toggle"
                        active: Bluetooth.radioOn
                        text: (Bluetooth.radioOn ? "\u25cf ON" : "\u25cb OFF")
                        onClicked: { instantColor = true; Bluetooth.toggleRadio() }

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
                    opacity: Bluetooth.liveMode ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    property real crossfadeBlur: Math.sin(Math.PI * opacity) * Animations.slideBlurHorizontalLength
                    layer.enabled: opacity < 1
                    layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: liveSection.crossfadeBlur; samples: Animations.slideBlurSamples; transparentBorder: true }

                    Text {
                        id: newDevicesLabel
                        text: "New Devices"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                        Layout.topMargin: -4
                        property real entranceProgress: 1; property real exitProgress: 1
                        opacity: entranceProgress * exitProgress
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        layer.enabled: entranceProgress < 1 || exitProgress < 1
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(newDevicesLabel.entranceBlur, newDevicesLabel.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                        NumberAnimation on entranceProgress { id: newDevicesLabelEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                        NumberAnimation on exitProgress { id: newDevicesLabelExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        function playEntrance() { newDevicesLabelExitAnim.stop(); exitProgress = 1; entranceProgress = 0; newDevicesLabelEntranceAnim.restart() }
                        function playExit() { newDevicesLabelEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; newDevicesLabelExitAnim.restart() }
                    }

                    Text {
                        id: pairingStatusOverlay
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        z: 10
                        text: Bluetooth.pairingMac !== "" ? ((Bluetooth.pairingIncoming ? "Incoming request from " : "Pairing with ") + Bluetooth.pairingName + "\u2026") : ""
                        visible: Bluetooth.pairingMac !== "" && Bluetooth.pendingConfirm === null && Bluetooth.pendingPin === null && Bluetooth.pairError === "" && !popup.pairDismissed
                        color: "#aaaaaa"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        wrapMode: Text.Wrap

                        property real shakeX: 0
                        property real entranceProgress: 1; property real exitProgress: 1
                        opacity: entranceProgress * exitProgress
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        property real shakeBlur: Math.min(28, Math.abs(shakeX) * 5)
                        transform: Translate { x: pairingStatusOverlay.shakeX }
                        layer.enabled: entranceProgress < 1 || exitProgress < 1 || shakeX !== 0
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(pairingStatusOverlay.entranceBlur, pairingStatusOverlay.exitBlur, pairingStatusOverlay.shakeBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                        NumberAnimation on entranceProgress { id: pairingStatusOverlayEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                        NumberAnimation on exitProgress { id: pairingStatusOverlayExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        function playEntrance() { pairingStatusOverlayExitAnim.stop(); exitProgress = 1; entranceProgress = 0; pairingStatusOverlayEntranceAnim.restart() }
                        function playExit() { pairingStatusOverlayEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; pairingStatusOverlayExitAnim.restart() }

                        SequentialAnimation {
                            id: pairingStatusShakeAnim
                            NumberAnimation { target: pairingStatusOverlay; property: "shakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
                            NumberAnimation { target: pairingStatusOverlay; property: "shakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairingStatusOverlay; property: "shakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairingStatusOverlay; property: "shakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairingStatusOverlay; property: "shakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
                        }
                        onVisibleChanged: if (visible) { playEntrance(); pairingStatusShakeAnim.stop(); pairingStatusShakeAnim.start() }
                    }

                    Text {
                        id: pairStatusOverlay
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        z: 10
                        text: { if (Bluetooth.pairError !== "") return Bluetooth.pairError; return "" }
                        visible: text.length > 0
                        color: "#ff6b6b"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        wrapMode: Text.Wrap

                        property real shakeX: 0
                        property real entranceProgress: 1; property real exitProgress: 1
                        opacity: entranceProgress * exitProgress
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        property real shakeBlur: Math.min(28, Math.abs(shakeX) * 5)
                        transform: Translate { x: pairStatusOverlay.shakeX }
                        layer.enabled: entranceProgress < 1 || exitProgress < 1 || shakeX !== 0
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(pairStatusOverlay.entranceBlur, pairStatusOverlay.exitBlur, pairStatusOverlay.shakeBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                        NumberAnimation on entranceProgress { id: pairStatusOverlayEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                        NumberAnimation on exitProgress { id: pairStatusOverlayExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        function playEntrance() { pairStatusOverlayExitAnim.stop(); exitProgress = 1; entranceProgress = 0; pairStatusOverlayEntranceAnim.restart() }
                        function playExit() { pairStatusOverlayEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; pairStatusOverlayExitAnim.restart() }

                        SequentialAnimation {
                            id: pairStatusShakeAnim
                            NumberAnimation { target: pairStatusOverlay; property: "shakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
                            NumberAnimation { target: pairStatusOverlay; property: "shakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairStatusOverlay; property: "shakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairStatusOverlay; property: "shakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairStatusOverlay; property: "shakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
                        }
                        onVisibleChanged: if (visible) { pairStatusShakeAnim.stop(); pairStatusShakeAnim.start() }

                        GlassButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: 22
                            implicitHeight: 22
                            text: "\u2715"
                            onClicked: { instantColor = true; Bluetooth.dismissError(); popup.pairDismissed = true }
                        }
                    }

                    // ---- Success banner: shows for 5s then plays the same exit fade+blur as the other overlays, then clears itself ----
                    Text {
                        id: connectedStatusOverlay
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        z: 10
                        text: Bluetooth.connectedName !== "" ? ("Connected to " + Bluetooth.connectedName) : ""
                        visible: Bluetooth.connectedName !== ""
                        color: "#6bffa0"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        wrapMode: Text.Wrap

                        property real shakeX: 0
                        property real entranceProgress: 1; property real exitProgress: 1
                        opacity: entranceProgress * exitProgress
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        property real shakeBlur: Math.min(28, Math.abs(shakeX) * 5)
                        transform: Translate { x: connectedStatusOverlay.shakeX }
                        layer.enabled: entranceProgress < 1 || exitProgress < 1 || shakeX !== 0
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(connectedStatusOverlay.entranceBlur, connectedStatusOverlay.exitBlur, connectedStatusOverlay.shakeBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                        NumberAnimation on entranceProgress { id: connectedStatusOverlayEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                        NumberAnimation on exitProgress { id: connectedStatusOverlayExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        function playEntrance() { connectedStatusOverlayExitAnim.stop(); exitProgress = 1; entranceProgress = 0; connectedStatusOverlayEntranceAnim.restart() }
                        function playExit() { connectedStatusOverlayEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; connectedStatusOverlayExitAnim.restart() }

                        SequentialAnimation {
                            id: connectedStatusShakeAnim
                            NumberAnimation { target: connectedStatusOverlay; property: "shakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
                            NumberAnimation { target: connectedStatusOverlay; property: "shakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: connectedStatusOverlay; property: "shakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: connectedStatusOverlay; property: "shakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: connectedStatusOverlay; property: "shakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
                        }
                        onVisibleChanged: if (visible) { playEntrance(); connectedStatusShakeAnim.stop(); connectedStatusShakeAnim.start(); connectedHideTimer.restart() }
                    }
                    Timer { id: connectedHideTimer; interval: 5000; onTriggered: { connectedStatusOverlay.playExit(); connectedClearTimer.start() } }
                    Timer { id: connectedClearTimer; interval: Animations.slideBlurDuration; onTriggered: Bluetooth.clearConnected() }

                    // ---- Confirm/Reject row: same non-floating placement, own widget shape ----
                    RowLayout {
                        id: pairConfirmRow
                        Layout.fillWidth: true
                        visible: Bluetooth.pendingConfirm !== null
                        spacing: 8

                        property real entranceProgress: 1; property real exitProgress: 1
                        opacity: entranceProgress * exitProgress
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        layer.enabled: entranceProgress < 1 || exitProgress < 1
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(pairConfirmRow.entranceBlur, pairConfirmRow.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                        NumberAnimation on entranceProgress { id: pairConfirmRowEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                        NumberAnimation on exitProgress { id: pairConfirmRowExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        function playEntrance() { pairConfirmRowExitAnim.stop(); exitProgress = 1; entranceProgress = 0; pairConfirmRowEntranceAnim.restart() }
                        function playExit() { pairConfirmRowEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; pairConfirmRowExitAnim.restart() }
                        onVisibleChanged: if (visible) playEntrance()

                        Text { Layout.fillWidth: true; text: "Confirm " + Bluetooth.pairingName + ": " + (Bluetooth.pendingConfirm ? Bluetooth.pendingConfirm.code : ""); color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2; wrapMode: Text.Wrap }
                        GlassButton {
                            text: "\u2713"
                            implicitWidth: 26
                            implicitHeight: 26
                            onClicked: { instantColor = true; Bluetooth.confirmYes() }
                            scale: confirmHover.hovered ? 1.08 : 1.0
                            transformOrigin: Item.Center
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            HoverHandler { id: confirmHover }
                        }
                        GlassButton {
                            text: "\u2715"
                            implicitWidth: 26
                            implicitHeight: 26
                            hoverBorderColor: "red"
                            onClicked: { instantColor = true; Bluetooth.confirmNo() }
                            scale: rejectHover.hovered ? 1.08 : 1.0
                            transformOrigin: Item.Center
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            HoverHandler { id: rejectHover }
                        }
                    }
                    // ---- PIN entry row: same non-floating placement, own widget shape ----
                    RowLayout {
                        id: pairPinRow
                        Layout.fillWidth: true
                        visible: Bluetooth.pendingPin !== null
                        onVisibleChanged: if (visible) { pinField.text = ""; pinField.forceActiveFocus() }
                        spacing: 4

                        TextField {
                            id: pinField
                            Layout.fillWidth: true
                            implicitHeight: 27
                            placeholderText: "PIN for " + Bluetooth.pairingName
                            focus: Bluetooth.pendingPin !== null
                            onTextChanged: popup.pinDraft = text
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            background: Rectangle { radius: Theme.radiusSm; color: "transparent"; border.width: 1; border.color: Theme.borderMuted }
                            onAccepted: { Bluetooth.submitPin(popup.pinDraft); popup.pinDraft = "" }
                        }
                        GlassButton {
                            text: "Submit"
                            implicitHeight: 27
                            onClicked: { instantColor = true; Bluetooth.submitPin(popup.pinDraft); popup.pinDraft = "" }
                            scale: submitHover.hovered ? 1.04 : 1.0
                            transformOrigin: Item.Center
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            HoverHandler { id: submitHover }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 170
                        clip: true

                        ColumnLayout {
                            width: parent.width - 6
                            x: 3
                            y: 0
                            spacing: 4

                            Text {
                                id: emptyStateText
                                visible: popup.newDevices.length === 0
                                text: Bluetooth.scanList.length === 0 ? "Scanning\u2026" : "No new devices nearby"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 1

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
                                id: newDevicesRepeater
                                model: popup.newDevices

                                delegate: ScanNewButton {
                                    id: entry
                                    Layout.leftMargin: 4
                                    Layout.topMargin: 2
                                    required property var modelData
                                    Layout.fillWidth: true
                                    clip: true
                                    implicitHeight: 36
                                    active: Bluetooth.pairingMac === modelData.mac && (Bluetooth.pendingConfirm !== null || Bluetooth.pendingPin !== null)
                                    text: modelData.name
                                    onClicked: { instantColor = true; popup.pairDismissed = false; Bluetooth.startPair(modelData.mac, modelData.name) }

                                    scale: entryHover.hovered ? 1.03 : 1.0
                                    transformOrigin: Item.Center
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    HoverHandler { id: entryHover }

                                    property real entranceProgress: 1; property real exitProgress: 1
                                    opacity: entranceProgress * exitProgress
                                    property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                                    property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                                    layer.enabled: entranceProgress < 1 || exitProgress < 1
                                    layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(entry.entranceBlur, entry.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                                    NumberAnimation on entranceProgress { id: entryEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                                    NumberAnimation on exitProgress { id: entryExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                                    function playEntrance() { entryExitAnim.stop(); exitProgress = 1; entranceProgress = 0; entryEntranceAnim.restart() }
                                    function playExit() { entryEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; entryExitAnim.restart() }
                                    Component.onCompleted: playEntrance()
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    id: pairedSection
                    anchors.fill: parent
                    spacing: 4
                    opacity: Bluetooth.liveMode ? 0 : 1
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    property real crossfadeBlur: Math.sin(Math.PI * opacity) * Animations.slideBlurHorizontalLength
                    layer.enabled: opacity < 1
                    layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: pairedSection.crossfadeBlur; samples: Animations.slideBlurSamples; transparentBorder: true }

                    Text {
                        id: pairedDevicesLabel
                        text: "Paired Devices"
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true

                        property real entranceProgress: 1; property real exitProgress: 1
                        opacity: entranceProgress * exitProgress
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        layer.enabled: entranceProgress < 1 || exitProgress < 1
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(pairedDevicesLabel.entranceBlur, pairedDevicesLabel.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                        NumberAnimation on entranceProgress { id: pairedDevicesLabelEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                        NumberAnimation on exitProgress { id: pairedDevicesLabelExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        function playEntrance() { pairedDevicesLabelExitAnim.stop(); exitProgress = 1; entranceProgress = 0; pairedDevicesLabelEntranceAnim.restart() }
                        function playExit() { pairedDevicesLabelExitAnim.stop(); entranceProgress = 1; exitProgress = 1; pairedDevicesLabelExitAnim.restart() }
                    }

                    // ---- Duplicated pairing status/confirm/pin blocks (own ids, "2" suffix) so an incoming/outgoing pairing request also shows while the Paired Devices page is the active one. ----
                    Text {
                        id: pairingStatusOverlay2
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        z: 10
                        text: Bluetooth.pairingMac !== "" ? ((Bluetooth.pairingIncoming ? "Incoming request from " : "Pairing with ") + Bluetooth.pairingName + "\u2026") : ""
                        visible: Bluetooth.pairingMac !== "" && Bluetooth.pendingConfirm === null && Bluetooth.pendingPin === null && Bluetooth.pairError === "" && !popup.pairDismissed
                        color: "#aaaaaa"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        wrapMode: Text.Wrap

                        property real shakeX: 0
                        property real entranceProgress: 1; property real exitProgress: 1
                        opacity: entranceProgress * exitProgress
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        property real shakeBlur: Math.min(28, Math.abs(shakeX) * 5)
                        transform: Translate { x: pairingStatusOverlay2.shakeX }
                        layer.enabled: entranceProgress < 1 || exitProgress < 1 || shakeX !== 0
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(pairingStatusOverlay2.entranceBlur, pairingStatusOverlay2.exitBlur, pairingStatusOverlay2.shakeBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                        NumberAnimation on entranceProgress { id: pairingStatusOverlay2EntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                        NumberAnimation on exitProgress { id: pairingStatusOverlay2ExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        function playEntrance() { pairingStatusOverlay2ExitAnim.stop(); exitProgress = 1; entranceProgress = 0; pairingStatusOverlay2EntranceAnim.restart() }
                        function playExit() { pairingStatusOverlay2EntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; pairingStatusOverlay2ExitAnim.restart() }

                        SequentialAnimation {
                            id: pairingStatusShakeAnim2
                            NumberAnimation { target: pairingStatusOverlay2; property: "shakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
                            NumberAnimation { target: pairingStatusOverlay2; property: "shakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairingStatusOverlay2; property: "shakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairingStatusOverlay2; property: "shakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairingStatusOverlay2; property: "shakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
                        }
                        onVisibleChanged: if (visible) { playEntrance(); pairingStatusShakeAnim2.stop(); pairingStatusShakeAnim2.start() }
                    }

                    Text {
                        id: pairStatusOverlay2
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        z: 10
                        text: { if (Bluetooth.pairError !== "") return Bluetooth.pairError; return "" }
                        visible: text.length > 0
                        color: "#ff6b6b"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        wrapMode: Text.Wrap

                        property real shakeX: 0
                        property real entranceProgress: 1; property real exitProgress: 1
                        opacity: entranceProgress * exitProgress
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        property real shakeBlur: Math.min(28, Math.abs(shakeX) * 5)
                        transform: Translate { x: pairStatusOverlay2.shakeX }
                        layer.enabled: entranceProgress < 1 || exitProgress < 1 || shakeX !== 0
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(pairStatusOverlay2.entranceBlur, pairStatusOverlay2.exitBlur, pairStatusOverlay2.shakeBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                        NumberAnimation on entranceProgress { id: pairStatusOverlay2EntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                        NumberAnimation on exitProgress { id: pairStatusOverlay2ExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        function playEntrance() { pairStatusOverlay2ExitAnim.stop(); exitProgress = 1; entranceProgress = 0; pairStatusOverlay2EntranceAnim.restart() }
                        function playExit() { pairStatusOverlay2EntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; pairStatusOverlay2ExitAnim.restart() }

                        SequentialAnimation {
                            id: pairStatusShakeAnim2
                            NumberAnimation { target: pairStatusOverlay2; property: "shakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
                            NumberAnimation { target: pairStatusOverlay2; property: "shakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairStatusOverlay2; property: "shakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairStatusOverlay2; property: "shakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: pairStatusOverlay2; property: "shakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
                        }
                        onVisibleChanged: if (visible) { pairStatusShakeAnim2.stop(); pairStatusShakeAnim2.start() }

                        GlassButton {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: 22
                            implicitHeight: 22
                            text: "\u2715"
                            onClicked: { instantColor = true; Bluetooth.dismissError(); popup.pairDismissed = true }
                        }
                    }

                    RowLayout {
                        id: pairConfirmRow2
                        Layout.fillWidth: true
                        visible: Bluetooth.pendingConfirm !== null
                        spacing: 8

                        property real entranceProgress: 1; property real exitProgress: 1
                        opacity: entranceProgress * exitProgress
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        layer.enabled: entranceProgress < 1 || exitProgress < 1
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(pairConfirmRow2.entranceBlur, pairConfirmRow2.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                        NumberAnimation on entranceProgress { id: pairConfirmRow2EntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                        NumberAnimation on exitProgress { id: pairConfirmRow2ExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        function playEntrance() { pairConfirmRow2ExitAnim.stop(); exitProgress = 1; entranceProgress = 0; pairConfirmRow2EntranceAnim.restart() }
                        function playExit() { pairConfirmRow2EntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; pairConfirmRow2ExitAnim.restart() }
                        onVisibleChanged: if (visible) playEntrance()

                        Text { Layout.fillWidth: true; text: "Confirm " + Bluetooth.pairingName + ": " + (Bluetooth.pendingConfirm ? Bluetooth.pendingConfirm.code : ""); color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 2; wrapMode: Text.Wrap }
                        GlassButton {
                            text: "\u2713"
                            implicitWidth: 26
                            implicitHeight: 26
                            onClicked: { instantColor = true; Bluetooth.confirmYes() }
                            scale: confirmHover2.hovered ? 1.08 : 1.0
                            transformOrigin: Item.Center
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            HoverHandler { id: confirmHover2 }
                        }
                        GlassButton {
                            text: "\u2715"
                            implicitWidth: 26
                            implicitHeight: 26
                            hoverBorderColor: "red"
                            onClicked: { instantColor = true; Bluetooth.confirmNo() }
                            scale: rejectHover2.hovered ? 1.08 : 1.0
                            transformOrigin: Item.Center
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            HoverHandler { id: rejectHover2 }
                        }
                    }
                    // ---- Success banner (paired-section duplicate) — sibling, not nested in the PIN row ----
                    Text {
                        id: connectedStatusOverlay2
                        Layout.fillWidth: true
                        Layout.bottomMargin: 4
                        z: 10
                        text: Bluetooth.connectedName !== "" ? ("Connected to " + Bluetooth.connectedName) : ""
                        visible: Bluetooth.connectedName !== ""
                        color: "#6bffa0"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                        wrapMode: Text.Wrap

                        property real shakeX: 0
                        property real entranceProgress: 1; property real exitProgress: 1
                        opacity: entranceProgress * exitProgress
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        property real shakeBlur: Math.min(28, Math.abs(shakeX) * 5)
                        transform: Translate { x: connectedStatusOverlay2.shakeX }
                        layer.enabled: entranceProgress < 1 || exitProgress < 1 || shakeX !== 0
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(connectedStatusOverlay2.entranceBlur, connectedStatusOverlay2.exitBlur, connectedStatusOverlay2.shakeBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                        NumberAnimation on entranceProgress { id: connectedStatusOverlay2EntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                        NumberAnimation on exitProgress { id: connectedStatusOverlay2ExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        function playEntrance() { connectedStatusOverlay2ExitAnim.stop(); exitProgress = 1; entranceProgress = 0; connectedStatusOverlay2EntranceAnim.restart() }
                        function playExit() { connectedStatusOverlay2EntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; connectedStatusOverlay2ExitAnim.restart() }

                        SequentialAnimation {
                            id: connectedStatusShakeAnim2
                            NumberAnimation { target: connectedStatusOverlay2; property: "shakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
                            NumberAnimation { target: connectedStatusOverlay2; property: "shakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: connectedStatusOverlay2; property: "shakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: connectedStatusOverlay2; property: "shakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                            NumberAnimation { target: connectedStatusOverlay2; property: "shakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
                        }
                        onVisibleChanged: if (visible) { playEntrance(); connectedStatusShakeAnim2.stop(); connectedStatusShakeAnim2.start(); connectedHideTimer2.restart() }
                    }
                    Timer { id: connectedHideTimer2; interval: 5000; onTriggered: { connectedStatusOverlay2.playExit(); connectedClearTimer2.start() } }
                    Timer { id: connectedClearTimer2; interval: Animations.slideBlurDuration; onTriggered: Bluetooth.clearConnected() }

                    RowLayout {
                        id: pairPinRow2
                        Layout.fillWidth: true
                        visible: Bluetooth.pendingPin !== null
                        onVisibleChanged: if (visible) { pinField2.text = ""; pinField2.forceActiveFocus() }
                        spacing: 4

                        TextField {
                            id: pinField2
                            Layout.fillWidth: true
                            implicitHeight: 27
                            placeholderText: "PIN for " + Bluetooth.pairingName
                            focus: Bluetooth.pendingPin !== null
                            onTextChanged: popup.pinDraft = text
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            background: Rectangle { radius: Theme.radiusSm; color: "transparent"; border.width: 1; border.color: Theme.borderMuted }
                            onAccepted: { Bluetooth.submitPin(popup.pinDraft); popup.pinDraft = "" }
                        }
                        GlassButton {
                            text: "Submit"
                            implicitHeight: 27
                            onClicked: { instantColor = true; Bluetooth.submitPin(popup.pinDraft); popup.pinDraft = "" }
                            scale: submitHover2.hovered ? 1.04 : 1.0
                            transformOrigin: Item.Center
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                            HoverHandler { id: submitHover2 }
                        }
                    }

                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 170
                        clip: true

                        ColumnLayout {
                            width: parent.width - 6
                            x: 3
                            y: 3
                            spacing: 4

                            Repeater {
                                id: pairedRepeater
                                model: Bluetooth.history

                                delegate: RowLayout {
                                    id: pairedEntry
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 4

                                    property real entranceProgress: 1; property real exitProgress: 1
                                    opacity: entranceProgress * exitProgress
                                    property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                                    property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                                    layer.enabled: entranceProgress < 1 || exitProgress < 1
                                    layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(pairedEntry.entranceBlur, pairedEntry.exitBlur); samples: Animations.slideBlurSamples; transparentBorder: true }
                                    NumberAnimation on entranceProgress { id: pairedEntryEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false }
                                    NumberAnimation on exitProgress { id: pairedEntryExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                                    function playEntrance() { pairedEntryExitAnim.stop(); exitProgress = 1; entranceProgress = 0; pairedEntryEntranceAnim.restart() }
                                    function playExit() { pairedEntryExitAnim.stop(); entranceProgress = 1; exitProgress = 1; pairedEntryExitAnim.restart() }
                                    Component.onCompleted: playEntrance()

                                    NameEntryButton {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 40
                                        implicitHeight: 36
                                        text: modelData.name
                                        active: Bluetooth.connectedMacs.includes(modelData.mac)
                                        inactiveTextColor: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.7)
                                        onClicked: Bluetooth.connectTo(modelData.mac)

                                        scale: nameHover.hovered ? 1.02 : 1.0
                                        transformOrigin: Item.Center
                                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        HoverHandler { id: nameHover }
                                    }

                                    GlassButton {
                                        implicitHeight: 36
                                        implicitWidth: 34
                                        text: "\u2715"
                                        onClicked: { instantColor = true; Bluetooth.disconnect(modelData.mac) }

                                        scale: disconnectHover.hovered ? 1.08 : 1.0
                                        transformOrigin: Item.Center
                                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        HoverHandler { id: disconnectHover }
                                    }

                                    GlassButton {
                                        implicitHeight: 36
                                        text: "Forget"
                                        hoverBorderColor: "red"
                                        onClicked: { instantColor = true; Bluetooth.forget(modelData.mac) }

                                        scale: forgetHover.hovered ? 1.04 : 1.0
                                        transformOrigin: Item.Center
                                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                        HoverHandler { id: forgetHover }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
