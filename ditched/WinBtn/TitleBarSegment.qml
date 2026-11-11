// ~/.config/quickshell/Bar/TitlebarSegment.qml
// Drop into your bar's Row as a sibling module — it animates its own
// implicitWidth, and Row reflows neighboring modules automatically as it
// expands/collapses. No per-window overlay, no geometry tracking.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../Theme"

Item {
    id: root
    required property var bar

    readonly property var activeWindow: Hyprland.activeToplevel
    readonly property bool isFullscreen: activeWindow && activeWindow.wayland ? activeWindow.wayland.fullscreen : false

    readonly property var excludedClasses: [
        "firefox", "librewolf", "zen", "chromium", "google-chrome",
        "brave-browser", "code", "code-url-handler", "vesktop", "discord"
    ]

    function isExcluded(hypr) {
        var cls = (hypr && hypr.wayland ? hypr.wayland.appId : "").toLowerCase()
        return excludedClasses.indexOf(cls) !== -1
    }

    readonly property bool shouldShow: activeWindow !== null
    && !isFullscreen
    && !isExcluded(activeWindow)
    && !!activeWindow.workspace && activeWindow.workspace.active

    readonly property string winTitle: (shouldShow && activeWindow.title) ? activeWindow.title : ""

    // Content width = buttons + spacing + title, clamped so long titles don't blow out the bar
    readonly property int maxTitleWidth: 220
    readonly property int contentPadding: 10
    readonly property int buttonsWidth: 14 * 3 + 6 * 2 // three 14px dots, 6px spacing
    readonly property int titleWidth: Math.min(maxTitleWidth, titleMetrics.implicitWidth)

    implicitWidth: shouldShow
    ? contentPadding * 2 + buttonsWidth + 8 + titleWidth
    : 0
    implicitHeight: 26

    clip: true

    Behavior on implicitWidth {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    Behavior on opacity {
        NumberAnimation { duration: 120 }
    }
    opacity: shouldShow ? 1 : 0

    Rectangle {
        anchors.fill: parent
        radius: 6
        color: "#1e1e1e"
        visible: root.width > 1 // avoid a 1px sliver flash mid-collapse

        Row {
            anchors.left: parent.left
            anchors.leftMargin: root.contentPadding
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
                width: 14; height: 14; radius: 7
                color: closeArea.containsMouse ? "#ff6159" : Qt.darker("#ff6159", 1.2)
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (root.activeWindow) {
                            Hyprland.dispatch('hl.dsp.window.close({window = "address:' + root.activeWindow.address + '"})')
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

            Rectangle {
                width: 14; height: 14; radius: 7
                color: minArea.containsMouse ? "#ffbd2e" : Qt.darker("#ffbd2e", 1.2)
                MouseArea {
                    id: minArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        if (root.activeWindow) root.bar.toggleMinimize(root.activeWindow)
                    }
                }
            }

            Rectangle {
                width: 14; height: 14; radius: 7
                color: fullArea.containsMouse ? "#28c941" : Qt.darker("#28c941", 1.2)
                MouseArea {
                    id: fullArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (!root.activeWindow) return
                            var addr = 'window = "address:' + root.activeWindow.address + '"'
                            if (mouse.button === Qt.RightButton) {
                                Hyprland.dispatch('hl.dsp.window.float({action = "toggle", ' + addr + '})')
                            } else {
                                Hyprland.dispatch('hl.dsp.window.fullscreen({mode = 0, ' + addr + '})')
                            }
                    }
                }
            }

            Text {
                id: titleText
                anchors.verticalCenter: parent.verticalCenter
                text: root.winTitle
                color: "#cccccc"
                font.pixelSize: 12
                elide: Text.ElideRight
                width: Math.min(root.maxTitleWidth, implicitWidth)
            }

            // Off-screen metrics probe — measures full title width before eliding,
            // so root.implicitWidth can clamp against maxTitleWidth correctly.
            TextMetrics {
                id: titleMetrics
                font: titleText.font
                text: root.winTitle
            }
        }
    }
}
