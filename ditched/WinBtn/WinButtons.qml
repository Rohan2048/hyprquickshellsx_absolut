// ~/.config/quickshell/WinBtn/WinBtn.qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../Theme"

Row {
    id: root
    required property var bar
    required property var targetWindow // Pass Hyprland.activeToplevel or a specific window
    spacing: 6

    visible: root.targetWindow !== null

    // Close — mirrors mainMod+C (hl.dsp.window.close())
    Rectangle {
        width: 14; height: 14; radius: 7
        color: closeArea.containsMouse ? "#ff6159" : Qt.darker("#ff6159", 1.2)
        MouseArea {
            id: closeArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (root.targetWindow) {
                    Hyprland.dispatch('hl.dsp.window.close({window = "address:' + root.targetWindow.address + '"})')
                    closeRefresh.start()
                }
            }
        }
        Timer {
            id: closeRefresh
            interval: 50
            onTriggered: Hyprland.refreshToplevels()
        }
    }

    // Minimize — shifts to Hyprland's special workspaces
    Rectangle {
        width: 14; height: 14; radius: 7
        color: minArea.containsMouse ? "#ffbd2e" : Qt.darker("#ffbd2e", 1.2)
        MouseArea {
            id: minArea
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                if (root.targetWindow) root.bar.toggleMinimize(root.targetWindow)
            }
        }
    }

    // Fullscreen (left-click) / Float (right-click)
    Rectangle {
        width: 14; height: 14; radius: 7
        color: fullArea.containsMouse ? "#28c941" : Qt.darker("#28c941", 1.2)
        MouseArea {
            id: fullArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (mouse) => {
                if (!root.targetWindow) return
                    var addr = 'window = "address:' + root.targetWindow.address + '"'
                    if (mouse.button === Qt.RightButton) {
                        Hyprland.dispatch('hl.dsp.window.float({action = "toggle", ' + addr + '})')
                    } else {
                        Hyprland.dispatch('hl.dsp.window.fullscreen({mode = 0, ' + addr + '})')
                    }
            }
        }
    }
}
