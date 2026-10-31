import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam

// SBSLockScreen.qml — minimal SBS lock screen.
//
// Independent of the main Lock/ stack and of Theme.qml: fixed black
// background, white SF Pro Display text, zero animations/Behaviors/
// DirectionalBlur, no pre-lock screenshot capture. Mirrors
// LockScreen.qml's feature set -- PAM auth, two-step confirm on
// restart/poweroff, auto-suspend idle timer, KDE Connect remote-unlock
// token, quick-settings panel with Wifi/Bluetooth/Airplane/Volume/
// Brightness -- without any of the glass/blur/shake visual treatment.
//
// Loaded instead of LockScreen whenever SBSState.active is true (see
// the Loader in the shell root). Buttons/labels lean on the shared
// SBSBtn/SBSText components; the auth/timer state machine and every
// binding below are unchanged from the original per-Rectangle version.
Scope {
    id: root

    property string currentText: ""
    property bool unlocking: false
    property bool failed: false
    property bool actionPrompt: false      // true briefly when a power action was clicked with no password typed
    property var pendingAction: null
    property var confirmAction: null
    property string confirmActionName: ""
    readonly property bool isHyprland: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE").length > 0
    property real lastCursorX: -1
    property real lastCursorY: -1
    readonly property real idleMoveThreshold: 4

    onCurrentTextChanged: if (currentText.length > 0) actionPrompt = false

    Timer { id: confirmActionTimer; interval: 4000; onTriggered: { root.confirmAction = null; root.confirmActionName = "" } }
    Timer { id: actionPromptTimer; interval: 2200; onTriggered: root.actionPrompt = false }

    PamContext {
        id: pam
        onCompleted: (result) => {
            root.unlocking = false
            if (result === PamResult.Success) {
                if (root.pendingAction) {
                    const action = root.pendingAction
                    root.pendingAction = null; root.currentText = ""
                    action()
                } else lock.locked = false
            } else {
                root.failed = true; root.currentText = ""; root.pendingAction = null
            }
        }
        onError: (err) => { root.unlocking = false; root.failed = true; root.pendingAction = null }
        onPamMessage: if (pam.responseRequired) pam.respond(root.currentText)
    }

    function tryUnlock() {
        if (unlocking || currentText.length === 0) return
            failed = false; unlocking = true; pam.start()
    }

    function authenticate(action, name) {
        if (currentText.length === 0) {
            failed = false; pendingAction = action; actionPrompt = true
            actionPromptTimer.restart()
            return
        }
        if (unlocking) return
            if (confirmActionName === name) {
                confirmAction = null; confirmActionName = ""; confirmActionTimer.stop()
                failed = false; actionPrompt = false; pendingAction = action; unlocking = true
                pam.start()
                return
            }
            confirmAction = action; confirmActionName = name
            confirmActionTimer.restart()
    }

    function cancelPendingAction() {
        pendingAction = null; actionPrompt = false
        confirmAction = null; confirmActionName = ""
        confirmActionTimer.stop()
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
        if (root.isHyprland && lock.locked) autoSuspendTimer.restart()
            else autoSuspendTimer.stop()
    }

    Process {
        id: autoSuspendProc
        command: ["systemctl", "suspend"]
        onExited: if (lock.locked) root.startAutoSuspendIfNeeded()
    }

    function lockRequested() { lock.locked = true; root.startAutoSuspendIfNeeded() }

    WlSessionLock {
        id: lock
        onLockedChanged: { if (locked) root.startAutoSuspendIfNeeded(); else { autoSuspendTimer.stop(); root.lastCursorX = -1; root.lastCursorY = -1 } }

        WlSessionLockSurface {
            id: surface
            property bool settingsOpen: false

            SBSLockBackground { anchors.fill: parent }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true; propagateComposedEvents: true; z: -1
                onEntered: pwField.forceActiveFocus()
                onPositionChanged: (mouse) => {
                    if (!pwField.activeFocus) pwField.forceActiveFocus()
                        if (root.lastCursorX < 0) {
                            root.lastCursorX = mouse.x; root.lastCursorY = mouse.y
                            return
                        }
                        const dx = mouse.x - root.lastCursorX, dy = mouse.y - root.lastCursorY
                        root.lastCursorX = mouse.x; root.lastCursorY = mouse.y
                        if (Math.abs(dx) < root.idleMoveThreshold && Math.abs(dy) < root.idleMoveThreshold) return
                            if (root.isHyprland && lock.locked) autoSuspendTimer.restart()
                }
            }

            RowLayout {
                id: powerRow
                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 24 }
                spacing: 10
                function requestAction(action, name) { root.authenticate(action, name) }

                Repeater {
                    model: [
                        { label: "SUSPEND",  action: function() { suspendProc.running = true },  name: "",         confirm: false },
                        { label: "RESTART",  action: function() { rebootProc.running = true },   name: "restart",  confirm: true },
                        { label: "POWEROFF", action: function() { poweroffProc.running = true },  name: "shutdown", confirm: true }
                    ]
                    delegate: SBSBtn {
                        required property var modelData
                        size: 11; cursorShape: Qt.PointingHandCursor; text: modelData.label
                        onClicked: modelData.confirm ? powerRow.requestAction(modelData.action, modelData.name) : modelData.action()
                    }
                }
                Process { id: suspendProc; command: ["systemctl", "suspend"] }
                Process { id: rebootProc; command: ["systemctl", "reboot"] }
                Process { id: poweroffProc; command: ["systemctl", "poweroff"] }
            }

            SBSLockSettingsButton {
                id: settingsBtn
                anchors { top: parent.top; right: parent.right; topMargin: 24; rightMargin: 24 }
                active: surface.settingsOpen
                onToggled: surface.settingsOpen = !surface.settingsOpen
            }

            SBSLockSettingsPanel {
                anchors { top: parent.top; right: parent.right; topMargin: 68; rightMargin: 24 }
                visible: surface.settingsOpen
            }

            SBSLockClock {
                id: clock
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: surface.settingsOpen ? -140 : 0
            }

            SBSText {
                id: statusLabel
                anchors { horizontalCenter: clock.horizontalCenter; top: pwRow.bottom; topMargin: 8 }
                text: root.failed ? "WRONG PASSWORD"
                : root.confirmAction !== null ? "CLICK AGAIN TO CONFIRM " + root.confirmActionName.toUpperCase() + "."
                : (root.pendingAction !== null ? "PASSWORD REQUIRED." : "")
                visible: text.length > 0
                size: 12
            }

            SBSText {
                id: cancelActionLabel
                anchors.horizontalCenter: clock.horizontalCenter
                anchors.top: statusLabel.visible ? statusLabel.bottom : pwRow.bottom
                anchors.topMargin: 6
                visible: root.pendingAction !== null || root.confirmAction !== null
                text: "CANCEL"; size: 11; font.underline: true
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.cancelPendingAction() }
            }

            RowLayout {
                id: pwRow
                anchors { horizontalCenter: clock.horizontalCenter; top: clock.bottom; topMargin: 24 }
                spacing: 6
                function submit() { root.tryUnlock() }
                function reset() { root.resetLock(); pwField.text = "" }

                TextField {
                    id: pwField
                    Layout.preferredWidth: 180; implicitHeight: 28
                    echoMode: TextInput.Password
                    passwordCharacter: "*"
                    horizontalAlignment: TextInput.AlignHCenter
                    placeholderText: "PASSWORD"
                    font.family: "SF Pro Display"; font.pixelSize: 14
                    color: "white"; placeholderTextColor: "white"
                    background: Rectangle {
                        color: "black"; border.width: 1; radius: 4
                        border.color: pwField.activeFocus ? "white" : "#808080"
                    }
                    text: root.currentText
                    onTextChanged: if (root.currentText !== text) root.currentText = text
                    focus: true
                    onAccepted: pwRow.submit()
                    Component.onCompleted: forceActiveFocus()
                }

                SBSBtn {
                    implicitWidth: 28; implicitHeight: 28; text: "\u2192"; size: 15
                    cursorShape: Qt.PointingHandCursor
                    onClicked: pwRow.submit()
                }
            }

            SBSLockBatteryStatus {
                anchors { bottom: parent.bottom; right: parent.right; bottomMargin: 24; rightMargin: 24 }
            }

            onVisibleChanged: if (visible) { pwRow.reset(); pwField.forceActiveFocus(); root.startAutoSuspendIfNeeded() }
        }
    }

    IpcHandler {
        target: "lock"
        function lock() { root.lockRequested() }
        function unlock(token: string): void { root.remoteUnlock(token) }
    }
}
