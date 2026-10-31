import QtQuick
import Quickshell
import "Lock"
import "Theme"

ShellRoot {
    LockContext {
        id: lockContext
        onUnlocked: {
            console.log("[test] unlocked() fired â€” auth chain works")
            win.visible = false
        }
    }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1920
        implicitHeight: 1080
        color: "black"

        property bool settingsOpen: false

        LockBackground {
            anchors.fill: parent
            screen: Quickshell.screens[0]
        }

        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.35
        }

        PowerControls {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.topMargin: 24
            lockContext: lockContext
        }

        LockSettingsButton {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 24
            anchors.rightMargin: 24
            active: win.settingsOpen
            onToggled: win.settingsOpen = !win.settingsOpen
        }

        LockSettingsPanel {
            id: settingsPanel
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: 76
            anchors.rightMargin: 24
            opacity: win.settingsOpen ? 1 : 0
            visible: opacity > 0
            scale: win.settingsOpen ? 1 : 0.96
            transformOrigin: Item.TopRight
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        }

        LockClock {
            id: clock
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: win.settingsOpen ? -140 : 0
            Behavior on anchors.horizontalCenterOffset {
                NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
            }
        }

        PasswordField {
            anchors.horizontalCenter: clock.horizontalCenter
            anchors.top: clock.bottom
            anchors.topMargin: 24
            lockContext: lockContext
        }

        BatteryStatus {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.bottomMargin: 24
            anchors.rightMargin: 24
        }
    }
}
