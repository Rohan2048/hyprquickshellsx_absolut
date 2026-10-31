import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Theme"
import "../Services"
import "../Widgets"
import "../Bar/modules"

// Live preview of a bar preset: a mock screen with a dummy of every mini bar (same glass panel, modules,
// scale, roundness, size, alignment, background). It is only a picture (nothing real is created) unless
// `editable` is on, and then it is also where you arrange the icons of the selected bar:
//
//   - the mock is the real screen's shape, at the real pixel scale (Fit / 50% / 100% zoom), so what you
//     see is what the bar will do. Icons sit wherever you put them (px from the start of the bar), with
//     free room between them: edge to edge bars are not tied to either end.
//   - drag an icon anywhere along the bar. It may go between icons or into free space, never on top of
//     one: overlapping turns it translucent red (a tint the size of the icon) and, on release, it is
//     placed at the nearest valid place.
//   - icons from the "+ Add" chips can be dragged in the same way (beginExternal / updateExternal /
//     endExternal).
//   Nothing is recomputed while dragging except "does it overlap": the other icons stay put and the
//   layout is committed once, on release.
//
//   bars        array of mini bar objects (see Services/BarPresets.qml)
//   sel         index of the highlighted bar (-1 = none); clicking a bar emits barClicked(index)
//   editable    allow dragging the icons of the selected bar
//   placed(barIndex, id, pos, all)   an icon was dropped at `pos`; `all` = every icon's place
Item {
    id: pv

    property var bars: []
    property int sel: -1
    property bool editable: false
    property string selModule: ""
    signal barClicked(int index)
    signal placed(int barIndex, string id, real pos, var all)

    // 0 = fit the panel, otherwise a real scale (0.5 = half size)
    property real zoom: 0
    readonly property real viewH: pv.editable ? 340 : mock.height + 4
    readonly property real fitW: pv.editable ? Math.max(200, pv.width - 2) : Math.min(400, Math.max(200, pv.width - 2))

    implicitHeight: (pv.editable ? zoomRow.height + 6 : 0) + pv.viewH + 6

    readonly property string dir: "file://" + Quickshell.env("HOME") + "/.config/icons/"
    // the mock is the real screen, so lengths in px are real
    readonly property real realW: Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1920
    readonly property real realH: Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1080
    readonly property real vw: pv.realW
    readonly property real vh: pv.realH
    readonly property real f: (pv.zoom > 0 && pv.editable) ? pv.zoom : Math.min(1, pv.fitW / pv.vw)
    readonly property var actionIds: ["launcher", "settings", "lock", "commands", "shortcuts", "overview", "display", "schedule"]
    readonly property real minGap: 2          // least room between two icons

    // drag state (one drag at a time)
    property int dragBar: -1
    property string dragId: ""
    property real dragPos: 0                  // start of the dragged icon along its bar (content units)
    property string extId: ""                 // an icon being dragged in from the Add chips

    onSelChanged: pv.selModule = ""

    function barItem(i) { return barRep.itemAt(i) }
    function beginExternal(id, sp) {
        if (pv.sel < 0) return
            pv.extId = id
            pv.updateExternal(sp)
    }
    function updateExternal(sp) { const b = pv.barItem(pv.sel); if (b && pv.extId !== "") b.extUpdate(sp) }
    function endExternal(sp) {
        const b = pv.barItem(pv.sel)
        if (b && pv.extId !== "") { b.extUpdate(sp); b.extCommit() }
        pv.extId = ""
    }
    // click on an Add chip while the bar is free: put it at the first free place at the end
    function addAtEnd(id) {
        const b = pv.barItem(pv.sel)
        if (b) b.addAtEnd(id)
    }

    Row {
        id: zoomRow
        visible: pv.editable
        anchors.right: parent.right
        spacing: 6
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Zoom"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }
        GlassButton { text: "Fit"; implicitHeight: 24; active: pv.zoom === 0; onClicked: pv.zoom = 0 }
        GlassButton { text: "50%"; implicitHeight: 24; active: pv.zoom === 0.5; onClicked: pv.zoom = 0.5 }
        GlassButton { text: "100%"; implicitHeight: 24; active: pv.zoom === 1; onClicked: pv.zoom = 1 }
    }

    Flickable {
        id: view
        anchors.top: parent.top
        anchors.topMargin: pv.editable ? zoomRow.height + 6 : 0
        anchors.left: parent.left
        anchors.right: parent.right
        height: pv.viewH
        clip: true
        contentWidth: Math.max(width, mock.width)
        contentHeight: Math.max(height, mock.height)
        interactive: pv.editable && pv.zoom !== 0 && pv.dragId === "" && pv.extId === ""
        boundsBehavior: Flickable.StopAtBounds

        Rectangle {
            id: mock
            width: pv.vw * pv.f
            height: pv.vh * pv.f
            x: Math.max(0, (view.width - width) / 2)
            y: pv.editable ? Math.max(0, (view.height - height) / 2) : 0
            radius: 8
            color: Theme.pillOffBg
            border.width: 1
            border.color: Theme.borderMuted
            clip: true

            Item {
                id: world
                width: pv.vw
                height: pv.vh
                scale: pv.f
                transformOrigin: Item.TopLeft

                // clicking empty screen deselects the icon
                MouseArea { anchors.fill: parent; onClicked: pv.selModule = "" }

                Repeater {
                    id: barRep
                    model: pv.bars.length
                    delegate: Item {
                        id: mb
                        required property int index

                        readonly property var b: pv.bars[mb.index] || ({})
                        readonly property string edge: b.edge || "bottom"
                        readonly property bool vert: edge === "left" || edge === "right"
                        readonly property real sc: (b.scalePct || 100) / 100
                        readonly property real baseT: vert ? 48 : Theme.barHeight
                        readonly property real thick: baseT * sc
                        readonly property bool docked: b.autohide === false
                        readonly property bool fill: b.sizeMode === "fill"
                        readonly property bool fixed: b.sizeMode === "fixed"
                        readonly property bool flush: docked && fill
                        readonly property real edgeGap: flush ? 0 : Theme.gapSm
                        readonly property real uLen: vert ? pv.vh : pv.vw
                        readonly property real maxLen: fill ? uLen
                        : (fixed ? Math.min(b.lengthPx || 600, uLen) : uLen - Theme.gapMd * 1.5)

                        // ---------------- icon layout ----------------
                        readonly property var ids: b.modules || []
                        readonly property bool free: !!b.places
                        // lengths of the icons along the bar, reported by the icons themselves
                        property var lenMap: ({})
                        function reportLen(id, len) {
                            if (id === "" || lenMap[id] === len) return
                                const m = Object.assign({}, lenMap)
                                m[id] = len
                                lenMap = m
                        }
                        function lenOf(id) { const v = lenMap[id]; return v === undefined ? 0 : v }
                        function gapFor(len) { return 2 * Math.min(1, len / 12) }

                        // flowing bars: one after another, like the real bar
                        readonly property real appsStretch: (!free && fill && ids.indexOf("apps") >= 0)
                        ? Math.max(0, contentMain - flowNatural) : 0
                        readonly property real flowNatural: {
                            let acc = 0
                            for (let i = 0; i < ids.length; i++) {
                                const l = lenOf(ids[i])
                                if (l > 0) acc += (acc > 0 ? gapFor(l) : 0) + l
                            }
                            return acc
                        }
                        readonly property var flowStarts: {
                            const pos = {}
                            let acc = 0
                            for (let i = 0; i < ids.length; i++) {
                                const l = lenOf(ids[i]) + (ids[i] === "apps" ? appsStretch : 0)
                                if (l > 0) { const g = acc > 0 ? gapFor(l) : 0; pos[ids[i]] = acc + g; acc += g + l }
                                else pos[ids[i]] = acc
                            }
                            const lead = (fill || fixed) ? Math.max(0, (contentMain - acc) / 2) : 0
                            if (lead > 0) for (const k in pos) pos[k] += lead
                                return pos
                        }
                        // free bars: where each icon was put
                        readonly property real freeNatural: {
                            let end = 0
                            for (let i = 0; i < ids.length; i++) {
                                const l = lenOf(ids[i])
                                const p = b.places ? b.places[ids[i]] : undefined
                                if (l > 0 && p !== undefined) end = Math.max(end, clampMain(p, l) + l)
                            }
                            return end
                        }
                        readonly property real natural: free ? freeNatural : flowNatural

                        readonly property real panelLen: (fill || fixed) ? maxLen
                        : Math.min((natural + Theme.gapMd * 2) * sc, maxLen)
                        readonly property real contentMain: (fill || fixed) ? Math.max(0, panelLen / sc - Theme.gapMd * 2) : natural
                        readonly property real mainPos: {
                            const m = (b.offset || 0) + (fill ? 0 : Theme.gapMd * 0.75)
                            if (b.align === "start") return m
                                if (b.align === "end") return Math.max(0, uLen - panelLen - m)
                                    return (uLen - panelLen) / 2
                        }

                        // furthest an icon of length `len` may start: fill / fixed bars are bounded, fit bars grow
                        function limitMax(len) { return (fill || fixed) ? Math.max(0, contentMain - len) : 100000 }
                        function clampMain(p, len) { return Math.max(0, Math.min(p, limitMax(len))) }
                        function startOf(id) {
                            if (free) {
                                const v = b.places[id]
                                return v !== undefined ? clampMain(v, lenOf(id)) : freeNatural
                            }
                            const v = flowStarts[id]
                            return v === undefined ? 0 : v
                        }
                        function snapshot(skip) {
                            const m = {}
                            for (let i = 0; i < ids.length; i++)
                                if (ids[i] !== skip) m[ids[i]] = Math.round(startOf(ids[i]))
                                    return m
                        }

                        // ---- the overlap rule ----
                        function conflicts(skip, p, len) {
                            for (let i = 0; i < ids.length; i++) {
                                const id = ids[i]
                                if (id === skip) continue
                                    const l = lenOf(id)
                                    if (l <= 0) continue
                                        const q = startOf(id)
                                        if (p < q + l + pv.minGap && q < p + len + pv.minGap) return true
                            }
                            return false
                        }
                        // the closest place to `p` where `len` fits between / beside the others (-1 = no room)
                        function nearestValid(skip, p, len) {
                            const lim = limitMax(len)
                            const cand = [Math.max(0, Math.min(p, lim)), 0]
                            for (let i = 0; i < ids.length; i++) {
                                const id = ids[i]
                                if (id === skip) continue
                                    const l = lenOf(id)
                                    if (l <= 0) continue
                                        const q = startOf(id)
                                        cand.push(q + l + pv.minGap, q - len - pv.minGap)
                            }
                            let best = -1, bd = 1e9
                            for (let k = 0; k < cand.length; k++) {
                                const c = cand[k]
                                if (c < 0 || c > lim || conflicts(skip, c, len)) continue
                                    const d = Math.abs(c - p)
                                    if (d < bd) { bd = d; best = c }
                            }
                            return best
                        }

                        // ---- an icon dragged in from the Add chips ----
                        property real extPos: 0
                        property bool extOver: false
                        readonly property bool extActive: pv.extId !== "" && pv.sel === mb.index
                        readonly property real extLen: extLd.item ? (vert ? extLd.item.implicitHeight : extLd.item.implicitWidth) : 24
                        readonly property bool extBad: extActive && extOver && conflicts("", extPos, extLen)
                        function extUpdate(sp) {
                            const pt = absLayer.mapFromItem(null, sp.x, sp.y)
                            const m = vert ? pt.y : pt.x
                            const c = vert ? pt.x : pt.y
                            extPos = Math.max(0, Math.min(m - extLen / 2, limitMax(extLen)))
                            const reach = (fill || fixed) ? contentMain + baseT : natural + 260
                            extOver = c > -baseT * 0.6 && c < baseT * 1.6 && m > -baseT && m < reach
                        }
                        function extCommit() {
                            if (!extOver || pv.extId === "") return
                                const fin = extBad ? nearestValid("", extPos, extLen) : extPos
                                if (fin < 0) return
                                    pv.placed(mb.index, pv.extId, Math.round(fin), snapshot(""))
                        }
                        function addAtEnd(id) {
                            const fin = nearestValid("", 100000, 28)
                            pv.placed(mb.index, id, Math.round(Math.max(0, fin < 0 ? natural + pv.minGap : fin)), snapshot(""))
                        }

                        width: vert ? thick : panelLen
                        height: vert ? panelLen : thick
                        x: vert ? (edge === "left" ? edgeGap : pv.vw - thick - edgeGap) : mainPos
                        y: !vert ? (edge === "top" ? edgeGap : pv.vh - thick - edgeGap) : mainPos

                        // what the modules in this dummy bar read instead of the real bar's config
                        QtObject {
                            id: pcfg
                            readonly property bool vertical: mb.vert
                            readonly property real thickness: mb.baseT
                        }

                        function compFor(id) {
                            switch (id) {
                                case "power": return cPower
                                case "music": return cMusic
                                case "apps": return cApps
                                case "wifi": return cWifi
                                case "bluetooth": return cBt
                                case "volume": return cVol
                                case "battery": return cBat
                                case "clock": return cClock
                                case "stopwatch": return cStop
                                case "timer": return cTimer
                                case "bell": return cBell
                                case "workspaces": return cWs
                            }
                            return pv.actionIds.indexOf(id) >= 0 ? cAction : null
                        }

                        // a click on the bar selects it (under the icons, so they still get their own presses)
                        MouseArea { anchors.fill: parent; onClicked: pv.barClicked(mb.index) }

                        GlassPanel {
                            role: "bar"
                            anchors.fill: parent
                            bare: mb.b.bg === "transparent"
                            radius: mb.flush ? 0 : (mb.thick / 2) * (mb.b.roundnessPct === undefined ? 100 : mb.b.roundnessPct) / 100

                            Item {
                                id: absLayer
                                anchors.centerIn: parent
                                width: mb.vert ? mb.baseT : mb.contentMain
                                height: mb.vert ? mb.contentMain : mb.baseT
                                scale: mb.sc

                                Repeater {
                                    // the COUNT is the model: a drop edits the layout and must not rebuild the icons
                                    model: mb.ids.length
                                    delegate: Item {
                                        id: sl
                                        required property int index
                                        readonly property string mid: mb.ids[sl.index] || ""
                                        readonly property real len: ld.item ? (mb.vert ? ld.item.implicitHeight : ld.item.implicitWidth) : 0
                                        readonly property real stretch: (sl.mid === "apps") ? mb.appsStretch : 0
                                        readonly property bool dragging: pv.dragBar === mb.index && pv.dragId === sl.mid
                                        readonly property bool picked: pv.sel === mb.index && pv.selModule === sl.mid
                                        readonly property bool bad: sl.dragging && mb.conflicts(sl.mid, pv.dragPos, sl.len)

                                        width: mb.vert ? mb.baseT : sl.len + sl.stretch
                                        height: mb.vert ? sl.len + sl.stretch : mb.baseT
                                        readonly property real main: sl.dragging ? pv.dragPos : mb.startOf(sl.mid)
                                        x: mb.vert ? 0 : sl.main
                                        y: mb.vert ? sl.main : 0
                                        z: sl.dragging ? 10 : 1
                                        Behavior on x { enabled: !sl.dragging && pv.editable; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                        Behavior on y { enabled: !sl.dragging && pv.editable; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                                        onLenChanged: mb.reportLen(sl.mid, sl.len)
                                        Component.onCompleted: mb.reportLen(sl.mid, sl.len)

                                        Loader {
                                            id: ld
                                            anchors.centerIn: parent
                                            width: (sl.stretch > 0 && !mb.vert) ? sl.width : (item ? item.implicitWidth : 0)
                                            height: (sl.stretch > 0 && mb.vert) ? sl.height : (item ? item.implicitHeight : 0)
                                            sourceComponent: mb.compFor(sl.mid)
                                            onLoaded: { if (item && item.action !== undefined) item.action = sl.mid }
                                        }

                                        // the icon you picked / are dragging
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Theme.radiusSm
                                            color: "transparent"
                                            border.width: (sl.picked || sl.dragging) ? 1 : 0
                                            border.color: Theme.accentActive
                                        }
                                        // overlapping another icon: a translucent red tint, exactly the icon's size
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Theme.radiusSm
                                            color: Qt.rgba(1, 0.15, 0.15, 0.42)
                                            visible: sl.bad
                                        }

                                        MouseArea {
                                            id: sm
                                            anchors.fill: parent
                                            enabled: pv.editable && pv.sel === mb.index
                                            preventStealing: true
                                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                            property real grab: 0
                                            property bool moved: false
                                            function mainOf(m) { const pt = absLayer.mapFromItem(sm, m.x, m.y); return mb.vert ? pt.y : pt.x }
                                            onPressed: (m) => {
                                                sm.grab = sm.mainOf(m) - mb.startOf(sl.mid)
                                                sm.moved = false
                                                pv.selModule = sl.mid
                                            }
                                            onPositionChanged: (m) => {
                                                if (!pressed) return
                                                    const want = sm.mainOf(m) - sm.grab
                                                    if (!sm.moved) {
                                                        if (Math.abs(want - mb.startOf(sl.mid)) < 3) return
                                                            sm.moved = true
                                                            pv.dragBar = mb.index
                                                            pv.dragId = sl.mid
                                                    }
                                                    pv.dragPos = Math.max(0, Math.min(want, mb.limitMax(sl.len)))
                                            }
                                            function finish() {
                                                if (!sm.moved) return
                                                    sm.moved = false
                                                    const id = sl.mid
                                                    const bi = mb.index
                                                    const bad = mb.conflicts(id, pv.dragPos, sl.len)
                                                    const fin = bad ? mb.nearestValid(id, pv.dragPos, sl.len) : pv.dragPos
                                                    pv.dragBar = -1
                                                    pv.dragId = ""
                                                    if (fin < 0) return                 // no room anywhere: it stays where it was
                                                        pv.placed(bi, id, Math.round(fin), mb.snapshot(id))
                                            }
                                            onReleased: sm.finish()
                                            onCanceled: sm.finish()
                                        }
                                    }
                                }

                                // the icon being dragged in from the Add chips (drawn like the real one)
                                Item {
                                    visible: mb.extActive
                                    z: 20
                                    width: mb.vert ? mb.baseT : mb.extLen
                                    height: mb.vert ? mb.extLen : mb.baseT
                                    x: mb.vert ? 0 : mb.extPos
                                    y: mb.vert ? mb.extPos : 0
                                    opacity: mb.extOver ? 1 : 0.55
                                    Loader {
                                        id: extLd
                                        anchors.centerIn: parent
                                        sourceComponent: mb.extActive ? mb.compFor(pv.extId) : null
                                        onLoaded: { if (item && item.action !== undefined) item.action = pv.extId }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.radiusSm
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.accentActive
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.radiusSm
                                        color: Qt.rgba(1, 0.15, 0.15, 0.42)
                                        visible: mb.extBad
                                    }
                                }
                            }
                        }

                        // selection ring
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -4
                            radius: Theme.radiusSm + 4
                            color: "transparent"
                            border.width: 2
                            border.color: Theme.accentActive
                            visible: pv.sel === mb.index
                        }

                        Component { id: cPower; ControlIcon { cfg: pcfg; iconId: "power"; iconSource: pv.dir + "power-btn.svg"; iconSize: 16 } }
                        Component {
                            id: cMusic
                            ControlIcon {
                                cfg: pcfg
                                iconId: "music"
                                iconSource: mb.vert ? pv.dir + "music-placeholder.png" : ""
                                text: mb.vert ? "" : "Now playing"
                            }
                        }
                        Component {
                            id: cApps
                            Item {
                                implicitWidth: mb.vert ? mb.baseT : appsGrid.implicitWidth + 6
                                implicitHeight: mb.vert ? appsGrid.implicitHeight + 6 : mb.baseT
                                Grid {
                                    id: appsGrid
                                    anchors.left: mb.vert ? undefined : parent.left
                                    anchors.top: mb.vert ? parent.top : undefined
                                    anchors.horizontalCenter: mb.vert ? parent.horizontalCenter : undefined
                                    anchors.verticalCenter: mb.vert ? undefined : parent.verticalCenter
                                    anchors.leftMargin: 3
                                    anchors.topMargin: 3
                                    columns: mb.vert ? 1 : 4
                                    spacing: 4
                                    Repeater {
                                        model: 4
                                        delegate: Rectangle {
                                            width: 30; height: 30
                                            radius: Theme.radiusSm
                                            color: Theme.hoverBg
                                            Rectangle { anchors.centerIn: parent; width: 16; height: 16; radius: 3; color: Theme.foreground; opacity: 0.55 }
                                        }
                                    }
                                }
                            }
                        }
                        Component { id: cWifi; ControlIcon { cfg: pcfg; iconId: "wifi"; iconSource: pv.dir + "wifion.svg" } }
                        Component { id: cBt; ControlIcon { cfg: pcfg; iconId: "bluetooth"; iconSource: pv.dir + "bluetooth-icon.svg" } }
                        Component { id: cVol; ControlIcon { cfg: pcfg; iconId: "volume"; iconSource: pv.dir + "sound.svg" } }
                        Component { id: cBat; ControlIcon { cfg: pcfg; iconId: "battery-high"; iconSource: pv.dir + "high-battery.svg"; iconSize: 20; text: "80%" } }
                        Component {
                            id: cClock
                            Item {
                                implicitWidth: mb.vert ? mb.baseT : clockCol.implicitWidth + 16
                                implicitHeight: mb.vert ? clockCol.implicitHeight + 12 : mb.baseT
                                Column {
                                    id: clockCol
                                    anchors.centerIn: parent
                                    spacing: 0
                                    Text { text: mb.vert ? "12" : "12:00"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                                    Text { visible: mb.vert; text: "00"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                                    Text { text: mb.vert ? "Sat" : "Sat 17 Oct"; color: Theme.isDark ? Qt.lighter(Theme.color3, 1.5) : Qt.darker(Theme.color3, 2.8); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                                    Text { visible: mb.vert; text: "17"; color: Theme.isDark ? Qt.lighter(Theme.color3, 1.5) : Qt.darker(Theme.color3, 2.8); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                                }
                            }
                        }
                        Component { id: cStop; TimeChip { cfg: pcfg; text: "00:00"; templateText: "00:00" } }
                        Component { id: cTimer; TimeChip { cfg: pcfg; chip: true; text: "05:00"; templateText: "00:00" } }
                        Component { id: cBell; ControlIcon { cfg: pcfg; iconId: "bell"; iconSource: pv.dir + "bell.svg" } }
                        Component { id: cWs; WorkspacesTray { cfg: pcfg } }
                        Component { id: cAction; ActionButton { cfg: pcfg } }

                    }
                }
            }
        }
    }
}
