import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import "../Theme"
import "../Services"
import "../Widgets"

Item {
    id: root
    width: parent ? parent.width : 300
    implicitHeight: 75

    property real shakeX: 0
    property real blurAmount: Math.abs(shakeX) * (Animations.shakyBlurMaxLength / Animations.shakyJitterMax)

    function playShake() {
        shakeAnim.stop()
        shakeAnim.restart()
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax; duration: Animations.shakyStepDuration; easing.type: Easing.OutBack }
        NumberAnimation { target: root; property: "shakeX"; to: -Animations.shakyJitterMax * 0.5; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax * 0.4; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: -Animations.shakyJitterMax * 0.2; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: Animations.shakyJitterMax * 0.1; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "shakeX"; to: 0; duration: Animations.shakyStepDuration; easing.type: Easing.InOutQuad }
    }

    property real timesUpShakeX: 0

    SequentialAnimation {
        id: timesUpShakeAnim
        NumberAnimation { target: root; property: "timesUpShakeX"; to: 3; duration: Animations.scaleDuration(35); easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: -4; duration: Animations.scaleDuration(35); easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: 2; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: -3; duration: Animations.scaleDuration(30); easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: 3; duration: Animations.scaleDuration(28); easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: -3; duration: Animations.scaleDuration(25); easing.type: Easing.InOutQuad }
        NumberAnimation { target: root; property: "timesUpShakeX"; to: 0; duration: Animations.scaleDuration(25); easing.type: Easing.OutQuad }
    }

    // ---- "Until a clock time" ----
    property bool picking: false
    property real timerP: 1
    property real untilP: 0
    property int pickMin: 0          // minutes since midnight
    // the popup grants the keyboard only while the picker is open
    readonly property bool wantsKeyboard: root.picking
    property date now: new Date()
    readonly property bool idle: !TimerService.running && !TimerService.timesUp && TimerService.remainingMs === TimerService.durationMs

    function pad(n) { return n < 10 ? "0" + n : "" + n }
    readonly property string pickText: root.pad(Math.floor(root.pickMin / 60)) + ":" + root.pad(root.pickMin % 60)

    // Same maths as TimerService.startUntil: whole minutes from the start of the current minute,
    // so 20:05 -> 20:10 reads "in 5m" and the timer starts at 05:00.
    readonly property string inText: {
        const n = root.now
        const base = new Date(n)
        base.setSeconds(0, 0)
        const t = new Date(n)
        t.setHours(Math.floor(root.pickMin / 60), root.pickMin % 60, 0, 0)
        if (t.getTime() <= n.getTime()) t.setDate(t.getDate() + 1)
            const mins = Math.round((t.getTime() - base.getTime()) / 60000)
            const h = Math.floor(mins / 60), m = mins % 60
            return "in " + (h > 0 ? h + "h " : "") + m + "m"
    }

    // Reads whatever is typed ("2030", "20:30", "930", "9") and applies it to pickMin.
    function commitTyped() {
        const d = timeInput.text.replace(/\D/g, "")
        if (d.length === 0) return false
            let h, m
            if (d.length <= 2)       { h = parseInt(d, 10); m = 0 }
            else if (d.length === 3) { h = parseInt(d.slice(0, 1), 10); m = parseInt(d.slice(1), 10) }
            else                     { h = parseInt(d.slice(0, 2), 10); m = parseInt(d.slice(2, 4), 10) }
            if (isNaN(h) || isNaN(m)) return false
                root.pickMin = Math.min(23, h) * 60 + Math.min(59, m)
                return true
    }

    function syncTime() { if (!timeInput.activeFocus) timeInput.text = root.pickText }
    onPickMinChanged: root.syncTime()

    function openPicker() {
        const d = new Date()
        root.now = d
        root.pickMin = (Math.ceil((d.getHours() * 60 + d.getMinutes() + 1) / 5) * 5) % 1440
        root.syncTime()
        root.picking = true
        toTimer.stop()
        toUntil.restart()
    }
    function closePicker() {
        root.picking = false
        toUntil.stop()
        toTimer.restart()
    }
    function nudge(deltaMin) {
        root.commitTyped()          // use whatever is typed as the base
        timeInput.focus = false
        root.pickMin = (root.pickMin + deltaMin + 1440) % 1440
        timeInput.text = root.pickText   // set directly, don't rely on focus state
    }

    // grab keyboard focus once the popup has been granted the keyboard
    onPickingChanged: if (picking) focusTimer.restart()
    Timer {
        id: focusTimer
        interval: 150
        onTriggered: if (root.picking) timeInput.forceActiveFocus()
    }

    ParallelAnimation {
        id: toUntil
        NumberAnimation { target: root; property: "timerP"; to: 0; duration: Animations.pageSlideDuration; easing.type: Animations.pageSlideEasingIn }
        NumberAnimation { target: root; property: "untilP"; to: 1; duration: Animations.pageSlideDuration; easing.type: Animations.pageSlideEasingOut }
    }
    ParallelAnimation {
        id: toTimer
        NumberAnimation { target: root; property: "untilP"; to: 0; duration: Animations.pageSlideDuration; easing.type: Animations.pageSlideEasingIn }
        NumberAnimation { target: root; property: "timerP"; to: 1; duration: Animations.pageSlideDuration; easing.type: Animations.pageSlideEasingOut }
    }
    Timer {
        interval: 1000
        running: root.picking
        repeat: true
        onTriggered: root.now = new Date()
    }
    Connections {
        target: TimerService
        function onRunningChanged() { if (TimerService.running && root.picking) root.closePicker() }
    }
    Connections {
        target: TimerService
        function onTimesUpChanged() {
            if (TimerService.timesUp) timesUpShakeAnim.start()
        }
    }

    Item {
        id: timerView
        anchors.fill: parent
        visible: root.timerP > 0
        enabled: !root.picking
        y: (1 - root.timerP) * (root.implicitHeight + 28)
        opacity: root.timerP
        property real blurAmount: Math.sin(Math.PI * root.timerP) * Animations.slideBlurVerticalLength * 1.5
        layer.enabled: timerView.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurVerticalAngle
            length: timerView.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        Item {
            id: content
            anchors.fill: parent
            x: root.shakeX

            layer.enabled: root.shakeX !== 0
            layer.effect: DirectionalBlur {
                angle: Animations.slideBlurHorizontalAngle
                length: root.blurAmount
                samples: Animations.shakyBlurSamples
                transparentBorder: true
            }

            ColumnLayout {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: 6
                visible: !TimerService.timesUp

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: TimerService.timeText
                    font.pixelSize: Theme.fontSizeXl
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.foreground
                }

                property bool adjustVisible: !TimerService.running && TimerService.remainingMs === TimerService.durationMs

                RowLayout {
                    id: adjustRow
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredHeight: parent.adjustVisible ? implicitHeight : 0
                    spacing: 16
                    clip: true
                    opacity: parent.adjustVisible ? 1 : 0
                    enabled: parent.adjustVisible

                    Behavior on Layout.preferredHeight {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 150 }
                    }

                    Repeater {
                        model: [
                            { label: "-1h", d: -3600000 },
                            { label: "-1m", d: -60000 },
                            { label: "+1m", d: 60000 },
                            { label: "+1h", d: 3600000 }
                        ]
                        delegate: Item {
                            required property var modelData
                            implicitWidth: 40
                            implicitHeight: 30
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSm
                                font.family: Theme.fontFamily
                                color: Theme.textMuted
                            }
                            MouseArea { anchors.fill: parent; onClicked: TimerService.adjust(modelData.d) }
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 20

                    Item {
                        implicitWidth: 60
                        implicitHeight: 30
                        Text {
                            anchors.centerIn: parent
                            text: TimerService.running ? "Pause" : "Start"
                            font.pixelSize: Theme.fontSize
                            font.family: Theme.fontFamily
                            color: Theme.foreground
                        }
                        MouseArea { anchors.fill: parent; onClicked: TimerService.running ? TimerService.pause() : TimerService.start() }
                    }
                    Item {
                        implicitWidth: 60
                        implicitHeight: 30
                        Text {
                            anchors.centerIn: parent
                            text: "Reset"
                            font.pixelSize: Theme.fontSize
                            font.family: Theme.fontFamily
                            color: Theme.textMuted
                        }
                        MouseArea { anchors.fill: parent; onClicked: TimerService.reset() }
                    }
                }
            }

            ColumnLayout {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                spacing: 8
                visible: TimerService.timesUp
                transform: Translate { x: root.timesUpShakeX }

                layer.enabled: root.timesUpShakeX !== 0
                layer.effect: DirectionalBlur {
                    angle: 0
                    length: Math.min(28, Math.abs(root.timesUpShakeX) * 5)
                    samples: 21
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Time's Up!"
                    font.pixelSize: Theme.fontSizeLg
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.foreground
                }

                GlassButton {
                    Layout.alignment: Qt.AlignHCenter
                    text: "OK"
                    onClicked: TimerService.reset()
                }
            }
        }

        GlassButton {
            visible: root.idle
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.rightMargin: 2
            implicitWidth: 46
            implicitHeight: 22
            fontSize: Theme.fontSizeSm
            text: "Until"
            onClicked: root.openPicker()
        }
    }

    // ---- the clock-time picker ----
    Item {
        id: untilView
        anchors.fill: parent
        visible: root.untilP > 0
        enabled: root.picking
        y: (1 - root.untilP) * (root.implicitHeight + 28)
        opacity: root.untilP
        property real blurAmount: Math.sin(Math.PI * root.untilP) * Animations.slideBlurVerticalLength * 1.5
        layer.enabled: untilView.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurVerticalAngle
            length: untilView.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        ColumnLayout {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: 6

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                TextInput {
                    id: timeInput
                    maximumLength: 5
                    inputMethodHints: Qt.ImhDigitsOnly
                    selectByMouse: true
                    activeFocusOnPress: true
                    cursorVisible: activeFocus
                    font.pixelSize: Theme.fontSizeXl
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.foreground
                    selectionColor: Theme.accentActive
                    Component.onCompleted: root.syncTime()

                    onActiveFocusChanged: {
                        if (activeFocus) selectAll()
                            else { root.commitTyped(); root.syncTime() }
                    }
                    onTextEdited: {
                        const d = text.replace(/\D/g, "").slice(0, 4)
                        const f = d.length > 2 ? d.slice(0, 2) + ":" + d.slice(2) : d
                        if (text !== f) { text = f; cursorPosition = f.length }
                        if (d.length === 4) root.commitTyped()
                    }
                    onAccepted: { root.commitTyped(); focus = false }

                    // keep typing keys from leaking to the rest of the popup
                    Keys.onPressed: (e) => {
                        if (e.key === Qt.Key_Escape) {
                            text = root.pickText
                            focus = false
                            e.accepted = true
                        } else if ((e.key >= Qt.Key_0 && e.key <= Qt.Key_9)
                            || e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete
                            || e.key === Qt.Key_Left || e.key === Qt.Key_Right
                            || e.key === Qt.Key_Home || e.key === Qt.Key_End
                            || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                            e.accepted = false
                            } else {
                                e.accepted = true
                            }
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 3
                    text: root.inText
                    font.pixelSize: Theme.fontSizeSm
                    font.family: Theme.fontFamily
                    color: Theme.textMuted
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 16
                Repeater {
                    model: [
                        { label: "-1h", d: -60 },
                        { label: "-5m", d: -5 },
                        { label: "+5m", d: 5 },
                        { label: "+1h", d: 60 }
                    ]
                    delegate: Item {
                        required property var modelData
                        implicitWidth: 40
                        implicitHeight: 30
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: Theme.fontSizeSm
                            font.family: Theme.fontFamily
                            color: Theme.textMuted
                        }
                        MouseArea { anchors.fill: parent; onClicked: root.nudge(modelData.d) }
                    }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 20

                Item {
                    implicitWidth: 60
                    implicitHeight: 30
                    Text {
                        anchors.centerIn: parent
                        text: "Start"
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                        color: Theme.foreground
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.commitTyped()
                            TimerService.startUntil(Math.floor(root.pickMin / 60), root.pickMin % 60)
                            root.closePicker()
                        }
                    }
                }
                Item {
                    implicitWidth: 60
                    implicitHeight: 30
                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.pixelSize: Theme.fontSize
                        font.family: Theme.fontFamily
                        color: Theme.textMuted
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.closePicker() }
                }
            }
        }
    }
}
