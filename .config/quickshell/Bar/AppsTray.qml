import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import "../Theme"
import "../Widgets"
import "../Services"
import "./modules"

Item {
    id: appsTray
    required property var bar
    required property var barScreen
    required property var tracking
    required property real maxLength

    readonly property alias hoveredEntry: taskbarList.hoveredEntry
    readonly property alias contextMenuEntry: taskbarList.contextMenuEntry

    readonly property bool vertical: bar.cfg.vertical
    readonly property bool fill: bar.fill
    readonly property bool hasWindows: ToplevelManager.toplevels.values.length > 0

    readonly property real pad: hasWindows ? 8 : 3
    readonly property real cell: Theme.barHeight
    readonly property real navSize: navLeft.visible ? (vertical ? navLeft.implicitHeight : navLeft.implicitWidth) : 0

    readonly property real contentMain: fill
    ? Math.max(0, maxLength - pad * 2)
    : Math.min(taskbarList.contentLength, Math.max(0, maxLength - pad * 2))
    readonly property real mainLength: contentMain + pad * 2

    implicitWidth: vertical ? bar.cfg.thickness : mainLength
    implicitHeight: vertical ? mainLength : bar.cfg.thickness
    width: implicitWidth
    height: implicitHeight

    Timer {
        id: syncTimer
        interval: 50
        onTriggered: taskbarList.syncGroupedApps()
    }

    Connections {
        target: ToplevelManager.toplevels
        function onValuesChanged() { syncTimer.restart() }
    }

    PanelWindow {
        id: sharedThumbPopup
        screen: barScreen
        exclusionMode: ExclusionMode.Ignore

        property bool shown: taskbarList.hoveredEntry !== null
        property bool alive: false
        visible: alive

        WlrLayershell.namespace: "quickshell:taskbar-thumb"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        property var lastEntry: null
        readonly property var currentEntry: taskbarList.hoveredEntry

        // Window (layer-shell surface) size. A surface resize is applied asynchronously by the
        // compositor, so resizing it in the same frame the content changes shows a stale-sized
        // buffer = tearing. Instead the window only ever GROWS ahead of the content, the glass
        // panel inside animates its own size (animW/animH). The window is NOT shrunk while the popup
        // is open (a late shrink + re-centre showed up as a second jump); it re-fits only while hidden.
        property int lockedWidth: 200
        property int lockedHeight: 120
        property real animW: 200
        property real animH: 120
        property bool snap: true      // true while closed: next open sizes everything instantly
        readonly property real gutter: 0     // was 30: a dead strip on the far side of the panel
        readonly property real edgeGap: 0    // px between bar and popup panel; a gap lets the pointer fall through to the desktop
        readonly property int fitWidth: appsTray.vertical ? panelWidth + gutter : panelWidth
        readonly property int fitHeight: appsTray.vertical ? actualContentHeight : actualContentHeight + gutter

        // Re-fit to the current group. Runs when the hovered app changes AND when the window count of the
        // hovered app changes while the popup is open (opening / closing windows).
        function refit() {
            if (!lastEntry) return
                // computed here from the primary values, not from fitWidth/fitHeight: those are separate
                // bindings that can still hold the old value when this runs from a change handler
                var fw = appsTray.vertical ? panelWidth + gutter : panelWidth
                var fh = appsTray.vertical ? actualContentHeight : actualContentHeight + gutter
                if (snap) {
                    lockedWidth = fw; lockedHeight = fh
                    animW = panelWidth; animH = actualContentHeight
                    snap = false
                } else {
                    lockedWidth = Math.max(lockedWidth, fw)
                    lockedHeight = Math.max(lockedHeight, fh)
                    animW = panelWidth; animH = actualContentHeight
                }
        }
        onCurrentEntryChanged: {
            if (currentEntry) { lastEntry = currentEntry; refit(); Qt.callLater(refit) }
        }
        // callLater: runs once, after every dependent binding has updated
        onPanelWidthChanged: if (!snap) Qt.callLater(refit)
        onActualContentHeightChanged: if (!snap) Qt.callLater(refit)

        implicitWidth: lockedWidth
        implicitHeight: lockedHeight

        anchors.top: appsTray.tracking.anchorTop
        anchors.bottom: appsTray.tracking.anchorBottom
        anchors.left: appsTray.tracking.anchorLeft
        anchors.right: appsTray.tracking.anchorRight
        margins.top: thumbPlace.marginTop
        margins.bottom: thumbPlace.marginBottom
        margins.left: thumbPlace.marginLeft
        margins.right: thumbPlace.marginRight

        readonly property var currentGroup: lastEntry ? lastEntry.modelData : null
        readonly property var currentWindows: currentGroup ? currentGroup.windows : []
        readonly property int thumbW: 200
        readonly property int thumbH: 120
        readonly property int thumbSpacing: 6
        readonly property int thumbCols: currentWindows.length > 0 ? Math.min(3, currentWindows.length) : 1
        readonly property var thumbRowsList: {
            var rows = []; var windows = currentWindows;
            for (var i = 0; i < windows.length; i += thumbCols) {
                rows.push(windows.slice(i, i + thumbCols))
            }
            return rows.reverse()
        }
        readonly property var thumbOrdered: {
            var o = []
            for (var i = 0; i < thumbRowsList.length; i++)
                for (var j = 0; j < thumbRowsList[i].length; j++) o.push(thumbRowsList[i][j])
                    return o
        }
        readonly property int actualContentHeight: Math.min((3 * thumbH) + (2 * thumbSpacing) + 8, (thumbRowsList.length * thumbH) + (Math.max(0, thumbRowsList.length - 1) * thumbSpacing) + 8)
        readonly property int panelWidth: (thumbCols * thumbW) + ((thumbCols - 1) * thumbSpacing) + 8

        onShownChanged: {
            if (shown) { closeTimer.stop(); alive = true }
            else { closeTimer.restart() }
        }
        Timer { id: closeTimer; interval: 260; onTriggered: { sharedThumbPopup.alive = false; sharedThumbPopup.snap = true } }

        GlassPanel {
            id: thumbPanelContainer
            width: sharedThumbPopup.animW
            height: sharedThumbPopup.animH
            Behavior on width { enabled: !sharedThumbPopup.snap; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on height { enabled: !sharedThumbPopup.snap; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            // Cross axis touches the bar side of the window (edgeGap, 0 = no dead strip between bar and
            // popup). Along axis is centred in the window, which PopupPlacement centres on the hovered icon.
            x: appsTray.vertical
            ? (appsTray.tracking.edge === "left" ? sharedThumbPopup.edgeGap : sharedThumbPopup.lockedWidth - width - sharedThumbPopup.edgeGap)
            : (sharedThumbPopup.lockedWidth - width) / 2
            y: appsTray.vertical
            ? (sharedThumbPopup.lockedHeight - height) / 2
            : (appsTray.tracking.edge === "top" ? sharedThumbPopup.edgeGap : sharedThumbPopup.lockedHeight - height - sharedThumbPopup.edgeGap)
            radius: Theme.radiusSm

            opacity: sharedThumbPopup.shown ? 1 : 0
            transform: Translate {
                x: appsTray.tracking.slideDirX * (sharedThumbPopup.shown ? 0 : 25)
                y: appsTray.tracking.slideDirY * (sharedThumbPopup.shown ? 0 : 25)
                Behavior on x { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                Behavior on y { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
            }
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Flickable {
                id: thumbFlickable
                anchors.fill: parent; anchors.margins: 4
                contentWidth: thumbContent.width; contentHeight: thumbContent.height
                clip: true; interactive: sharedThumbPopup.thumbRowsList.length > 3

                WheelHandler {
                    target: thumbFlickable
                    onWheel: (event) => {
                        var move = thumbFlickable.contentY - event.angleDelta.y
                        var max = thumbFlickable.contentHeight - thumbFlickable.height
                        thumbFlickable.contentY = Math.max(0, Math.min(max, move))
                    }
                }

                Grid {
                    id: thumbContent; width: thumbFlickable.width
                    columns: sharedThumbPopup.thumbCols; spacing: sharedThumbPopup.thumbSpacing
                    Repeater {
                        model: ScriptModel { values: sharedThumbPopup.thumbOrdered }
                        delegate: Rectangle {
                            id: thumbCell; required property var modelData; width: 200; height: 120
                            color: Theme.background; radius: Theme.radiusSm
                            border.color: cellMouse.containsMouse ? Theme.color1 : Theme.hoverBg
                            border.width: cellMouse.containsMouse ? 2 : 1
                            clip: true

                            ScreencopyView {
                                id: sv
                                anchors.fill: parent; anchors.margins: 4
                                captureSource: thumbCell.modelData
                                // Low-end CPUs: no layer. A cell streams only while hovered, or until its
                                // first frame has arrived; after that it just takes one snapshot per pulse.
                                live: (cellMouse.containsMouse || !sv.hasContent) && sharedThumbPopup.visible
                                Connections { target: sharedThumbPopup; function onCapture() { if (sv.hasContent) sv.captureFrame() } }
                            }

                            // Name strip: "App - window title", themed like the popups (preset fill + text colour)
                            Rectangle {
                                id: nameStrip
                                readonly property string appName: {
                                    var id = thumbCell.modelData.appId ?? ""
                                    var e = id !== "" ? DesktopEntries.heuristicLookup(id) : null
                                    return e ? e.name : id
                                }
                                readonly property string winTitle: thumbCell.modelData.title ?? ""
                                readonly property string label: winTitle === "" ? appName
                                : (appName === "" || winTitle.toLowerCase().indexOf(appName.toLowerCase()) !== -1 ? winTitle : appName + " - " + winTitle)
                                anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                                anchors.margins: 4
                                height: 20
                                radius: Theme.radiusSm
                                color: Theme.popupPaintBg
                                clip: true
                                ThemeFill { anchors.fill: parent; fill: Theme.popupFill; radius: parent.radius }
                                Text {
                                    anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6
                                    verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideRight
                                    text: nameStrip.label
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                }
                            }

                            MouseArea {
                                id: cellMouse; anchors.fill: parent; hoverEnabled: true
                                onContainsMouseChanged: sharedThumbPopup.innerHover += containsMouse ? 1 : -1
                                Component.onDestruction: if (containsMouse) sharedThumbPopup.innerHover -= 1
                                onClicked: { appsTray.bar.activateWindow(thumbCell.modelData); taskbarList.hoveredEntry = null }
                            }

                            Rectangle {
                                width: 18; height: 18; radius: 4; anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 4
                                color: closeMouse.containsMouse ? Theme.color1 : Qt.rgba(0, 0, 0, 0.4)
                                Text { anchors.centerIn: parent; text: "×"; color: "white"; font.bold: true }
                                MouseArea {
                                    id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: thumbCell.modelData.close()
                                    onContainsMouseChanged: sharedThumbPopup.innerHover += containsMouse ? 1 : -1
                                    Component.onDestruction: if (containsMouse) sharedThumbPopup.innerHover -= 1
                                }
                            }
                        }
                    }
                }
            }
        }

        signal capture()
        Timer {
            id: pulseTimer
            interval: 12000; repeat: true; running: sharedThumbPopup.visible; triggeredOnStart: true
            onTriggered: sharedThumbPopup.capture()
        }

        // Pointer-inside test for the popup. Done geometrically on mouse events (not from an input mask):
        // inside = within the panel rectangle on all four sides, or over a cell / close button.
        property int innerHover: 0       // cells / close buttons under the pointer
        property bool geomInside: false  // pointer inside the panel rectangle
        function updateInside() {
            var p = winHover.point.position, r = thumbPanelContainer
            geomInside = winHover.hovered
            && p.x >= r.x && p.x <= r.x + r.width
            && p.y >= r.y && p.y <= r.y + r.height
        }
        readonly property bool pointerInside: geomInside || innerHover > 0
        onPointerInsideChanged: {
            if (pointerInside) { hideDelay.stop(); appsTray.bar.isHovered = true }
            else { hideDelay.pendingHideEntry = taskbarList.hoveredEntry; hideDelay.restart() }
        }
        HoverHandler {
            id: winHover
            onHoveredChanged: sharedThumbPopup.updateInside()
            onPointChanged: sharedThumbPopup.updateInside()
        }
    }

    PopupPlacement {
        id: thumbPlace
        tracking: appsTray.tracking
        popup: sharedThumbPopup
        anchorItem: sharedThumbPopup.lastEntry
        smooth: false
        gap: 0
        clampToBar: false
    }

    PanelWindow {
        id: sharedMenuPopup
        screen: barScreen
        exclusionMode: ExclusionMode.Ignore

        property bool shown: taskbarList.contextMenuEntry !== null
        property bool alive: false
        visible: alive

        WlrLayershell.namespace: "quickshell:taskbar-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        color: "transparent"

        property var lastMenuEntry: null
        readonly property var currentEntry: taskbarList.contextMenuEntry

        onCurrentEntryChanged: {
            if (currentEntry) {
                lastMenuEntry = currentEntry
            }
        }

        implicitWidth: appsTray.vertical ? 140 : 130
        implicitHeight: menuColumn.implicitHeight + (appsTray.vertical ? 15 : 25)

        anchors.top: appsTray.tracking.anchorTop
        anchors.bottom: appsTray.tracking.anchorBottom
        anchors.left: appsTray.tracking.anchorLeft
        anchors.right: appsTray.tracking.anchorRight
        margins.top: menuPlace.marginTop
        margins.bottom: menuPlace.marginBottom
        margins.left: menuPlace.marginLeft
        margins.right: menuPlace.marginRight

        onShownChanged: {
            if (shown) { menuCloseTimer.stop(); alive = true }
            else { menuCloseTimer.restart() }
        }
        Timer { id: menuCloseTimer; interval: 250; onTriggered: sharedMenuPopup.alive = false }

        GlassPanel {
            anchors.fill: parent
            anchors.bottomMargin: appsTray.tracking.edge === "bottom" ? 10 : 0
            anchors.topMargin: appsTray.tracking.edge === "top" ? 10 : 0
            anchors.leftMargin: appsTray.tracking.edge === "left" ? 10 : 0
            anchors.rightMargin: appsTray.tracking.edge === "right" ? 10 : 0
            radius: Theme.radiusSm
            opacity: sharedMenuPopup.shown ? 1 : 0
            transform: Translate {
                x: appsTray.tracking.slideDirX * (sharedMenuPopup.shown ? 0 : 15)
                y: appsTray.tracking.slideDirY * (sharedMenuPopup.shown ? 0 : 15)
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
                Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutQuint } }
            }
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Column {
                id: menuColumn; anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top; anchors.margins: 7; spacing: 2
                Repeater {
                    model: [
                        { text: (sharedMenuPopup.lastMenuEntry && appsTray.bar.isMinimizedFake(sharedMenuPopup.lastMenuEntry.targetWindow) ? "Show" : "Minimize"), action: "toggle" },
                        { text: "Close All", action: "close" }
                    ]
                    delegate: Rectangle {
                        width: parent.width; height: 28; radius: Theme.radiusSm
                        color: mArea.containsMouse ? Theme.hoverBg : "transparent"
                        Text { anchors.centerIn: parent; width: parent.width; text: modelData.text; color: Theme.foreground; font.family: Theme.fontFamily; horizontalAlignment: Text.AlignHCenter }
                        MouseArea {
                            id: mArea; anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                var target = sharedMenuPopup.lastMenuEntry
                                if (!target) return
                                    if (modelData.action === "toggle") appsTray.bar.toggleMinimize(target.targetWindow)
                                        else appsTray.bar.closeAll(target.modelData.windows.slice())
                                            taskbarList.contextMenuEntry = null
                            }
                        }
                    }
                }
            }
        }
        HoverHandler {
            onHoveredChanged: {
                if (hovered) contextMenuHideDelay.stop()
                    else { contextMenuHideDelay.pendingHideEntry = taskbarList.contextMenuEntry; contextMenuHideDelay.restart() }
            }
        }
    }

    PopupPlacement {
        id: menuPlace
        tracking: appsTray.tracking
        popup: sharedMenuPopup
        anchorItem: sharedMenuPopup.lastMenuEntry
        smooth: false
        gap: 0
        clampToBar: false
    }

    ControlIcon {
        id: navLeft
        x: appsTray.vertical ? 0 : appsTray.pad
        y: appsTray.vertical ? appsTray.pad : 0
        visible: taskbarList.contentLength > appsTray.contentMain
        glyph: appsTray.vertical ? "▴" : "<"
        onActivated: {
            taskbarListAnim.to = Math.max(0, taskbarList.scrollPos - 200)
            taskbarListAnim.start()
        }
    }

    ListView {
        id: taskbarList
        orientation: appsTray.vertical ? ListView.Vertical : ListView.Horizontal
        clip: true; spacing: 4

        x: appsTray.vertical ? 0 : appsTray.pad + appsTray.navSize
        y: appsTray.vertical ? appsTray.pad + appsTray.navSize : 0
        width: appsTray.vertical ? appsTray.width : Math.max(0, appsTray.contentMain - appsTray.navSize * 2)
        height: appsTray.vertical ? Math.max(0, appsTray.contentMain - appsTray.navSize * 2) : appsTray.height

        property var appOrder: []
        property var groupedApps: []
        property var hoveredEntry: null
        property var pendingHoverEntry: null
        property var contextMenuEntry: null
        property var iconCache: ({})

        readonly property real contentLength: appsTray.vertical ? contentHeight : contentWidth
        readonly property real viewLength: appsTray.vertical ? height : width
        readonly property real scrollPos: appsTray.vertical ? contentY : contentX

        function syncGroupedApps() {
            var vals = ToplevelManager.toplevels.values
            var byAppId = {}
            for (var i = 0; i < vals.length; i++) {
                var id = vals[i].appId ?? "unknown"
                if (!byAppId[id]) byAppId[id] = []
                    byAppId[id].push(vals[i])
            }
            taskbarList.appOrder = taskbarList.appOrder.filter(function(id) { return byAppId[id] !== undefined })
            for (var id in byAppId) {
                if (taskbarList.appOrder.indexOf(id) === -1) taskbarList.appOrder.push(id)
            }
            taskbarList.groupedApps = taskbarList.appOrder.map(function(id) { return { appId: id, windows: byAppId[id] } })
        }

        Component.onCompleted: syncGroupedApps()
        model: ScriptModel { values: taskbarList.groupedApps; objectProp: "appId" }

        Timer { id: hoverDelay; interval: 200; onTriggered: taskbarList.hoveredEntry = taskbarList.pendingHoverEntry }
        Timer { id: hideDelay; interval: 250; property var pendingHideEntry: null; onTriggered: { if (taskbarList.hoveredEntry === pendingHideEntry && !bar.isTriggerHovered) taskbarList.hoveredEntry = null } }
        Timer { id: contextMenuHideDelay; interval: 250; property var pendingHideEntry: null; onTriggered: { if (taskbarList.contextMenuEntry === pendingHideEntry) taskbarList.contextMenuEntry = null } }

        function resolveIconCandidates(appId) {
            if (appId in taskbarList.iconCache) return taskbarList.iconCache[appId]
                var lower = appId.toLowerCase()
                var tail = appId.includes(".") ? appId.split(".").pop() : ""
                var names = [appId, lower, tail].filter(function(n) { return n !== "" })

                var candidates = []
                for (var i = 0; i < names.length; i++) {
                    var entry = DesktopEntries.heuristicLookup(names[i])
                    var icon = entry ? entry.icon : names[i]
                    var src = icon.startsWith("/") ? ("file://" + icon) : Quickshell.iconPath(icon, "")
                    if (src && candidates.indexOf(src) === -1) candidates.push(src)
                }

                taskbarList.iconCache[appId] = candidates
                return candidates
        }

        NumberAnimation {
            id: taskbarListAnim
            target: taskbarList
            property: appsTray.vertical ? "contentY" : "contentX"
            duration: 300; easing.type: Easing.OutQuart
        }

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                taskbarListAnim.stop()
                var delta = appsTray.vertical
                ? event.angleDelta.y
                : (event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y)
                var np = Math.max(0, Math.min(taskbarList.contentLength - taskbarList.viewLength, taskbarList.scrollPos - delta))
                if (appsTray.vertical) taskbarList.contentY = np
                    else taskbarList.contentX = np
            }
        }

        delegate: Item {
            id: taskDelegate
            required property var modelData
            readonly property bool groupActivated: modelData.windows.some(function(w) { return w.activated })
            readonly property var targetWindow: modelData.windows.find(function(w) { return w.activated }) ?? modelData.windows[0]
            implicitWidth: appsTray.vertical ? appsTray.bar.cfg.thickness : appsTray.cell
            implicitHeight: appsTray.cell

            Item {
                id: tile
                anchors.centerIn: parent
                width: appsTray.cell; height: appsTray.cell

                Rectangle {
                    anchors.fill: parent; radius: Theme.radiusSm
                    color: taskMouse.containsMouse ? Qt.rgba(Theme.hoverBg.r, Theme.hoverBg.g, Theme.hoverBg.b, 0.35)
                    : (groupActivated ? Qt.rgba(Theme.hoverBg.r, Theme.hoverBg.g, Theme.hoverBg.b, 0.18) : "transparent")
                }

                Loader {
                    anchors.centerIn: parent; width: 16; height: 16
                    property var themeKey: Theme.palette
                    sourceComponent: Item {
                        property var candidates: taskbarList.resolveIconCandidates(taskDelegate.modelData.appId ?? "")
                        property int candidateIndex: 0
                        IconImage {
                            anchors.fill: parent; visible: candidateIndex < candidates.length
                            source: visible ? candidates[candidateIndex] : ""
                            onStatusChanged: if (status === Image.Error) candidateIndex++
                        }
                        Rectangle {
                            anchors.fill: parent; radius: 3; visible: candidateIndex >= candidates.length; color: Theme.hoverBg
                            Text { anchors.centerIn: parent; text: (taskDelegate.modelData.appId ?? "?")[0].toUpperCase(); color: Theme.foreground; font.pixelSize: Theme.fs(10); font.bold: true }
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 2; spacing: 2
                    visible: modelData.windows.length > 1
                    Repeater {
                        model: Math.min(modelData.windows.length, 5)
                        delegate: Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.foreground }
                    }
                }

                Rectangle {
                    visible: modelData.windows.length > 5; width: 11; height: 11; radius: 3; color: Theme.color1
                    anchors.top: parent.top; anchors.right: parent.right
                    Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: Theme.fs(9); font.bold: true }
                }

                MouseArea {
                    id: taskMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            taskbarList.hoveredEntry = null
                            taskbarList.contextMenuEntry = (taskbarList.contextMenuEntry === taskDelegate) ? null : taskDelegate
                        } else {
                            appsTray.bar.activateWindow(taskDelegate.targetWindow)
                        }
                    }
                }
            }

            HoverHandler {
                onHoveredChanged: {
                    if (hovered) {
                        hideDelay.stop(); taskbarList.pendingHoverEntry = taskDelegate
                        if (taskbarList.hoveredEntry !== null) { hoverDelay.stop(); taskbarList.hoveredEntry = taskDelegate }
                        else hoverDelay.restart()
                    } else {
                        hoverDelay.stop()
                        if (taskbarList.hoveredEntry === taskDelegate) { hideDelay.pendingHideEntry = taskDelegate; hideDelay.restart() }
                    }
                }
            }
        }
    }

    ControlIcon {
        id: navRight
        x: appsTray.vertical ? 0 : appsTray.width - appsTray.pad - implicitWidth
        y: appsTray.vertical ? appsTray.height - appsTray.pad - implicitHeight : 0
        visible: taskbarList.contentLength > appsTray.contentMain
        glyph: appsTray.vertical ? "▾" : ">"
        onActivated: {
            taskbarListAnim.to = Math.min(taskbarList.contentLength - taskbarList.viewLength, taskbarList.scrollPos + 200)
            taskbarListAnim.start()
        }
    }
}
