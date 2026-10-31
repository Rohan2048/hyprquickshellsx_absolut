import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import "../Theme"
import "../Widgets"
import "../Services"

Scope {
    id: root

    property string currentText: ""; property bool unlocking: false; property bool failed: false
    property bool actionPrompt: false
    property var pendingAction: null
    property var confirmAction: null
    property string confirmActionName: ""

    readonly property bool isHyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE").length > 0

    property real lastCursorX: -1; property real lastCursorY: -1
    readonly property real idleMoveThreshold: 4

    onCurrentTextChanged: if (currentText.length > 0) actionPrompt = false

    Timer { id: confirmActionTimer; interval: 4000; onTriggered: { root.confirmAction = null; root.confirmActionName = "" } }
    Timer { id: actionPromptTimer; interval: 2200; onTriggered: root.actionPrompt = false }

    PamContext {
        id: pam
        onCompleted: (result) => {
            root.unlocking = false
            if (result === PamResult.Success) {
                if (root.pendingAction) { const action = root.pendingAction; root.pendingAction = null; root.currentText = ""; action() }
                else lock.locked = false
            } else { root.failed = true; root.currentText = ""; root.pendingAction = null }
        }
        onError: (err) => { root.unlocking = false; root.failed = true; root.pendingAction = null }
        onPamMessage: if (pam.responseRequired) pam.respond(root.currentText)
    }

    function tryUnlock() {
        if (unlocking || currentText.length === 0) return
            failed = false; unlocking = true; pam.start()
    }

    function authenticate(action, name) {
        if (currentText.length === 0) { failed = false; pendingAction = action; actionPrompt = true; actionPromptTimer.restart(); return }
        if (unlocking) return
            if (confirmActionName === name) {
                confirmAction = null; confirmActionName = ""; confirmActionTimer.stop()
                failed = false; actionPrompt = false; pendingAction = action; unlocking = true
                pam.start(); return
            }
            confirmAction = action; confirmActionName = name; confirmActionTimer.restart()
    }

    function cancelPendingAction() {
        pendingAction = null; actionPrompt = false; confirmAction = null; confirmActionName = ""; confirmActionTimer.stop()
    }

    function resetLock() {
        currentText = ""; failed = false; actionPrompt = false
        pendingAction = null; confirmAction = null; confirmActionName = ""
        confirmActionTimer.stop()
        if (pam.active) pam.abort()
    }

    FileView {
        id: unlockTokenFile
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/lock-unlock-token"
        blockLoading: true; watchChanges: true; printErrors: false
        onFileChanged: reload()
    }

    function remoteUnlock(token) {
        const expected = unlockTokenFile.text().trim()
        if (expected.length === 0) return
            if (typeof token !== "string" || token.length === 0 || token !== expected) return
                root.failed = false; root.currentText = ""; root.pendingAction = null; root.unlocking = false
                if (pam.active) pam.abort()
                    lock.locked = false
    }

    Timer { id: autoSuspendTimer; interval: 30000; repeat: false; onTriggered: { if (lock.locked) autoSuspendProc.running = true } }

    function startAutoSuspendIfNeeded() {
        root.lastCursorX = -1; root.lastCursorY = -1
        // Only ever arm the idle-suspend while the session is actually locked.
        // Surface visibility changes after an unlock (newer Quickshell) used to
        // re-arm it, suspending the machine while it was in normal use.
        if (root.isHyprland && lock.locked) autoSuspendTimer.restart()
            else autoSuspendTimer.stop()
    }

    Process {
        id: autoSuspendProc
        command: ["systemctl", "suspend"]
        stderr: SplitParser { onRead: (line) => {} }
        onExited: (exitCode, exitStatus) => { if (lock.locked) root.startAutoSuspendIfNeeded() }
    }

    property int pendingCaptures: 0

    Component {
        id: captureComponent
        Process {
            property string screenName
            command: ["grim", "-o", screenName, "/tmp/quickshell-lockshot-" + screenName + ".png"]
            stderr: SplitParser { onRead: (line) => {} }
            onExited: (exitCode, exitStatus) => {
                root.pendingCaptures--
                if (root.pendingCaptures <= 0) { lock.locked = true; root.startAutoSuspendIfNeeded() }
                destroy()
            }
        }
    }

    function lockRequested() {
        const screens = Quickshell.screens
        if (!screens || screens.length === 0) { lock.locked = true; root.startAutoSuspendIfNeeded(); return }
        pendingCaptures = screens.length
        for (let i = 0; i < screens.length; i++) { const proc = captureComponent.createObject(root, { screenName: screens[i].name }); proc.running = true }
    }

    WlSessionLock {
        id: lock
        onLockedChanged: { if (locked) root.startAutoSuspendIfNeeded(); else { autoSuspendTimer.stop(); root.lastCursorX = -1; root.lastCursorY = -1 } }

        WlSessionLockSurface {
            id: surface
            property bool settingsOpen: false

            MouseArea {
                anchors.fill: parent; hoverEnabled: true; propagateComposedEvents: true; z: -1
                onEntered: pwField.forceActiveFocus()
                onPositionChanged: (mouse) => {
                    if (!pwField.activeFocus) pwField.forceActiveFocus()
                        if (root.lastCursorX < 0) { root.lastCursorX = mouse.x; root.lastCursorY = mouse.y; return }
                        const dx = mouse.x - root.lastCursorX, dy = mouse.y - root.lastCursorY
                        root.lastCursorX = mouse.x; root.lastCursorY = mouse.y
                        if (Math.abs(dx) < root.idleMoveThreshold && Math.abs(dy) < root.idleMoveThreshold) return
                            if (root.isHyprland && lock.locked) autoSuspendTimer.restart()
                }
            }

            // everything behind the UI: the settings panel blurs this
            Item {
                id: backdrop
                anchors.fill: parent
                LockBackground {
                    anchors.fill: parent
                    screen: surface.screen
                    wallpaperPath: LockPresets.layout.bg.mode === "wallpaper" ? LockPresets.layout.bg.path : ""
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.background.hslLightness < 0.5 ? "black" : "white"
                    opacity: LockPresets.layout.bg.dim / 100
                }

                // shapes added in Settings > Lock screen (none unless a preset has some)
                LockShapes { anchors.fill: parent; shapes: LockPresets.layout.shapes }

                // notes: a line of text and / or your signature (Settings > Lock screen > Notes)
                Repeater {
                    model: LockPresets.layout.notes
                    delegate: LockNote {
                        required property var modelData
                        spec: modelData
                        x: LockPresets.place(modelData.fx, backdrop.width, width, LockPresets.margin)
                        y: LockPresets.place(modelData.fy, backdrop.height, height, LockPresets.margin)
                    }
                }
            }

            // the power buttons, stretched by Settings > Lock screen > Power buttons
            LockScaled {
                id: powerBox
                child: powerRow
                sx: LockPresets.layout.power.sx
                sy: LockPresets.layout.power.sy
                x: LockPresets.place(LockPresets.layout.power.fx, surface.width, width, LockPresets.margin)
                y: LockPresets.place(LockPresets.layout.power.fy, surface.height, height, LockPresets.margin)

                RowLayout {
                    id: powerRow
                    spacing: 10
                    readonly property string iconDir: "file://" + Quickshell.env("HOME") + "/.config/icons/"
                    function requestAction(action, name) { root.authenticate(action, name) }

                    GlassButton {
                        id: suspendBtn; icon: ""; elevated: true; implicitWidth: 48; implicitHeight: 48; radiusOverride: LockPresets.layout.power.radius
                        ThemedIcon { anchors.centerIn: parent; iconId: "lock-suspend"; fallback: powerRow.iconDir + "suspend.svg"; size: 20 }
                        property real shakeX: 0
                        transform: Translate { x: suspendBtn.shakeX }
                        layer.enabled: suspendBtn.shakeX !== 0
                        layer.effect: DirectionalBlur { angle: 0; length: Math.min(10, Math.abs(suspendBtn.shakeX) * 3); samples: 16 }
                        SequentialAnimation {
                            id: suspendShake; running: false
                            PropertyAction { target: suspendBtn; property: "shakeX"; value: 5 }
                            PauseAnimation { duration: 30 }
                            PropertyAction { target: suspendBtn; property: "shakeX"; value: -5 }
                            PauseAnimation { duration: 30 }
                            PropertyAction { target: suspendBtn; property: "shakeX"; value: 3 }
                            PauseAnimation { duration: 25 }
                            PropertyAction { target: suspendBtn; property: "shakeX"; value: -3 }
                            PauseAnimation { duration: 25 }
                            PropertyAction { target: suspendBtn; property: "shakeX"; value: 0 }
                        }
                        onClicked: { suspendShake.stop(); suspendShake.start(); suspendProc.running = true }
                    }
                    GlassButton {
                        id: restartBtn; icon: ""; elevated: true; implicitWidth: 48; implicitHeight: 48; radiusOverride: LockPresets.layout.power.radius
                        ThemedIcon { anchors.centerIn: parent; iconId: "lock-restart"; fallback: powerRow.iconDir + "restart.svg"; size: 20 }
                        property real shakeX: 0
                        transform: Translate { x: restartBtn.shakeX }
                        layer.enabled: restartBtn.shakeX !== 0
                        layer.effect: DirectionalBlur { angle: 0; length: Math.min(10, Math.abs(restartBtn.shakeX) * 3); samples: 16 }
                        SequentialAnimation {
                            id: restartShake; running: false
                            PropertyAction { target: restartBtn; property: "shakeX"; value: 5 }
                            PauseAnimation { duration: 30 }
                            PropertyAction { target: restartBtn; property: "shakeX"; value: -5 }
                            PauseAnimation { duration: 30 }
                            PropertyAction { target: restartBtn; property: "shakeX"; value: 3 }
                            PauseAnimation { duration: 25 }
                            PropertyAction { target: restartBtn; property: "shakeX"; value: -3 }
                            PauseAnimation { duration: 25 }
                            PropertyAction { target: restartBtn; property: "shakeX"; value: 0 }
                        }
                        onClicked: { restartShake.stop(); restartShake.start(); powerRow.requestAction(() => rebootProc.running = true, "restart") }
                    }
                    GlassButton {
                        id: poweroffBtn; icon: ""; elevated: true; implicitWidth: 48; implicitHeight: 48; radiusOverride: LockPresets.layout.power.radius
                        ThemedIcon { anchors.centerIn: parent; iconId: "lock-poweroff"; fallback: powerRow.iconDir + "power-off.svg"; size: 20 }
                        property real shakeX: 0
                        transform: Translate { x: poweroffBtn.shakeX }
                        layer.enabled: poweroffBtn.shakeX !== 0
                        layer.effect: DirectionalBlur { angle: 0; length: Math.min(10, Math.abs(poweroffBtn.shakeX) * 3); samples: 16 }
                        SequentialAnimation {
                            id: poweroffShake; running: false
                            PropertyAction { target: poweroffBtn; property: "shakeX"; value: 5 }
                            PauseAnimation { duration: 30 }
                            PropertyAction { target: poweroffBtn; property: "shakeX"; value: -5 }
                            PauseAnimation { duration: 30 }
                            PropertyAction { target: poweroffBtn; property: "shakeX"; value: 3 }
                            PauseAnimation { duration: 25 }
                            PropertyAction { target: poweroffBtn; property: "shakeX"; value: -3 }
                            PauseAnimation { duration: 25 }
                            PropertyAction { target: poweroffBtn; property: "shakeX"; value: 0 }
                        }
                        onClicked: { poweroffShake.stop(); poweroffShake.start(); powerRow.requestAction(() => poweroffProc.running = true, "shutdown") }
                    }

                    Process { id: suspendProc; command: ["systemctl", "suspend"]; stderr: SplitParser { onRead: (line) => {} } }
                    Process { id: rebootProc; command: ["systemctl", "reboot"]; stderr: SplitParser { onRead: (line) => {} } }
                    Process { id: poweroffProc; command: ["systemctl", "poweroff"]; stderr: SplitParser { onRead: (line) => {} } }
                }
            }

            LockScaled {
                id: settingsBox
                z: 51
                child: settingsBtn
                sx: LockPresets.layout.settings.sx
                sy: LockPresets.layout.settings.sy
                x: LockPresets.place(LockPresets.layout.settings.fx, surface.width, width, LockPresets.margin)
                y: LockPresets.place(LockPresets.layout.settings.fy, surface.height, height, LockPresets.margin)

                LockSettingsButton {
                    id: settingsBtn
                    cornerRadius: LockPresets.layout.settings.radius
                    active: surface.settingsOpen
                    onToggled: surface.settingsOpen = !surface.settingsOpen
                }
            }

            // The panel opens from the settings button (side and offsets: Settings > Lock screen > Settings button).
            LockSettingsPanel {
                id: settingsPanel
                backdrop: backdrop
                wallpaperPath: LockPresets.layout.bg.mode === "wallpaper" ? LockPresets.layout.bg.path : ""
                dim: LockPresets.layout.bg.dim / 100
                dimColor: Theme.background.hslLightness < 0.5 ? "black" : "white"
                shapes: LockPresets.layout.shapes
                surfaceW: surface.width
                surfaceH: surface.height
                extraBlur: LockPresets.layout.bg.mode === "wallpaper" || LockPresets.layout.shapes.length > 0 || LockPresets.layout.notes.length > 0
                // above everything else on the lock screen, however close things are stacked
                z: 50
                readonly property var spot: LockPresets.panelRect(LockPresets.layout.settings,
                                                                  settingsBox.x, settingsBox.y, settingsBox.width, settingsBox.height,
                                                                  width, height, surface.width, surface.height, LockPresets.margin)
                x: spot.x
                y: spot.y
                transformOrigin: spot.origin
                contentX: LockPresets.layout.settings.contentX
                contentY: LockPresets.layout.settings.contentY
                shown: surface.settingsOpen
            }

            Item {
                id: clockGroup
                anchors.fill: parent

                // 0 = at rest, 1 = pushed away from the settings panel (direction from where the
                // settings button sits, see LockPresets.pushVector)
                property real slide: 0
                readonly property var push: LockPresets.pushVector(
                    LockPresets.layout.settings.fx, LockPresets.layout.settings.fy,
                    LockPresets.layout.settings.push, 140)

                Connections {
                    target: surface
                    function onSettingsOpenChanged() { slideAnim.restart() }
                }

                SequentialAnimation {
                    id: slideAnim
                    NumberAnimation {
                        target: clockGroup; property: "slide"
                        to: surface.settingsOpen ? 1 : 0
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }

                transform: Translate { x: clockGroup.slide * clockGroup.push.dx; y: clockGroup.slide * clockGroup.push.dy }

                layer.effect: DirectionalBlur {
                    angle: clockGroup.push.dy !== 0 ? 90 : 0
                    length: Math.sin(Math.PI * clockGroup.slide) * 10
                    samples: 16
                }

                Component.onCompleted: {
                    clockGroup.layer.enabled = true
                    warmupTimer.start()
                }
                Timer {
                    id: warmupTimer
                    interval: 16
                    onTriggered: clockGroup.layer.enabled = Qt.binding(function() { return clockGroup.slide !== 0 && clockGroup.slide !== 1 })
                }

                LockUser {
                    id: userBox
                    visible: LockPresets.layout.user.show
                    showPfp: LockPresets.layout.user.showPfp
                    showName: LockPresets.layout.user.showName
                    pfp: LockPresets.layout.user.pfp
                    size: LockPresets.layout.user.size
                    textGrad: LockPresets.textGrad(LockPresets.layout)
                    textColor: LockPresets.textColor(LockPresets.layout)
                    x: LockPresets.place(LockPresets.layout.user.fx, clockGroup.width, width, LockPresets.margin)
                    y: LockPresets.place(LockPresets.layout.user.fy, clockGroup.height, height, LockPresets.margin)
                }

                // the clock and date, stretched by Settings > Lock screen > Clock
                LockScaled {
                    id: clockBox
                    child: clock
                    sx: LockPresets.layout.clock.sx
                    sy: LockPresets.layout.clock.sy
                    x: LockPresets.place(LockPresets.layout.clock.fx, clockGroup.width, width, 0)
                    y: LockPresets.place(LockPresets.layout.clock.fy, clockGroup.height, height, 0)

                    LockClock {
                        id: clock
                        textGrad: LockPresets.textGrad(LockPresets.layout)
                        textColor: LockPresets.textColor(LockPresets.layout)
                        showDate: LockPresets.layout.clock.showDate
                    }
                }

                Text {
                    id: statusLabel
                    anchors.horizontalCenter: pwRow.horizontalCenter ;anchors.horizontalCenterOffset: -17 ;anchors.top: pwRow.bottom ;anchors.topMargin: 8
                    text: root.failed ? "Wrong password" : root.confirmAction !== null ? "Click again to confirm " + root.confirmActionName + "." : (root.pendingAction !== null ? "Password required to perform action." : "")
                    visible: text.length > 0
                    color: root.failed ? "#ff6b6b" : "white"
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(13)
                }

                Text {
                    id: cancelActionLabel
                    anchors.horizontalCenter: pwRow.horizontalCenter ;anchors.horizontalCenterOffset: -17 ;anchors.top: statusLabel.visible ? statusLabel.bottom : pwRow.bottom ;anchors.topMargin: 6
                    visible: root.pendingAction !== null || root.confirmAction !== null
                    text: "Cancel"
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fs(12); font.underline: true
                    color: "white"
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cancelPendingAction() }
                }

                RowLayout {
                    id: pwRow
                    // under the clock like always, or free (Settings > Lock screen > Password)
                    readonly property bool follow: LockPresets.layout.password.follow
                    x: follow ? clockBox.x + (clockBox.width - width) / 2
                    : LockPresets.place(LockPresets.layout.password.fx, clockGroup.width, width, 0)
                    y: follow ? clockBox.y + clockBox.height + 24
                    : LockPresets.place(LockPresets.layout.password.fy, clockGroup.height, height, 0)
                    spacing: 6

                    function submit() { root.tryUnlock() }
                    function reset() { root.resetLock(); pwField.text = "" }

                    TextField {
                        id: pwField
                        Layout.preferredWidth: 180; implicitHeight: 22
                        leftPadding: 0; rightPadding: 0; topPadding: 2; bottomPadding: 0
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password; passwordCharacter: "\u2022"
                        horizontalAlignment: TextInput.AlignHCenter




                        cursorVisible: false
                        cursorDelegate: Item {}

                        Keys.onPressed: (event) => {
                            if (event.modifiers & Qt.ControlModifier && (event.key === Qt.Key_C || event.key === Qt.Key_V || event.key === Qt.Key_X)) event.accepted = true
                        }

                        color: "transparent"; selectionColor: "transparent"; selectedTextColor: "transparent"
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fs(16)

                        property real dotsOffsetX: 0; property real dotsOffsetY: 0

                        Rectangle {
                            id: selectionHighlight
                            visible: pwField.selectedText.length > 0
                            color: Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.35)
                            radius: 4; height: 14
                            anchors.verticalCenter: dotsHolder.verticalCenter
                            anchors.verticalCenterOffset: -2
                            readonly property real dotPitch: 13
                            x: dotsHolder.x + pwField.selectionStart * dotPitch - 3
                            width: Math.max(0, (pwField.selectionEnd - pwField.selectionStart) * dotPitch)
                        }
                        Text {
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "Enter Password..."
                            color: "#aaaaaa"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fs(16)
                            visible: pwField.activeFocus && root.currentText.length === 0
                        }
                        Row {
                            id: dotsHolder
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: pwField.dotsOffsetX; anchors.verticalCenterOffset: pwField.dotsOffsetY
                            spacing: 6; opacity: 1.0
                            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Repeater {
                                model: root.currentText.length
                                delegate: Rectangle { width: 7; height: 7; radius: 3.5; color: Theme.foreground }
                            }
                        }

                        property real shakeX: 0
                        transform: Translate { x: pwField.shakeX }
                        layer.enabled: pwField.shakeX !== 0
                        layer.effect: DirectionalBlur { angle: 0; length: Math.min(28, Math.abs(pwField.shakeX) * 5); samples: 24 }

                        SequentialAnimation {
                            id: pwShake; running: false
                            PropertyAction { target: pwField; property: "shakeX"; value: 6 }
                            PauseAnimation { duration: 35 }
                            PropertyAction { target: pwField; property: "shakeX"; value: -18 }
                            PauseAnimation { duration: 35 }
                            PropertyAction { target: pwField; property: "shakeX"; value: 12 }
                            PauseAnimation { duration: 30 }
                            PropertyAction { target: pwField; property: "shakeX"; value: -14 }
                            PauseAnimation { duration: 30 }
                            PropertyAction { target: pwField; property: "shakeX"; value: 8 }
                            PauseAnimation { duration: 28 }
                            PropertyAction { target: pwField; property: "shakeX"; value: -6 }
                            PauseAnimation { duration: 25 }
                            PropertyAction { target: pwField; property: "shakeX"; value: 0 }
                        }

                        Connections {
                            target: root
                            function onFailedChanged() {
                                if (root.failed) {
                                    pwShake.stop(); pwShake.start(); pwField.text = ""
                                    dotsHolder.opacity = 0
                                    dotsHolder.opacity = Qt.binding(function() { return 1.0 })
                                }
                            }
                        }

                        background: Item {
                            anchors.fill: parent

                            Rectangle {
                                id: glowRing
                                anchors.fill: parent; radius: 10
                                color: "transparent"; border.width: 2; border.color: Theme.borderMuted
                                opacity: pwField.activeFocus ? 0.85 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                                SequentialAnimation {
                                    running: pwField.activeFocus; loops: Animation.Infinite
                                    ColorAnimation { target: glowRing; property: "border.color"; to: Qt.lighter(Theme.color3, 1.8); duration: 900; easing.type: Easing.InOutSine }
                                    ColorAnimation { target: glowRing; property: "border.color"; to: Theme.borderMuted; duration: 900; easing.type: Easing.InOutSine }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent; radius: 10
                                color: Qt.rgba(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, 0.5)
                                border.width: 2; border.color: pwField.activeFocus ? "transparent" : Theme.borderMuted
                            }
                        }

                        text: root.currentText
                        onTextChanged: if (root.currentText !== text) root.currentText = text

                        focus: true
                        onAccepted: pwRow.submit()
                        onActiveFocusChanged: {
                            pwShake.stop()
                            pwShake.start()
                        }
                        Component.onCompleted: forceActiveFocus()
                    }

                    Rectangle {
                        id: submitBtn
                        implicitWidth: 28; implicitHeight: 28; radius: 14
                        color: mouse.containsMouse ? Theme.hoverBgStrong : Qt.rgba(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, 0.5)
                        border.width: 1; border.color: Theme.borderMuted
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Text { anchors.centerIn: parent; text: "\u2192"; color: Theme.foreground; font.pixelSize: Theme.fs(15); font.bold: true }

                        MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: pwRow.submit() }
                    }
                }
            }

            LockScaled {
                id: battBox
                child: batt
                sx: LockPresets.layout.battery.sx
                sy: LockPresets.layout.battery.sy
                x: LockPresets.place(LockPresets.layout.battery.fx, surface.width, width, LockPresets.margin)
                y: LockPresets.place(LockPresets.layout.battery.fy, surface.height, height, LockPresets.margin)

                BatteryStatus { id: batt }
            }

            onVisibleChanged: {
                if (visible) { pwRow.reset(); pwField.forceActiveFocus(); pwShake.stop(); pwShake.start(); settingsBtn.triggerShake(); root.startAutoSuspendIfNeeded() }
                else settingsBtn.triggerShake()
            }
        }
    }

    IpcHandler {
        target: "lock"
        function lock() { root.lockRequested() }
        function unlock(token: string): void { root.remoteUnlock(token) }
    }
}
