import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import "../Theme"
import "../Widgets"
import "../Services"

ColumnLayout {
    id: wifiDetail
    signal back()
    spacing: 6

    property string expandedSsid: ""

    onVisibleChanged: { if (visible) { entranceAnimation.restart(); Wifi.popupOpen = true } else { Wifi.popupOpen = false } }

    function handleBack() { wifiDetail.expandedSsid = ""; wifiDetail.back() }

    property bool liveMode: Wifi.liveMode
    onLiveModeChanged: entranceAnimation.restart()

    property real entranceX: 0
    property real shakeX: 0
    transform: Translate { x: wifiDetail.entranceX + wifiDetail.shakeX }

    layer.enabled: wifiDetail.shakeX !== 0 || wifiDetail.entranceX !== 0
    layer.effect: DirectionalBlur { angle: 0; length: Math.min(14, Math.abs(wifiDetail.shakeX) * 4 + Math.abs(wifiDetail.entranceX) * 0.5); samples: 20 }

    ParallelAnimation {
        id: entranceAnimation
        NumberAnimation { target: wifiDetail; property: "entranceX"; from: 16; to: 0; duration: Animations.scaleDuration(170); easing.type: Easing.OutCubic }
        SequentialAnimation {
            PropertyAction { target: wifiDetail; property: "shakeX"; value: 3 }
            PauseAnimation { duration: Animations.scaleDuration(30) }
            PropertyAction { target: wifiDetail; property: "shakeX"; value: -8 }
            PauseAnimation { duration: Animations.scaleDuration(30) }
            PropertyAction { target: wifiDetail; property: "shakeX"; value: 5 }
            PauseAnimation { duration: Animations.scaleDuration(25) }
            PropertyAction { target: wifiDetail; property: "shakeX"; value: -6 }
            PauseAnimation { duration: Animations.scaleDuration(25) }
            PropertyAction { target: wifiDetail; property: "shakeX"; value: 3 }
            PauseAnimation { duration: Animations.scaleDuration(20) }
            PropertyAction { target: wifiDetail; property: "shakeX"; value: -3 }
            PauseAnimation { duration: Animations.scaleDuration(18) }
            PropertyAction { target: wifiDetail; property: "shakeX"; value: 0 }
        }
    }

    property var newNetworks: []
    property var savedNetworks: []

    function recomputeNewNetworks() {
        const filtered = Wifi.scanList.filter(n => !Wifi.history.some(h => h.ssid === n.ssid))
        if (wifiDetail.expandedSsid !== "") { if (filtered.some(n => n.ssid === wifiDetail.expandedSsid)) return }
        const oldIds = newNetworks.map(n => n.ssid); const newIds = filtered.map(n => n.ssid)
        const sameSet = oldIds.length === newIds.length && oldIds.every(id => newIds.includes(id))
        if (sameSet) { newNetworks = filtered; return }
        const removedIds = oldIds.filter(id => !newIds.includes(id))
        if (removedIds.length > 0) {
            removedIds.forEach(id => { const idx = oldIds.indexOf(id); const item = newNetworksRepeater.itemAt(idx); if (item) item.playExit() })
            newNetRemoveTimer.restart()
        } else { newNetworks = filtered }
    }

    function recomputeSaved() {
        const oldIds = savedNetworks.map(n => n.ssid); const newIds = Wifi.history.map(n => n.ssid)
        if (oldIds.join(",") === newIds.join(",")) return
            const removedIds = oldIds.filter(id => !newIds.includes(id))
            if (removedIds.length > 0) {
                removedIds.forEach(id => { const idx = oldIds.indexOf(id); const item = savedRepeater.itemAt(idx); if (item) item.playExit() })
                savedRemoveTimer.restart()
            } else { savedNetworks = Wifi.history }
    }

    Timer { id: newNetRemoveTimer; interval: Animations.slideBlurDuration; onTriggered: wifiDetail.newNetworks = Wifi.scanList.filter(n => !Wifi.history.some(h => h.ssid === n.ssid)) }
    Timer { id: savedRemoveTimer; interval: Animations.slideBlurDuration; onTriggered: wifiDetail.savedNetworks = Wifi.history }

    Connections {
        target: Wifi
        function onScanListChanged() { wifiDetail.recomputeNewNetworks() }
        function onHistoryChanged() { wifiDetail.recomputeNewNetworks(); wifiDetail.recomputeSaved() }
    }

    Component.onCompleted: { recomputeNewNetworks(); recomputeSaved() }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        GlassButton { text: "\u2190"; implicitWidth: 30; implicitHeight: 26; onClicked: wifiDetail.handleBack(); Layout.leftMargin: 3 }

        Text { text: "Wi-Fi"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13); font.bold: true; Layout.fillWidth: true }

        GlassButton {
            id: settingsButton
            implicitWidth: 30; implicitHeight: 26
            active: Wifi.liveMode
            onClicked: Wifi.toggleLiveMode()
            onActiveChanged: settingsIcon.rotation = active ? 90 : 0

            Image {
                id: settingsIcon
                anchors.centerIn: parent
                source: "file://" + Quickshell.env("HOME") + "/.config/icons/settings.svg"
                sourceSize.width: 14; sourceSize.height: 14
                width: 14; height: 14
                opacity: settingsButton.active ? 1.0 : 0.85
                scale: settingsButton.active ? 1.1 : 1.0
                visible: false
                Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            ColorOverlay { anchors.fill: settingsIcon; source: settingsIcon; color: Theme.foreground; rotation: settingsIcon.rotation; opacity: settingsIcon.opacity; scale: settingsIcon.scale }
        }

        GlassButton { variant: "toggle"; Layout.rightMargin: 3; active: Wifi.radioOn; text: Wifi.radioOn ? "\u25cf ON" : "\u25cb OFF"; onClicked: Wifi.toggleRadio() }
    }

    Item {
        Layout.fillWidth: true
        implicitHeight: 194
        visible: Wifi.liveMode

        ColumnLayout {
            anchors.fill: parent
            spacing: 4

            Text { text: "New Networks"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true; Layout.topMargin: -20 }

            Text {
                id: statusOverlay
                Layout.fillWidth: true
                z: 10
                text: { if (Wifi.connecting) return "Connecting to " + Wifi.connectingSsid + "\u2026"; if (Wifi.authError !== "") return "Authentication Error"; return "" }
                visible: text.length > 0
                color: (Wifi.authError !== "") ? "#ff6b6b" : Theme.foreground
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1

                property real shakeX: 0
                transform: Translate { x: statusOverlay.shakeX }
                layer.enabled: statusOverlay.shakeX !== 0
                layer.effect: DirectionalBlur { angle: 0; length: Math.min(28, Math.abs(statusOverlay.shakeX) * 5); samples: 21 }

                SequentialAnimation {
                    id: statusShakeAnim
                    NumberAnimation { target: statusOverlay; property: "shakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
                    NumberAnimation { target: statusOverlay; property: "shakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
                    NumberAnimation { target: statusOverlay; property: "shakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                    NumberAnimation { target: statusOverlay; property: "shakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                    NumberAnimation { target: statusOverlay; property: "shakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
                }

                onVisibleChanged: if (visible) { statusShakeAnim.stop(); statusShakeAnim.start() }
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

            Text {
                Layout.fillWidth: true
                visible: wifiDetail.newNetworks.length === 0
                text: Wifi.scanList.length === 0 ? "Scanning\u2026" : "No new networks nearby"
                color: Theme.foreground
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 6
                clip: true

                ColumnLayout {
                    width: parent.width
                    y: 3; x: 3
                    spacing: 4

                    Repeater {
                        id: newNetworksRepeater
                        model: wifiDetail.newNetworks
                        delegate: ColumnLayout {
                            id: entry
                            required property var modelData
                            readonly property bool secured: modelData.security !== "Open" && modelData.security !== "none"
                            readonly property bool expanded: wifiDetail.expandedSsid === modelData.ssid
                            Layout.fillWidth: true
                            spacing: 4
                            property bool hoverSuppressed: false
                            property real entranceProgress: 1; property real exitProgress: 1; property real itemShakeX: 0
                            opacity: entranceProgress * exitProgress
                            scale: 0.85 + 0.15 * Math.min(entranceProgress, exitProgress)
                            property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                            property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                            transform: Translate { x: entry.itemShakeX }
                            layer.enabled: entranceProgress < 1 || exitProgress < 1 || entry.itemShakeX !== 0
                            layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(entry.entranceBlur, entry.exitBlur, Math.abs(entry.itemShakeX) * 3); samples: Animations.slideBlurSamples; transparentBorder: true }
                            NumberAnimation on entranceProgress { id: entryEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false; onRunningChanged: if (!running) entry.hoverSuppressed = false }
                            NumberAnimation on exitProgress { id: entryExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                            SequentialAnimation {
                                id: entryShakeAnim
                                PropertyAction { target: entry; property: "itemShakeX"; value: 2 }
                                PauseAnimation { duration: Animations.scaleDuration(30) }
                                PropertyAction { target: entry; property: "itemShakeX"; value: -5 }
                                PauseAnimation { duration: Animations.scaleDuration(30) }
                                PropertyAction { target: entry; property: "itemShakeX"; value: 3 }
                                PauseAnimation { duration: Animations.scaleDuration(25) }
                                PropertyAction { target: entry; property: "itemShakeX"; value: -4 }
                                PauseAnimation { duration: Animations.scaleDuration(25) }
                                PropertyAction { target: entry; property: "itemShakeX"; value: 2 }
                                PauseAnimation { duration: Animations.scaleDuration(20) }
                                PropertyAction { target: entry; property: "itemShakeX"; value: -2 }
                                PauseAnimation { duration: Animations.scaleDuration(18) }
                                PropertyAction { target: entry; property: "itemShakeX"; value: 0 }
                            }
                            function playEntrance() { entryExitAnim.stop(); exitProgress = 1; entranceProgress = 0; entry.hoverSuppressed = true; entryEntranceAnim.restart(); entryShakeAnim.restart() }
                            function playExit() { entryEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; entryExitAnim.restart() }
                            Component.onCompleted: playEntrance()
                            onExpandedChanged: if (expanded) { pwField.text = ""; pwField.forceActiveFocus() }

                            ScanEntryButton {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 3
                                Layout.fillWidth: true
                                implicitHeight: 36
                                active: entry.expanded
                                hoverEnabled: !entry.hoverSuppressed
                                text: (entry.modelData.ssid || entry.modelData.name || entry.modelData.SSID || JSON.stringify(entry.modelData)) + "  \u00b7  " + (entry.modelData.signal ?? entry.modelData.strength ?? entry.modelData.rssi ?? "?") + "%" + (entry.secured ? "  \ud83d\udd12" : "")
                                onClicked: { if (entry.secured) wifiDetail.expandedSsid = entry.expanded ? "" : entry.modelData.ssid; else Wifi.connectTo(entry.modelData.ssid) }
                                scale: hovered ? 1.02 : 1.0
                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                clip: false
                                implicitHeight: entry.expanded ? pwRow.implicitHeight : 0
                                Behavior on implicitHeight { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                RowLayout {
                                    id: pwRow
                                    width: parent.width
                                    height: 12
                                    spacing: 6
                                    opacity: entry.expanded ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: 140 } }
                                    Layout.leftMargin: 3
                                    Layout.bottomMargin: 0

                                    TextField {
                                        id: pwField
                                        Layout.preferredWidth: pwRow.width * 0.72
                                        implicitHeight: 30
                                        echoMode: TextInput.Password
                                        placeholderText: "Password"
                                        focus: entry.expanded
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize - 1
                                        background: Rectangle { radius: Theme.radiusSm; color: "transparent"; border.width: 1; border.color: Theme.borderMuted }
                                        onAccepted: { Wifi.connectWithPassword(entry.modelData.ssid, text); wifiDetail.expandedSsid = "" }
                                    }
                                    GlassButton {
                                        text: "Connect"
                                        implicitHeight: 27
                                        Layout.rightMargin: 1
                                        Layout.bottomMargin: 0
                                        hoverEnabled: !entry.hoverSuppressed
                                        onClicked: { Wifi.connectWithPassword(entry.modelData.ssid, pwField.text); wifiDetail.expandedSsid = "" }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        visible: !Wifi.liveMode

       Text { text: "Saved Networks"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true; Layout.topMargin: -20 }

        ScrollView {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.preferredHeight: 170
            clip: true

            ColumnLayout {
                width: parent.width
                y: 3; x: 2
                spacing: 4

                Repeater {
                    id: savedRepeater
                    model: wifiDetail.savedNetworks

                    delegate: RowLayout {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4

                        property bool hoverSuppressed: false

                        property real entranceProgress: 1; property real exitProgress: 1; property real itemShakeX: 0
                        opacity: entranceProgress * exitProgress
                        scale: 0.85 + 0.15 * Math.min(entranceProgress, exitProgress)
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        transform: Translate { x: row.itemShakeX }
                        layer.enabled: entranceProgress < 1 || exitProgress < 1 || row.itemShakeX !== 0
                        layer.effect: DirectionalBlur { angle: Animations.slideBlurHorizontalAngle; length: Math.max(row.entranceBlur, row.exitBlur, Math.abs(row.itemShakeX) * 3); samples: Animations.slideBlurSamples; transparentBorder: true }

                        NumberAnimation on entranceProgress { id: rowEntranceAnim; from: 0; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut; running: false; onRunningChanged: if (!running) row.hoverSuppressed = false }
                        NumberAnimation on exitProgress { id: rowExitAnim; from: 1; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingIn; running: false }
                        SequentialAnimation {
                            id: rowShakeAnim
                            PropertyAction { target: row; property: "itemShakeX"; value: 2 }
                            PauseAnimation { duration: Animations.scaleDuration(30) }
                            PropertyAction { target: row; property: "itemShakeX"; value: -5 }
                            PauseAnimation { duration: Animations.scaleDuration(30) }
                            PropertyAction { target: row; property: "itemShakeX"; value: 3 }
                            PauseAnimation { duration: Animations.scaleDuration(25) }
                            PropertyAction { target: row; property: "itemShakeX"; value: -4 }
                            PauseAnimation { duration: Animations.scaleDuration(25) }
                            PropertyAction { target: row; property: "itemShakeX"; value: 2 }
                            PauseAnimation { duration: Animations.scaleDuration(20) }
                            PropertyAction { target: row; property: "itemShakeX"; value: -2 }
                            PauseAnimation { duration: Animations.scaleDuration(18) }
                            PropertyAction { target: row; property: "itemShakeX"; value: 0 }
                        }
                        function playEntrance() { rowExitAnim.stop(); exitProgress = 1; entranceProgress = 0; row.hoverSuppressed = true; rowEntranceAnim.restart(); rowShakeAnim.restart() }
                        function playExit() { rowEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; rowExitAnim.restart() }
                        Component.onCompleted: playEntrance()

                        NameNewButton {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 160
                            implicitHeight: 36
                            text: row.modelData.ssid
                            active: Wifi.ssid === row.modelData.ssid
                            inactiveTextColor: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.7)
                            onClicked: Wifi.connectTo(row.modelData.ssid)
                            scale: hovered ? 1.02 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                        }

                        GlassButton { implicitHeight: 36; implicitWidth: 34; text: "\u2715"; hoverEnabled: !row.hoverSuppressed; onClicked: Wifi.disconnect(row.modelData.ssid) }

                        GlassButton {
                            implicitHeight: 36
                            text: "Forget"
                            hoverBorderColor: "red"
                            hoverEnabled: !row.hoverSuppressed
                            onClicked: { hoverEnabled = false; Wifi.forget(row.modelData.ssid) }
                        }
                    }
                }
            }
        }
    }
}
