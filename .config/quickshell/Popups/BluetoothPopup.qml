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
    readonly property real uiScale: PopupSettings.scaleOf("bluetooth")
    visible: false

    implicitWidth: (300 + PopupSettings.sizeW("bluetooth")) * uiScale
    implicitHeight: (body.contentCol.implicitHeight + 20 + PopupSettings.sizeH("bluetooth")) * uiScale

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
        body.headerTitle.playExit(); body.gearBtn.playExit(); body.radioBtn.playExit()
        body.newDevicesLabel.playExit(); body.pairedDevicesLabel.playExit(); body.emptyStateText.playExit()
        body.pairingStatusOverlay.playExit(); body.pairStatusOverlay.playExit(); body.pairConfirmRow.playExit()
        body.connectedStatusOverlay.playExit()
        body.pairingStatusOverlay2.playExit(); body.pairStatusOverlay2.playExit(); body.pairConfirmRow2.playExit()
        body.connectedStatusOverlay2.playExit()
        for (let i = 0; i < body.newDevicesRepeater.count; i++) body.newDevicesRepeater.itemAt(i).playExit()
            for (let i = 0; i < body.pairedRepeater.count; i++) body.pairedRepeater.itemAt(i).playExit()
                closeTimer.restart()
    }

    Timer { id: closeTimer; interval: Animations.slideBlurDuration; onTriggered: { popup.visible = false; popup.closing = false } }

    onVisibleChanged: {
        Bluetooth.popupOpen = visible
        if (visible) {
            body.headerTitle.playEntrance(); body.gearBtn.playEntrance(); body.radioBtn.playEntrance()
            body.newDevicesLabel.playEntrance(); body.pairedDevicesLabel.playEntrance(); body.emptyStateText.playEntrance()
            body.pairingStatusOverlay.playEntrance(); body.pairStatusOverlay.playEntrance(); body.pairConfirmRow.playEntrance()
            body.connectedStatusOverlay.playEntrance()
            body.pairingStatusOverlay2.playEntrance(); body.pairStatusOverlay2.playEntrance(); body.pairConfirmRow2.playEntrance()
            body.connectedStatusOverlay2.playEntrance()
            for (let i = 0; i < body.newDevicesRepeater.count; i++) body.newDevicesRepeater.itemAt(i).playEntrance()
                for (let i = 0; i < body.pairedRepeater.count; i++) body.pairedRepeater.itemAt(i).playEntrance()
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
                    const item = body.newDevicesRepeater.itemAt(idx)
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

    PopupScale {
        anchors.fill: parent
        popupId: "bluetooth"

        GlassPanel {
            anchors.fill: parent
            radius: PopupSettings.radiusOf("bluetooth")
            tracking: popup.tracking

            BluetoothContent {
                id: body
                anchors.fill: parent
                host: popup
            }

        }
    }
}
