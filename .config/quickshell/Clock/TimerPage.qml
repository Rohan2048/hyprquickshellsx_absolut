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

    // Snap-style jitter for the "Time's Up!" entrance — separate property
    // from shakeX so it doesn't fight with playShake()'s tweened shake.
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
    // The Until button (top right) swaps the timer for a clock-time picker with the same slide + blur +
    // fade as the Date & time popup uses to enter and leave (Animations.pageSlideDuration / easings,
    // vertical blur, offset of the page height + 28). Start sets the timer to run until that time.
    property bool picking: false
    property real timerP: 1          // 1 = the timer view is fully shown
    property real untilP: 0          // 1 = the picker is fully shown
    property int pickMin: 0          // minutes since midnight
    // the popup holding this page grants it the keyboard only while the picker is open (typing the time)
    readonly property bool wantsKeyboard: root.picking
    property date now: new Date()
    readonly property bool idle: !TimerService.running && !TimerService.timesUp && TimerService.remainingMs === TimerService.durationMs

    function pad(n) { return n < 10 ? "0" + n : "" + n }
    readonly property string pickText: root.pad(Math.floor(root.pickMin / 60)) + ":" + root.pad(root.pickMin % 60)
    readonly property string inText: {
        const n = root.now
        const t = new Date(n)
        t.setHours(Math.floor(root.pickMin / 60), root.pickMin % 60, 0, 0)
        if (t.getTime() <= n.getTime()) t.setDate(t.getDate() + 1)
            const mins = Math.round((t.getTime() - n.getTime()) / 60000)
            const h = Math.floor(mins / 60), m = mins % 60
            return "in " + (h > 0 ? h + "h " : "") + m + "m"
    }

    // keeps the typable time showing pickMin, except while you are typing in it
    function syncTime() { if (!timeInput.activeFocus) timeInput.text = root.pickText }
    onPickMinChanged: root.syncTime()

    function openPicker() {
        const d = new Date()
        root.now = d
        // start from the next 5-minute mark, so a quick tap lands somewhere sensible
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
        timeInput.focus = false
        root.pickMin = (root.pickMin + deltaMin + 1440) % 1440
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
    // the timer started or was reset somewhere else (bar chip, other popup): leave the picker
    Connections {
        target: TimerService
        function onRunningChanged() { if (TimerService.running && root.picking) root.closePicker() }
    }

    // State and logic live in Services/TimerService.qml so the bar can see
    // whether a timer is active. This page is only a view over it.
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

            // Normal timer view
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

                // FIX: this row now actually collapses (height animates to 0)
                // once the timer starts, instead of just fading out while still
                // holding its layout space. Because the ColumnLayout is
                // vertically centered in the 75px widget, collapsing this row
                // shrinks the column and the whole thing re-centers — which is
                // what pulls the countdown text down toward center.
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

                    Item {
                        implicitWidth: 40
                        implicitHeight: 30
                        Text {
                            anchors.centerIn: parent
                            text: "-1h"
                            font.pixelSize: Theme.fontSizeSm
                            font.family: Theme.fontFamily
                            color: Theme.textMuted
                        }
                        MouseArea { anchors.fill: parent; onClicked: TimerService.adjust(-3600000) }
                    }
                    Item {
                        implicitWidth: 40
                        implicitHeight: 30
                        Text {
                            anchors.centerIn: parent
                            text: "-1m"
                            font.pixelSize: Theme.fontSizeSm
                            font.family: Theme.fontFamily
                            color: Theme.textMuted
                        }
                        MouseArea { anchors.fill: parent; onClicked: TimerService.adjust(-60000) }
                    }
                    Item {
                        implicitWidth: 40
                        implicitHeight: 30
                        Text {
                            anchors.centerIn: parent
                            text: "+1m"
                            font.pixelSize: Theme.fontSizeSm
                            font.family: Theme.fontFamily
                            color: Theme.textMuted
                        }
                        MouseArea { anchors.fill: parent; onClicked: TimerService.adjust(60000) }
                    }
                    Item {
                        implicitWidth: 40
                        implicitHeight: 30
                        Text {
                            anchors.centerIn: parent
                            text: "+1h"
                            font.pixelSize: Theme.fontSizeSm
                            font.family: Theme.fontFamily
                            color: Theme.textMuted
                        }
                        MouseArea { anchors.fill: parent; onClicked: TimerService.adjust(3600000) }
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

            // FIX: inline "Time's Up" state — occupies the same 75px area,
            // no overlay, no z-ordering, no anchors.fill on an ancestor.
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

        // top right: end the timer at a clock time instead of after a duration
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
                // click the time and type it, e.g. 2030 for 20:30 (the -1h / -5m / +5m / +1h buttons still work)
                TextInput {
                    id: timeInput
                    inputMask: "99:99"
                    inputMethodHints: Qt.ImhDigitsOnly
                    selectByMouse: true
                    font.pixelSize: Theme.fontSizeXl
                    font.bold: true
                    font.family: Theme.fontFamily
                    color: Theme.foreground
                    selectionColor: Theme.accentActive
                    Component.onCompleted: root.syncTime()
                    onActiveFocusChanged: { if (activeFocus) selectAll(); else root.syncTime() }
                    onTextEdited: {
                        if (!acceptableInput) return
                            const p = text.split(":")
                            root.pickMin = Math.min(23, parseInt(p[0], 10)) * 60 + Math.min(59, parseInt(p[1], 10))
                    }
                    onEditingFinished: focus = false
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
                        text: "Back"
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
