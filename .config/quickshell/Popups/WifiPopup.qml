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
    readonly property real uiScale: PopupSettings.scaleOf("wifi")
    visible: false

    implicitWidth: (300 + PopupSettings.sizeW("wifi")) * uiScale
    implicitHeight: (body.contentCol.implicitHeight + 20 + PopupSettings.sizeH("wifi")) * uiScale

    property var tracking: null

    color: "transparent"
    exclusiveZone: 0

    WlrLayershell.namespace: "quickshell:popup:wifi"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property real iconCenterOffset: 0
    property real barBottomOffset: 32

    readonly property real horizontalOverhang: 5
    readonly property real verticalGap: 3

    anchors { bottom: true; right: true }
    readonly property real effectiveRightMargin: {
        var screenW = popup.screen ? popup.screen.width : implicitWidth
        var desired = iconCenterOffset - implicitWidth / 2
        if (!popup.tracking) { var maxRight = Math.max(0, screenW - implicitWidth); return Math.min(Math.max(0, desired), maxRight) }
        var minRightMargin = screenW - (popup.tracking.barRightEdge + horizontalOverhang)
        var maxRightMargin = screenW - implicitWidth - popup.tracking.barLeftEdge + horizontalOverhang
        var lo = Math.min(minRightMargin, maxRightMargin); var hi = Math.max(minRightMargin, maxRightMargin)
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
        body.newNetworksLabel.playExit(); body.savedNetworksLabel.playExit(); body.emptyStateText.playExit()
        body.statusOverlay.playExit(); body.speedRow.playExit()
        for (let i = 0; i < body.newNetworksRepeater.count; i++) body.newNetworksRepeater.itemAt(i).playExit()
            for (let i = 0; i < body.savedRepeater.count; i++) body.savedRepeater.itemAt(i).playExit()
                closeTimer.restart()
    }

    Timer { id: closeTimer; interval: Animations.slideBlurDuration; onTriggered: { popup.visible = false; popup.closing = false } }

    onVisibleChanged: {
        if (visible) {
            Wifi.popupOpen = true
            body.headerTitle.playEntrance(); body.gearBtn.playEntrance(); body.radioBtn.playEntrance()
            body.newNetworksLabel.playEntrance(); body.savedNetworksLabel.playEntrance(); body.emptyStateText.playEntrance()
            body.statusOverlay.playEntrance(); body.speedRow.playEntrance()
            for (let i = 0; i < body.newNetworksRepeater.count; i++) body.newNetworksRepeater.itemAt(i).playEntrance()
                for (let i = 0; i < body.savedRepeater.count; i++) body.savedRepeater.itemAt(i).playEntrance()
        } else {
            Wifi.popupOpen = false; expandedSsid = ""; Wifi.dismissAuthError()
        }
    }

    ClickAwayCloser { targetWindows: [popup]; active: popup.visible; onDismissed: popup.close() }

    property var newNetworks: []

    function recomputeNewNetworks() {
        const filtered = Wifi.scanList.filter(n => n && n.ssid && !Wifi.history.some(h => h.ssid === n.ssid))
        const oldIds = newNetworks.map(n => n.ssid); const newIds = filtered.map(n => n.ssid)
        const sameSet = oldIds.length === newIds.length && oldIds.every(id => newIds.includes(id))
        if (sameSet) { if (popup.expandedSsid === "") newNetworks = filtered; return }
        const removedIds = oldIds.filter(id => !newIds.includes(id))
        if (removedIds.length > 0) {
            removedIds.forEach(id => { const idx = oldIds.indexOf(id); const item = body.newNetworksRepeater.itemAt(idx); if (item) item.playExit() })
            removeTimer.restart()
        } else { newNetworks = filtered }
    }
    Timer {
        id: removeTimer
        interval: Animations.slideBlurDuration
        onTriggered: { const filtered = Wifi.scanList.filter(n => n && n.ssid && !Wifi.history.some(h => h.ssid === n.ssid)); popup.newNetworks = filtered }
    }

    property var savedNetworks: []

    function recomputeSaved() {
        const oldIds = savedNetworks.map(n => n.ssid); const newIds = Wifi.history.map(n => n.ssid)
        if (oldIds.join(",") === newIds.join(",")) { savedNetworks = Wifi.history; return }
        const removedIds = oldIds.filter(id => !newIds.includes(id))
        if (removedIds.length > 0) {
            removedIds.forEach(id => { const idx = oldIds.indexOf(id); const item = body.savedRepeater.itemAt(idx); if (item) item.playExit() })
            savedRemoveTimer.restart()
        } else { savedNetworks = Wifi.history }
    }

    Timer { id: savedRemoveTimer; interval: Animations.slideBlurDuration; onTriggered: popup.savedNetworks = Wifi.history }

    Connections {
        target: Wifi
        function onScanListChanged() { popup.recomputeNewNetworks() }
        function onHistoryChanged() { popup.recomputeNewNetworks(); popup.recomputeSaved() }
    }
    Component.onCompleted: { recomputeNewNetworks(); recomputeSaved() }

    property string expandedSsid: ""

    PopupScale {
        anchors.fill: parent
        popupId: "wifi"

        GlassPanel {
            anchors.fill: parent
            radius: PopupSettings.radiusOf("wifi")
            tracking: popup.tracking

            WifiContent {
                id: body
                anchors.fill: parent
                host: popup
            }

        }
    }
}
