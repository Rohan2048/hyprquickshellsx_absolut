import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import "../Theme"
import "../Widgets"
import "../Services"

ColumnLayout {
    id: btDetail
    signal back()
    spacing: 6

    property string pinDraft: ""

    onVisibleChanged: {
        Bluetooth.popupOpen = visible
        if (visible) {
            entranceAnimation.restart()
        }
    }

    function handleBack() {
        btDetail.back()
    }

    property bool liveMode: Bluetooth.liveMode
    onLiveModeChanged: {
        entranceAnimation.restart()
    }

    property real entranceX: 0
    property real shakeX: 0
    transform: Translate { x: btDetail.entranceX + btDetail.shakeX }

    layer.enabled: btDetail.shakeX !== 0 || btDetail.entranceX !== 0
    layer.effect: DirectionalBlur {
        angle: 0
        length: Math.min(14, Math.abs(btDetail.shakeX) * 4 + Math.abs(btDetail.entranceX) * 0.5)
        samples: 20
    }

    ParallelAnimation {
        id: entranceAnimation
        NumberAnimation {
            target: btDetail; property: "entranceX"
            from: 16; to: 0
            duration: Animations.scaleDuration(170)
            easing.type: Easing.OutCubic
        }
        SequentialAnimation {
            PropertyAction { target: btDetail; property: "shakeX"; value: 3 }
            PauseAnimation { duration: Animations.scaleDuration(30) }
            PropertyAction { target: btDetail; property: "shakeX"; value: -8 }
            PauseAnimation { duration: Animations.scaleDuration(30) }
            PropertyAction { target: btDetail; property: "shakeX"; value: 5 }
            PauseAnimation { duration: Animations.scaleDuration(25) }
            PropertyAction { target: btDetail; property: "shakeX"; value: -6 }
            PauseAnimation { duration: Animations.scaleDuration(25) }
            PropertyAction { target: btDetail; property: "shakeX"; value: 3 }
            PauseAnimation { duration: Animations.scaleDuration(20) }
            PropertyAction { target: btDetail; property: "shakeX"; value: -3 }
            PauseAnimation { duration: Animations.scaleDuration(18) }
            PropertyAction { target: btDetail; property: "shakeX"; value: 0 }
        }
    }

    // ---- Diff-tracked device lists (drives per-item entrance/exit) ----
    property var newDevices: []
    property var pairedDevices: []

    function recomputeNewDevices() {
        const filtered = Bluetooth.scanList.filter(
            d => !Bluetooth.history.some(h => h.mac === d.mac))
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
                newDevRemoveTimer.restart()
            } else {
                newDevices = filtered
            }
    }

    function recomputePaired() {
        const oldIds = pairedDevices.map(d => d.mac)
        const newIds = Bluetooth.history.map(d => d.mac)
        if (oldIds.join(",") === newIds.join(",")) return

            const removedIds = oldIds.filter(id => !newIds.includes(id))
            if (removedIds.length > 0) {
                removedIds.forEach(id => {
                    const idx = oldIds.indexOf(id)
                    const item = pairedRepeater.itemAt(idx)
                    if (item) item.playExit()
                })
                pairedRemoveTimer.restart()
            } else {
                pairedDevices = Bluetooth.history
            }
    }

    Timer {
        id: newDevRemoveTimer
        interval: Animations.slideBlurDuration
        onTriggered: {
            btDetail.newDevices = Bluetooth.scanList.filter(
                d => !Bluetooth.history.some(h => h.mac === d.mac))
        }
    }

    Timer {
        id: pairedRemoveTimer
        interval: Animations.slideBlurDuration
        onTriggered: btDetail.pairedDevices = Bluetooth.history
    }

    Connections {
        target: Bluetooth
        function onScanListChanged() { btDetail.recomputeNewDevices() }
        function onHistoryChanged() { btDetail.recomputeNewDevices(); btDetail.recomputePaired() }
    }

    Component.onCompleted: {
        recomputeNewDevices()
        recomputePaired()
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        GlassButton {
            text: "\u2190"
            implicitWidth: 30
            implicitHeight: 26
            Layout.leftMargin: 3
            onClicked: btDetail.handleBack()
        }

        Text {
            text: "Bluetooth"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(13)
            font.bold: true
            Layout.fillWidth: true
        }

        GlassButton {
            id: settingsButton
            implicitWidth: 30
            implicitHeight: 26
            active: Bluetooth.liveMode
            onClicked: Bluetooth.toggleLiveMode()
            onActiveChanged: settingsIcon.rotation = active ? 90 : 0

            Image {
                id: settingsIcon
                anchors.centerIn: parent
                source: "file://" + Quickshell.env("HOME") + "/.config/icons/settings.svg"
                sourceSize.width: 14
                sourceSize.height: 14
                width: 14; height: 14
                opacity: settingsButton.active ? 1.0 : 0.85
                scale: settingsButton.active ? 1.1 : 1.0
                visible: false

                Behavior on rotation {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
                Behavior on scale {
                    NumberAnimation { duration: 220; easing.type: Easing.OutBack }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            ColorOverlay {
                anchors.fill: settingsIcon
                source: settingsIcon
                color: Theme.foreground
                rotation: settingsIcon.rotation
                opacity: settingsIcon.opacity
                scale: settingsIcon.scale
            }

        }

        GlassButton {
            variant: "toggle"
            Layout.rightMargin:3
            active: Bluetooth.radioOn
            text: Bluetooth.radioOn ? "\u25cf ON" : "\u25cb OFF"
            onClicked: Bluetooth.toggleRadio()
        }
    }

    // ---- New devices (live scan) ----
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        visible: Bluetooth.liveMode

        Text {
            text: "New Devices"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.bold: true
            Layout.topMargin: -20
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Bluetooth.pendingConfirm !== null
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: "Confirm " + Bluetooth.pairingName + ": " + (Bluetooth.pendingConfirm ? Bluetooth.pendingConfirm.code : "")
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                wrapMode: Text.Wrap
            }
            GlassButton {
                text: "\u2713"
                implicitWidth: 26
                implicitHeight: 26
                onClicked: { instantColor = true; Bluetooth.confirmYes() }
                scale: confirmHoverNew.hovered ? 1.08 : 1.0
                transformOrigin: Item.Center
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                HoverHandler { id: confirmHoverNew }
            }
            GlassButton {
                text: "\u2715"
                implicitWidth: 26
                implicitHeight: 26
                hoverBorderColor: "red"
                onClicked: { instantColor = true; Bluetooth.confirmNo() }
                scale: rejectHoverNew.hovered ? 1.08 : 1.0
                transformOrigin: Item.Center
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                HoverHandler { id: rejectHoverNew }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Bluetooth.pendingPin !== null
            onVisibleChanged: if (visible) { pinFieldNew.text = ""; pinFieldNew.forceActiveFocus() }
            spacing: 4
            TextField {
                id: pinFieldNew
                Layout.fillWidth: true
                implicitHeight: 27
                placeholderText: "PIN for " + Bluetooth.pairingName
                focus: Bluetooth.pendingPin !== null
                onTextChanged: btDetail.pinDraft = text
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                background: Rectangle {
                    radius: Theme.radiusSm
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.borderMuted
                }
                onAccepted: { Bluetooth.submitPin(btDetail.pinDraft); btDetail.pinDraft = "" }
            }
            GlassButton {
                text: "Submit"
                implicitHeight: 27
                onClicked: { instantColor = true; Bluetooth.submitPin(btDetail.pinDraft); btDetail.pinDraft = "" }
                scale: submitHoverNew.hovered ? 1.04 : 1.0
                transformOrigin: Item.Center
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                HoverHandler { id: submitHoverNew }
            }
        }

        // ---- Unified single-line status: error > pairing-in-progress > connected. One Text, never stacks, self-clears. ----
        Text {
            id: statusLineNew
            Layout.fillWidth: true
            z: 10
            text: {
                if (Bluetooth.pairError !== "") return Bluetooth.pairError
                    if (Bluetooth.pairingMac !== "" && Bluetooth.pendingConfirm === null && Bluetooth.pendingPin === null)
                        return (Bluetooth.pairingIncoming ? "Incoming request from " : "Pairing with ") + Bluetooth.pairingName + "\u2026"
                        if (Bluetooth.connectedName !== "") return "Connected to " + Bluetooth.connectedName
                            return ""
            }
            visible: text.length > 0
            color: Bluetooth.pairError !== "" ? "#ff6b6b" : (Bluetooth.connectedName !== "" ? "#6bffa0" : "#aaaaaa")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            elide: Text.ElideRight
            maximumLineCount: 1

            property real shakeX: 0
            transform: Translate { x: statusLineNew.shakeX }
            layer.enabled: statusLineNew.shakeX !== 0
            layer.effect: DirectionalBlur { angle: 0; length: Math.min(28, Math.abs(statusLineNew.shakeX) * 5); samples: 21 }

            SequentialAnimation {
                id: statusLineNewShakeAnim
                NumberAnimation { target: statusLineNew; property: "shakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
                NumberAnimation { target: statusLineNew; property: "shakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
                NumberAnimation { target: statusLineNew; property: "shakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                NumberAnimation { target: statusLineNew; property: "shakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                NumberAnimation { target: statusLineNew; property: "shakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
            }
            onTextChanged: {
                statusLineNewShakeAnim.stop(); statusLineNewShakeAnim.start()
                if (Bluetooth.connectedName !== "" && Bluetooth.pairError === "" && Bluetooth.pairingMac === "")
                    connectedHideTimerNew.restart()
            }
            Behavior on opacity { NumberAnimation { duration: 140 } }

            GlassButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 22
                implicitHeight: 22
                text: "\u2715"
                visible: Bluetooth.pairError !== ""
                onClicked: Bluetooth.dismissError()
            }
        }
        Timer { id: connectedHideTimerNew; interval: 5000; onTriggered: Bluetooth.clearConnected() }

        Text {
            Layout.fillWidth: true
            visible: btDetail.newDevices.length === 0
            text: Bluetooth.scanList.length === 0 ? "Scanning\u2026" : "No new devices nearby"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.preferredHeight: 170
            clip: true

            ColumnLayout {
                width: parent.width
                y: 3.5
                x: 3
                spacing: 4

                Repeater {
                    id: newDevicesRepeater
                    model: btDetail.newDevices


                    delegate: Item {
                        id: entry
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: 36

                        property bool hoverSuppressed: false

                        property real entranceProgress: 1
                        property real exitProgress: 1
                        property real itemShakeX: 0
                        opacity: entranceProgress * exitProgress
                        scale: 0.85 + 0.15 * Math.min(entranceProgress, exitProgress)
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        transform: Translate { x: entry.itemShakeX }
                        layer.enabled: entranceProgress < 1 || exitProgress < 1 || entry.itemShakeX !== 0
                        layer.effect: DirectionalBlur {
                            angle: Animations.slideBlurHorizontalAngle
                            length: Math.max(entry.entranceBlur, entry.exitBlur, Math.abs(entry.itemShakeX) * 3)
                            samples: Animations.slideBlurSamples
                            transparentBorder: true
                        }

                        NumberAnimation on entranceProgress {
                            id: entryEntranceAnim
                            from: 0; to: 1
                            duration: Animations.slideBlurDuration
                            easing.type: Animations.slideBlurEasingOut
                            running: false
                            onRunningChanged: if (!running) entry.hoverSuppressed = false
                        }
                        NumberAnimation on exitProgress {
                            id: entryExitAnim
                            from: 1; to: 0
                            duration: Animations.slideBlurDuration
                            easing.type: Animations.slideBlurEasingIn
                            running: false
                        }
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
                        function playEntrance() {
                            entryExitAnim.stop(); exitProgress = 1; entranceProgress = 0
                            entry.hoverSuppressed = true
                            entryEntranceAnim.restart()
                            entryShakeAnim.restart()
                        }
                        function playExit() { entryEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; entryExitAnim.restart() }
                        Component.onCompleted: playEntrance()

                        ScanEntryButton {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: 10 // <--- ADJUST THIS VALUE to change the button width

                            active: Bluetooth.pairingMac === entry.modelData.mac &&
                            (Bluetooth.pendingConfirm !== null || Bluetooth.pendingPin !== null)
                            hoverEnabled: !entry.hoverSuppressed
                            text: entry.modelData.name
                            onClicked: Bluetooth.startPair(entry.modelData.mac, entry.modelData.name)

                            scale: hovered ? 1.02 : 1.0
                            Behavior on scale {
                                NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- Paired devices ----
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4
        visible: !Bluetooth.liveMode

        Text {
            text: "Paired Devices"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.bold: true
            Layout.topMargin: -20
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Bluetooth.pendingConfirm !== null
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: "Confirm " + Bluetooth.pairingName + ": " + (Bluetooth.pendingConfirm ? Bluetooth.pendingConfirm.code : "")
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                wrapMode: Text.Wrap
            }
            GlassButton {
                text: "\u2713"
                implicitWidth: 26
                implicitHeight: 26
                onClicked: { instantColor = true; Bluetooth.confirmYes() }
                scale: confirmHoverPaired.hovered ? 1.08 : 1.0
                transformOrigin: Item.Center
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                HoverHandler { id: confirmHoverPaired }
            }
            GlassButton {
                text: "\u2715"
                implicitWidth: 26
                implicitHeight: 26
                hoverBorderColor: "red"
                onClicked: { instantColor = true; Bluetooth.confirmNo() }
                scale: rejectHoverPaired.hovered ? 1.08 : 1.0
                transformOrigin: Item.Center
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                HoverHandler { id: rejectHoverPaired }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Bluetooth.pendingPin !== null
            onVisibleChanged: if (visible) { pinFieldPaired.text = ""; pinFieldPaired.forceActiveFocus() }
            spacing: 4
            TextField {
                id: pinFieldPaired
                Layout.fillWidth: true
                implicitHeight: 27
                placeholderText: "PIN for " + Bluetooth.pairingName
                focus: Bluetooth.pendingPin !== null
                onTextChanged: btDetail.pinDraft = text
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
                background: Rectangle {
                    radius: Theme.radiusSm
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.borderMuted
                }
                onAccepted: { Bluetooth.submitPin(btDetail.pinDraft); btDetail.pinDraft = "" }
            }
            GlassButton {
                text: "Submit"
                implicitHeight: 27
                onClicked: { instantColor = true; Bluetooth.submitPin(btDetail.pinDraft); btDetail.pinDraft = "" }
                scale: submitHoverPaired.hovered ? 1.04 : 1.0
                transformOrigin: Item.Center
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                HoverHandler { id: submitHoverPaired }
            }
        }

        // ---- Unified single-line status (paired-section duplicate) ----
        Text {
            id: statusLinePaired
            Layout.fillWidth: true
            z: 10
            text: {
                if (Bluetooth.pairError !== "") return Bluetooth.pairError
                    if (Bluetooth.pairingMac !== "" && Bluetooth.pendingConfirm === null && Bluetooth.pendingPin === null)
                        return (Bluetooth.pairingIncoming ? "Incoming request from " : "Pairing with ") + Bluetooth.pairingName + "\u2026"
                        if (Bluetooth.connectedName !== "") return "Connected to " + Bluetooth.connectedName
                            return ""
            }
            visible: text.length > 0
            color: Bluetooth.pairError !== "" ? "#ff6b6b" : (Bluetooth.connectedName !== "" ? "#6bffa0" : "#aaaaaa")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            elide: Text.ElideRight
            maximumLineCount: 1

            property real shakeX: 0
            transform: Translate { x: statusLinePaired.shakeX }
            layer.enabled: statusLinePaired.shakeX !== 0
            layer.effect: DirectionalBlur { angle: 0; length: Math.min(28, Math.abs(statusLinePaired.shakeX) * 5); samples: 21 }

            SequentialAnimation {
                id: statusLinePairedShakeAnim
                NumberAnimation { target: statusLinePaired; property: "shakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
                NumberAnimation { target: statusLinePaired; property: "shakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
                NumberAnimation { target: statusLinePaired; property: "shakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                NumberAnimation { target: statusLinePaired; property: "shakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
                NumberAnimation { target: statusLinePaired; property: "shakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
            }
            onTextChanged: {
                statusLinePairedShakeAnim.stop(); statusLinePairedShakeAnim.start()
                if (Bluetooth.connectedName !== "" && Bluetooth.pairError === "" && Bluetooth.pairingMac === "")
                    connectedHideTimerPaired.restart()
            }
            Behavior on opacity { NumberAnimation { duration: 140 } }

            GlassButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: 22
                implicitHeight: 22
                text: "\u2715"
                visible: Bluetooth.pairError !== ""
                onClicked: Bluetooth.dismissError()
            }
        }
        Timer { id: connectedHideTimerPaired; interval: 5000; onTriggered: Bluetooth.clearConnected() }

        ScrollView {
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.preferredHeight: 170
            clip: true

            ColumnLayout {
                width: parent.width
                y: 3
                x: 3
                spacing: 4

                Repeater {
                    id: pairedRepeater
                    model: btDetail.pairedDevices


                    delegate: RowLayout {
                        id: row
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: 4

                        property bool hoverSuppressed: false

                        property real entranceProgress: 1
                        property real exitProgress: 1
                        property real itemShakeX: 0
                        opacity: entranceProgress * exitProgress
                        scale: 0.85 + 0.15 * Math.min(entranceProgress, exitProgress)
                        property real entranceBlur: Math.sin(Math.PI * entranceProgress) * Animations.slideBlurHorizontalLength
                        property real exitBlur: Math.sin(Math.PI * exitProgress) * Animations.slideBlurHorizontalLength
                        transform: Translate { x: row.itemShakeX }
                        layer.enabled: entranceProgress < 1 || exitProgress < 1 || row.itemShakeX !== 0
                        layer.effect: DirectionalBlur {
                            angle: Animations.slideBlurHorizontalAngle
                            length: Math.max(row.entranceBlur, row.exitBlur, Math.abs(row.itemShakeX) * 3)
                            samples: Animations.slideBlurSamples
                            transparentBorder: true
                        }

                        NumberAnimation on entranceProgress {
                            id: rowEntranceAnim
                            from: 0; to: 1
                            duration: Animations.slideBlurDuration
                            easing.type: Animations.slideBlurEasingOut
                            running: false
                            onRunningChanged: if (!running) row.hoverSuppressed = false
                        }
                        NumberAnimation on exitProgress {
                            id: rowExitAnim
                            from: 1; to: 0
                            duration: Animations.slideBlurDuration
                            easing.type: Animations.slideBlurEasingIn
                            running: false
                        }
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
                        function playEntrance() {
                            rowExitAnim.stop(); exitProgress = 1; entranceProgress = 0
                            row.hoverSuppressed = true
                            rowEntranceAnim.restart()
                            rowShakeAnim.restart()
                        }
                        function playExit() { rowEntranceAnim.stop(); entranceProgress = 1; exitProgress = 1; rowExitAnim.restart() }
                        Component.onCompleted: playEntrance()

                        NameNewButton {
                            Layout.fillWidth: true
                            implicitHeight: 36
                            text: row.modelData.name
                            active: Bluetooth.connectedMacs.includes(row.modelData.mac)
                            inactiveTextColor: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.7)
                            onClicked: Bluetooth.connectTo(row.modelData.mac)

                            scale: hovered ? 1.02 : 1.0
                            Behavior on scale {
                                NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                            }
                        }

                        GlassButton {
                            implicitHeight: 36
                            implicitWidth: 34
                            text: "\u2715"
                            hoverEnabled: !row.hoverSuppressed
                            onClicked: Bluetooth.disconnect(row.modelData.mac)
                        }

                        GlassButton {
                            text: "Forget"
                            hoverBorderColor: "red"
                            implicitHeight: 36
                            hoverEnabled: !row.hoverSuppressed
                            onClicked: {
                                instantColor = true
                                hoverEnabled = false
                                Bluetooth.forget(row.modelData.mac)
                            }
                        }
                    }
                }
            }
        }
    }
}
