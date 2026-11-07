// ~/.config/quickshell/WinBtn/WinDecorations.qml
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../Theme"

PanelWindow {
    id: root
    required property var bar

    // Track ONLY the active window to prevent stacking overlays on every window
    readonly property var activeWindow: Hyprland.activeToplevel
    readonly property var ipc: activeWindow ? activeWindow.lastIpcObject : null
    readonly property bool isFullscreen: activeWindow && activeWindow.wayland ? activeWindow.wayland.fullscreen : false

    readonly property var excludedClasses: [
        "firefox", "librewolf", "zen", "chromium", "google-chrome",
        "brave-browser", "code", "code-url-handler", "vesktop", "discord"
    ]

    function isExcluded(hypr) {
        var cls = (hypr.wayland ? hypr.wayland.appId : "").toLowerCase()
        return excludedClasses.indexOf(cls) !== -1
    }

    readonly property int titlebarHeight: 26
    readonly property int gripThickness: 6
    readonly property int gripCorner: 14

    readonly property real winX: (ipc && ipc.at) ? ipc.at[0] : 0
    readonly property real winY: (ipc && ipc.at) ? ipc.at[1] : 0
    readonly property real winW: (ipc && ipc.size) ? ipc.size[0] : 0
    readonly property real winH: (ipc && ipc.size) ? ipc.size[1] : 0

    readonly property var scr: {
        var scrs = Quickshell.screens
        for (var i = 0; i < scrs.length; i++) {
            if (activeWindow && Hyprland.monitorFor(scrs[i]) === activeWindow.monitor) return scrs[i]
        }
        return scrs.length > 0 ? scrs[0] : null
    }
    screen: scr

    WlrLayershell.namespace: "quickshell:windeco-active"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    exclusiveZone: 0

    visible: !isFullscreen &&
    activeWindow !== null &&
    !isExcluded(activeWindow) &&
    !!activeWindow.workspace && activeWindow.workspace.active &&
    !!ipc && !!ipc.at && !!ipc.size &&
    scr !== null

    implicitWidth: winW + gripThickness * 2
    implicitHeight: titlebarHeight + winH + gripThickness * 2

    anchors.top: true
    anchors.left: true
    margins.left: winX - (scr ? scr.x : 0) - gripThickness
    margins.top: Math.max(0, winY - (scr ? scr.y : 0) - titlebarHeight - gripThickness)

    readonly property real localWinLeft: gripThickness
    readonly property real localWinTop: titlebarHeight + gripThickness
    readonly property real localWinRight: localWinLeft + winW
    readonly property real localWinBottom: localWinTop + winH

    // Safety net to keep active window coordinates synced
    Connections {
        target: Hyprland
        function onRawEvent(event) { Hyprland.refreshToplevels() }
    }
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: Hyprland.refreshToplevels()
    }

    // ---- Click-passthrough mask ----
    mask: Region {
        x: root.localWinLeft; y: 0
        width: root.winW; height: root.titlebarHeight

        Region {
            x: root.localWinLeft + root.gripCorner/2
            y: root.localWinTop - root.gripThickness/2
            width: root.winW - root.gripCorner
            height: root.gripThickness
        }
        Region {
            x: root.localWinLeft + root.gripCorner/2
            y: root.localWinBottom - root.gripThickness/2
            width: root.winW - root.gripCorner
            height: root.gripThickness
        }
        Region {
            x: root.localWinRight - root.gripThickness/2
            y: root.localWinTop + root.gripCorner/2
            width: root.gripThickness
            height: root.winH - root.gripCorner
        }
        Region {
            x: root.localWinLeft - root.gripThickness/2
            y: root.localWinTop + root.gripCorner/2
            width: root.gripThickness
            height: root.winH - root.gripCorner
        }
        Region {
            x: root.localWinLeft - root.gripThickness/2
            y: root.localWinTop - root.gripThickness/2
            width: root.gripCorner; height: root.gripCorner
        }
        Region {
            x: root.localWinRight - root.gripThickness/2
            y: root.localWinTop - root.gripThickness/2
            width: root.gripCorner; height: root.gripCorner
        }
        Region {
            x: root.localWinLeft - root.gripThickness/2
            y: root.localWinBottom - root.gripThickness/2
            width: root.gripCorner; height: root.gripCorner
        }
        Region {
            x: root.localWinRight - root.gripThickness/2
            y: root.localWinBottom - root.gripThickness/2
            width: root.gripCorner; height: root.gripCorner
        }
    }

    // ---- Titlebar ----
    Rectangle {
        x: root.localWinLeft
        y: 0
        width: root.winW
        height: root.titlebarHeight
        radius: 6
        color: "#1e1e1e"

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            // Close button -> hl.dsp.window.close()
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

            // Minimize button -> shifts to special workspace
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

            // Fullscreen (left) / Float (right) -> hl.dsp.window.fullscreen({ mode = 0 })
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
        }
    }

    // ---- Resize grips ----
    function beginDrag(ma) {
        ma.startW = root.winW; ma.startH = root.winH
        ma.startX = root.winX; ma.startY = root.winY
        var g = ma.mapToGlobal(ma.mouseX, ma.mouseY)
        ma.pressGX = g.x; ma.pressGY = g.y
        ma.curW = ma.startW; ma.curH = ma.startH
        ma.curX = ma.startX; ma.curY = ma.startY
    }

    function updateDrag(ma, dxSign, dySign, moveX, moveY) {
        var g = ma.mapToGlobal(ma.mouseX, ma.mouseY)
        var totalDX = g.x - ma.pressGX
        var totalDY = g.y - ma.pressGY
        var minSize = 40

        var targetW = dxSign !== 0 ? Math.max(minSize, ma.startW + dxSign * totalDX) : ma.startW
        var targetH = dySign !== 0 ? Math.max(minSize, ma.startH + dySign * totalDY) : ma.startH

        var deltaW = targetW - ma.curW
        var deltaH = targetH - ma.curH
        if (deltaW !== 0 || deltaH !== 0) {
            Hyprland.dispatch('hl.dsp.window.resize({dx = ' + deltaW + ', dy = ' + deltaH + ', window = "address:' + root.activeWindow.address + '"})')
            ma.curW = targetW; ma.curH = targetH
        }

        var targetX = moveX ? (ma.startX - (targetW - ma.startW)) : ma.startX
        var targetY = moveY ? (ma.startY - (targetH - ma.startH)) : ma.startY
        var moveDX = targetX - ma.curX
        var moveDY = targetY - ma.curY
        if (moveDX !== 0 || moveDY !== 0) {
            Hyprland.dispatch('hl.dsp.window.move({dx = ' + moveDX + ', dy = ' + moveDY + ', window = "address:' + root.activeWindow.address + '"})')
            ma.curX = targetX; ma.curY = targetY
        }
    }

    // North grip
    MouseArea {
        x: root.localWinLeft + root.gripCorner/2; y: root.localWinTop - root.gripThickness/2
        width: root.winW - root.gripCorner; height: root.gripThickness
        hoverEnabled: true; cursorShape: Qt.SizeVerCursor
        property real pressGX: 0; property real pressGY: 0
        property real startW: 0; property real startH: 0; property real startX: 0; property real startY: 0
        property real curW: 0; property real curH: 0; property real curX: 0; property real curY: 0
        onPressed: root.beginDrag(this)
        onPositionChanged: if (pressed) root.updateDrag(this, 0, -1, false, true)
    }
    // South grip
    MouseArea {
        x: root.localWinLeft + root.gripCorner/2; y: root.localWinBottom - root.gripThickness/2
        width: root.winW - root.gripCorner; height: root.gripThickness
        hoverEnabled: true; cursorShape: Qt.SizeVerCursor
        property real pressGX: 0; property real pressGY: 0
        property real startW: 0; property real startH: 0; property real startX: 0; property real startY: 0
        property real curW: 0; property real curH: 0; property real curX: 0; property real curY: 0
        onPressed: root.beginDrag(this)
        onPositionChanged: if (pressed) root.updateDrag(this, 0, 1, false, false)
    }
    // East grip
    MouseArea {
        x: root.localWinRight - root.gripThickness/2; y: root.localWinTop + root.gripCorner/2
        width: root.gripThickness; height: root.winH - root.gripCorner
        hoverEnabled: true; cursorShape: Qt.SizeHorCursor
        property real pressGX: 0; property real pressGY: 0
        property real startW: 0; property real startH: 0; property real startX: 0; property real startY: 0
        property real curW: 0; property real curH: 0; property real curX: 0; property real curY: 0
        onPressed: root.beginDrag(this)
        onPositionChanged: if (pressed) root.updateDrag(this, 1, 0, false, false)
    }
    // West grip
    MouseArea {
        x: root.localWinLeft - root.gripThickness/2; y: root.localWinTop + root.gripCorner/2
        width: root.gripThickness; height: root.winH - root.gripCorner
        hoverEnabled: true; cursorShape: Qt.SizeHorCursor
        property real pressGX: 0; property real pressGY: 0
        property real startW: 0; property real startH: 0; property real startX: 0; property real startY: 0
        property real curW: 0; property real curH: 0; property real curX: 0; property real curY: 0
        onPressed: root.beginDrag(this)
        onPositionChanged: if (pressed) root.updateDrag(this, -1, 0, true, false)
    }
    // NW grip
    MouseArea {
        x: root.localWinLeft - root.gripThickness/2; y: root.localWinTop - root.gripThickness/2
        width: root.gripCorner; height: root.gripCorner
        hoverEnabled: true; cursorShape: Qt.SizeFDiagCursor
        property real pressGX: 0; property real pressGY: 0
        property real startW: 0; property real startH: 0; property real startX: 0; property real startY: 0
        property real curW: 0; property real curH: 0; property real curX: 0; property real curY: 0
        onPressed: root.beginDrag(this)
        onPositionChanged: if (pressed) root.updateDrag(this, -1, -1, true, true)
    }
    // NE grip
    MouseArea {
        x: root.localWinRight - root.gripThickness/2; y: root.localWinTop - root.gripThickness/2
        width: root.gripCorner; height: root.gripCorner
        hoverEnabled: true; cursorShape: Qt.SizeBDiagCursor
        property real pressGX: 0; property real pressGY: 0
        property real startW: 0; property real startH: 0; property real startX: 0; property real startY: 0
        property real curW: 0; property real curH: 0; property real curX: 0; property real curY: 0
        onPressed: root.beginDrag(this)
        onPositionChanged: if (pressed) root.updateDrag(this, 1, -1, false, true)
    }
    // SW grip
    MouseArea {
        x: root.localWinLeft - root.gripThickness/2; y: root.localWinBottom - root.gripThickness/2
        width: root.gripCorner; height: root.gripCorner
        hoverEnabled: true; cursorShape: Qt.SizeBDiagCursor
        property real pressGX: 0; property real pressGY: 0
        property real startW: 0; property real startH: 0; property real startX: 0; property real startY: 0
        property real curW: 0; property real curH: 0; property real curX: 0; property real curY: 0
        onPressed: root.beginDrag(this)
        onPositionChanged: if (pressed) root.updateDrag(this, -1, 1, true, false)
    }
    // SE grip
    MouseArea {
        x: root.localWinRight - root.gripThickness/2; y: root.localWinBottom - root.gripThickness/2
        width: root.gripCorner; height: root.gripCorner
        hoverEnabled: true; cursorShape: Qt.SizeFDiagCursor
        property real pressGX: 0; property real pressGY: 0
        property real startW: 0; property real startH: 0; property real startX: 0; property real startY: 0
        property real curW: 0; property real curH: 0; property real curX: 0; property real curY: 0
        onPressed: root.beginDrag(this)
        onPositionChanged: if (pressed) root.updateDrag(this, 1, 1, false, false)
    }
}
