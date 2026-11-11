import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Live preview of one popup, with its pieces draggable.
//
// The popup's real content (`content`, e.g. BatteryContent) is shown inside a stand-in panel, one copy per
// page, side by side. Every Widgets/PopupElement in it gets an outline:
//   drag the outline          moves the element (PopupSettings "layout", x / y in px)
//   drag a corner handle      scales the element around its centre -- always uniform, never stretched
// and the popup itself (the panel's own handles, outside the pieces):
//   right / bottom edge bar   the popup's width / height          (PopupSettings "size")
//   filled corner, bottom right   scales the whole popup           (PopupSettings "scales")
//   ring, top left            the popup's corner radius, slid along the diagonal (PopupSettings "radii")
// What you see here is what the popup shows, because it is the same content the popup uses.
// Clicks never reach the content (nothing in the preview switches turbo mode, devices ...).
Item {
    id: ed

    // small button of the floating toolbar over a selected piece
    component MiniBtn: Rectangle {
        id: mb
        property string label: ""
        property bool on: false
        signal tap()
        implicitWidth: Math.max(22, mbText.implicitWidth + 12)
        implicitHeight: 20
        radius: 5
        color: mb.on ? Theme.accentActive : Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
        border.color: mb.on ? Theme.foreground : Qt.rgba(1, 1, 1, 0.3)
        Text {
            id: mbText
            anchors.centerIn: parent
            text: mb.label
            color: mb.on ? Theme.textOnAccent : "white"
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm - 1
            font.bold: true
        }
        MouseArea { anchors.fill: parent; onClicked: mb.tap() }
    }

    property string popupId: ""
    property Component content: null
    property int pages: 1
    property var pageNames: []
    property string selected: ""                  // element id
    property var foundIds: []                     // every element found in the preview, in page order
    property var host: null                       // stand-in for the popup window (PopupStub), for content that reads one
    property bool canScale: true                  // false for popups that have no scale setting
    property string dbg: ""                       // on-screen debug line (what was found / what the last drag did)
    property string dbgEv: ""
    property string blockedId: ""                  // the piece being dragged / stretched is pushing against another piece or the panel edge (drawn red)
    property bool busy: false                     // a piece is being dragged / stretched: its outline must not be rebuilt

    readonly property real want: PopupSettings.scaleOf(ed.popupId)
    readonly property real gap: 18
    // popups whose real window is sized from the screen (clipboard, apps, shortcuts) give the size the panel really
    // has; 0 = use the content's own size
    property real forceW: 0
    property real forceH: 0
    property real implW: 340
    readonly property real baseW: ed.forceW > 0 ? ed.forceW : ed.implW
    readonly property real dw: PopupSettings.sizeW(ed.popupId)
    readonly property real dh: PopupSettings.sizeH(ed.popupId)
    property real maxH: 0                         // > 0: the stage may not be taller than this (the preview column on the right)
    readonly property real kH: ed.maxH > 0 ? (ed.maxH - 56) / (ed.tallest + ed.dh) : 1e9
    readonly property real k: Math.max(0.25, Math.min(ed.want, kH, (stage.width - 40 - ed.gap * (ed.pages - 1)) / ((ed.baseW + ed.dw) * ed.pages)))
    property real tallest: 150

    implicitHeight: stage.height


    // ---- no overlap, never outside the popup ----
    // rect of an item in the coordinates of `ref`: { x, y, w, h }
    function boxRect(box, ref) {
        const a = box.mapToItem(ref, 0, 0), b = box.mapToItem(ref, box.width, box.height)
        return { x: Math.min(a.x, b.x), y: Math.min(a.y, b.y), w: Math.abs(b.x - a.x), h: Math.abs(b.y - a.y) }
    }
    function hit(r, o) { return r.x < o.x + o.w - 0.5 && r.x + r.w > o.x + 0.5 && r.y < o.y + o.h - 0.5 && r.y + r.h > o.y + 0.5 }
    // a row and the buttons inside it are one thing, not an overlap
    function related(a, b) {
        let p = a, g = 0
        while (p && g++ < 40) { if (p === b) return true; p = p.parent }
        p = b; g = 0
        while (p && g++ < 40) { if (p === a) return true; p = p.parent }
        return false
    }
    // what `self` may not cover (taken once, when the drag starts); pieces it already covers then are left out
    function obstaclesFor(elems, self, ref, r0) {
        const out = []
        for (let i = 0; i < elems.length; i++) {
            const el = elems[i]
            if (!el || !el.box || el.elementId === self.elementId || !el.box.visible) continue
                if (ed.related(self.box, el.box)) continue
                    const r = ed.boxRect(el.box, ref)
                    if (r.w < 2 || r.h < 2 || ed.hit(r0, r)) continue
                        out.push(r)
        }
        return out
    }
    function inside(r, W, H) { return r.x >= -0.5 && r.y >= -0.5 && r.x + r.w <= W + 0.5 && r.y + r.h <= H + 0.5 }
    function free(r0, dx, dy, obs) {
        const r = { x: r0.x + dx, y: r0.y + dy, w: r0.w, h: r0.h }
        for (let i = 0; i < obs.length; i++) if (ed.hit(r, obs[i])) return false
            return true
    }
    function fitsAll(r, obs, W, H) {
        if (!ed.inside(r, W, H)) return false
            for (let i = 0; i < obs.length; i++) if (ed.hit(r, obs[i])) return false
                return true
    }
    // keep the piece inside the panel (an axis it already sticks out of is left alone)
    function clampDelta(r0, dx, dy, W, H) {
        let x = r0.x + dx, y = r0.y + dy
        if (r0.x >= -0.5 && r0.x + r0.w <= W + 0.5) x = Math.max(0, Math.min(W - r0.w, x))
            if (r0.y >= -0.5 && r0.y + r0.h <= H + 0.5) y = Math.max(0, Math.min(H - r0.h, y))
                return { dx: x - r0.x, dy: y - r0.y }
    }
    // walk from one offset to another in small steps and stop at the last free one (a fast drag cannot jump over a piece)
    function sweep(r0, fx, fy, tx, ty, obs) {
        const n = Math.max(1, Math.ceil(Math.max(Math.abs(tx - fx), Math.abs(ty - fy)) / 3))
        let lx = fx, ly = fy
        for (let i = 1; i <= n; i++) {
            const x = fx + (tx - fx) * i / n, y = fy + (ty - fy) * i / n
            if (!ed.free(r0, x, y, obs)) return { x: lx, y: ly, full: false }
            lx = x; ly = y
        }
        return { x: lx, y: ly, full: true }
    }
    // the smallest extra width / height the popup may have: every moved piece stays inside it, so shrinking the popup
    // never pushes (or hides) a piece
    function minDw() {
        let need = -1e9
        for (let i = 0; i < pagesRep.count; i++) {
            const h = pagesRep.itemAt(i)
            if (!h || !h.root) continue
                for (let j = 0; j < h.elems.length; j++) {
                    const el = h.elems[j]
                    if (!el.box || !ed.movedPiece(el.elementId)) continue
                        const r = ed.boxRect(el.box, h.root)
                        need = Math.max(need, r.x + r.w - ed.baseW)
                }
        }
        return need
    }
    function minDh() {
        let need = -1e9
        for (let i = 0; i < pagesRep.count; i++) {
            const h = pagesRep.itemAt(i)
            if (!h || !h.root) continue
                for (let j = 0; j < h.elems.length; j++) {
                    const el = h.elems[j]
                    if (!el.box || !ed.movedPiece(el.elementId)) continue
                        const r = ed.boxRect(el.box, h.root)
                        need = Math.max(need, r.y + r.h - h.baseH)
                }
        }
        return need
    }
    function movedPiece(id) {
        return PopupSettings.elemX(ed.popupId, id) !== 0 || PopupSettings.elemY(ed.popupId, id) !== 0 || PopupSettings.elemPct(ed.popupId, id) !== 100
    }

    // ---- finding the elements inside a page ----
    property var labels: ({})
    property string dbgArr: "no PopupArrange found"
    function labelFor(id) { return ed.labels[id] ?? id }
    function collect(item, out) {
        if (!item) return
            const kids = item.children
            for (let i = 0; i < kids.length; i++) {
                const o = kids[i]
                if (o.arrangeHost === true) {
                    // Widgets/PopupArrange: pieces found automatically (edit mode keeps them current)
                    o.editing = true
                    ed.dbgArr = o.dbg + " entries=" + o.entries.length
                    for (let j = 0; j < o.entries.length; j++) {
                        const e = o.entries[j]
                        if (e.box && e.box.visible && e.box.width > 0) {
                            out.push({ elementId: e.elementId, box: e.box, visible: true, isButton: e.box.isGlassButton === true })
                            ed.labels[e.elementId] = e.label
                        }
                    }
                } else if (typeof o.elementId === "string" && o.elementId !== "" && o.box !== undefined) {
                    if (o.visible) out.push(o)
                }
                ed.collect(o, out)
            }
    }
    function rescan() {
        if (ed.busy) return
            const ids = []
            for (let i = 0; i < pagesRep.count; i++) {
                const h = pagesRep.itemAt(i)
                if (!h) continue
                    const found = []
                    ed.collect(h.root, found)
                    // only replace the list when something really changed, or the outlines would be rebuilt mid-drag
                    let same = found.length === h.elems.length
                    for (let j = 0; same && j < found.length; j++)
                        same = found[j].elementId === h.elems[j].elementId && found[j].box === h.elems[j].box
                        if (!same) h.elems = found
                            for (let j = 0; j < found.length; j++) if (ids.indexOf(found[j].elementId) < 0) ids.push(found[j].elementId)
            }
            ed.dbg = "popup='" + ed.popupId + "' pages=" + pagesRep.count + " objects=" + ids.length + " | " + ed.dbgArr
            if (JSON.stringify(ids) !== JSON.stringify(ed.foundIds)) ed.foundIds = ids
                if (ed.selected !== "" && ids.indexOf(ed.selected) < 0) ed.selected = ""
    }
    Timer { interval: 350; running: true; repeat: true; triggeredOnStart: true; onTriggered: ed.rescan() }

    // true once everything is loaded and the size has stopped changing (the same numbers on two checks in a row).
    // Only reported, never used for layout: the Settings window waits for it before it widens.
    property bool settled: false
    property string _sig: ""
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!ed.content || pagesRep.count === 0) { ed._sig = ""; ed.settled = false; return }
            const parts = [ed.baseW, ed.tallest, stage.height, ed.k, ed.foundIds.length]
            for (let i = 0; i < pagesRep.count; i++) {
                const h = pagesRep.itemAt(i)
                if (!h || !h.root) { ed._sig = ""; ed.settled = false; return }
                parts.push(h.root.implicitWidth, h.baseH)
            }
            const sig = parts.join("|")
            ed.settled = (sig === ed._sig)
            ed._sig = sig
        }
    }
    onContentChanged: { ed.settled = false; ed._sig = ""; Qt.callLater(ed.rescan) }
    onPopupIdChanged: { ed.tallest = 150; ed.selected = ""; ed.settled = false; ed._sig = ""; Qt.callLater(ed.rescan) }

    Rectangle {
        id: stage
        width: ed.width
        height: (ed.tallest + ed.dh) * ed.k + 56
        radius: Theme.radiusMd
        color: Qt.rgba(0, 0, 0, 0.18)
        border.width: 1
        border.color: Theme.borderMuted
        clip: true

        MouseArea { anchors.fill: parent; onClicked: ed.selected = "" }

        Row {
            id: row
            x: 20
            y: ed.pages > 1 ? 10 : 20
            spacing: ed.gap

            Repeater {
                id: pagesRep
                model: ed.content ? ed.pages : 0

                delegate: Column {
                    id: host
                    required property int index
                    property var elems: []
                    readonly property Item root: loader.item
                    readonly property real baseH: ed.forceH > 0 ? ed.forceH : (loader.item ? loader.item.implicitHeight : 150)
                    spacing: 4

                    onBaseHChanged: ed.tallest = Math.max(ed.tallest, host.baseH)
                    Component.onCompleted: ed.tallest = Math.max(150, host.baseH)

                    Text {
                        visible: ed.pages > 1
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ed.pageNames[host.index] ?? ("Page " + (host.index + 1))
                        color: Theme.foreground
                        opacity: 0.7
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSm
                        font.bold: true
                    }

                    Item {
                        id: frame
                        width: (ed.baseW + ed.dw) * ed.k
                        height: (host.baseH + ed.dh) * ed.k

                        // stand-in popup panel; its `popupId` is how buttons and elements find their style
                        GlassPanel {
                            id: panel
                            property string popupId: ed.popupId
                            anchors.fill: parent
                            radius: PopupSettings.radiusOf(ed.popupId) * ed.k
                            animeAllowed: false
                            // like the real popup window: whatever sticks out of a shrunk popup is not shown
                            clip: true

                            Item {
                                id: scaler
                                width: ed.baseW + ed.dw
                                height: host.baseH + ed.dh
                                scale: ed.k
                                transformOrigin: Item.TopLeft

                                Loader {
                                    id: loader
                                    anchors.fill: parent
                                    sourceComponent: ed.content
                                    onLoaded: {
                                        if (item.page !== undefined) item.page = host.index
                                            if (item.interactive !== undefined) item.interactive = false
                                                if (item.host !== undefined) item.host = ed.host
                                                    if (item.live !== undefined) item.live = true
                                                        if (host.index === 0) ed.implW = item.implicitWidth
                                                            Qt.callLater(ed.rescan)
                                    }
                                }
                            }
                        }

                        // ---- the popup's own handles ----
                        // width: right edge bar (the right edge of page i moves (i + 1) times as fast as the width)
                        Rectangle {
                            z: 20
                            x: frame.width - 3; y: frame.height / 2 - 20
                            width: 6; height: 40; radius: 3
                            color: Theme.foreground; opacity: wMouse.containsMouse || wMouse.pressed ? 0.9 : 0.4
                            MouseArea {
                                id: wMouse
                                anchors.fill: parent; anchors.margins: -8
                                hoverEnabled: true; preventStealing: true
                                cursorShape: Qt.SizeHorCursor
                                property real x0: 0
                                property real w0: 0
                                property bool moved: false     // a press without a real drag changes nothing
                                onPressed: (m) => { x0 = mapToItem(stage, m.x, m.y).x; w0 = PopupSettings.sizeW(ed.popupId); moved = false }
                                onPositionChanged: (m) => {
                                    if (!pressed) return
                                        const dx = mapToItem(stage, m.x, m.y).x - x0
                                        if (!moved && Math.abs(dx) < 5) return
                                            moved = true
                                            let w = w0 + dx / (ed.k * (host.index + 1))
                                            const lo = ed.minDw()
                                            w = Math.max(w, lo)
                                            if (Math.abs(w) < 4 && lo <= 0) w = 0
                                                PopupSettings.setSize(ed.popupId, w, PopupSettings.sizeH(ed.popupId))
                                }
                            }
                        }
                        // height: bottom edge bar
                        Rectangle {
                            z: 20
                            x: frame.width / 2 - 20; y: frame.height - 3
                            width: 40; height: 6; radius: 3
                            color: Theme.foreground; opacity: hMouse.containsMouse || hMouse.pressed ? 0.9 : 0.4
                            MouseArea {
                                id: hMouse
                                anchors.fill: parent; anchors.margins: -8
                                hoverEnabled: true; preventStealing: true
                                cursorShape: Qt.SizeVerCursor
                                property real y0: 0
                                property real h0: 0
                                property bool moved: false
                                onPressed: (m) => { y0 = mapToItem(stage, m.x, m.y).y; h0 = PopupSettings.sizeH(ed.popupId); moved = false }
                                onPositionChanged: (m) => {
                                    if (!pressed) return
                                        const dy = mapToItem(stage, m.x, m.y).y - y0
                                        if (!moved && Math.abs(dy) < 5) return
                                            moved = true
                                            let h = h0 + dy / ed.k
                                            const loH = ed.minDh()
                                            h = Math.max(h, loH)
                                            if (Math.abs(h) < 4 && loH <= 0) h = 0
                                                PopupSettings.setSize(ed.popupId, PopupSettings.sizeW(ed.popupId), h)
                                }
                            }
                        }
                        // scale of the whole popup: bottom right corner
                        Rectangle {
                            z: 20
                            visible: ed.canScale && host.index === ed.pages - 1
                            x: frame.width - 8; y: frame.height - 8
                            width: 16; height: 16; radius: 8
                            color: Theme.accentActive
                            border.width: 2; border.color: Theme.foreground
                            MouseArea {
                                id: sMouse
                                anchors.fill: parent; anchors.margins: -6
                                preventStealing: true
                                cursorShape: Qt.SizeFDiagCursor
                                property point p0
                                property real s0: 100
                                property real fw: 1
                                property real fh: 1
                                property bool moved: false
                                onPressed: (m) => {
                                    moved = false
                                    p0 = mapToItem(stage, m.x, m.y)
                                    s0 = PopupSettings.scalePct(ed.popupId)
                                    fw = Math.max(40, row.width); fh = Math.max(40, frame.height)
                                }
                                onPositionChanged: (m) => {
                                    if (!pressed) return
                                        const c = mapToItem(stage, m.x, m.y)
                                        if (!moved && Math.hypot(c.x - p0.x, c.y - p0.y) < 5) return
                                            moved = true
                                            const f = 1 + ((c.x - p0.x) / fw + (c.y - p0.y) / fh) / 2
                                            PopupSettings.setScalePct(ed.popupId, s0 * Math.max(0.2, f))
                                }
                            }
                        }
                        // corner radius: a ring that slides along the top-left diagonal
                        Rectangle {
                            z: 20
                            x: PopupSettings.radiusOf(ed.popupId) * ed.k - 7; y: x
                            width: 14; height: 14; radius: 7
                            color: "transparent"
                            border.width: 2; border.color: Theme.foreground
                            opacity: rMouse.containsMouse || rMouse.pressed ? 1 : 0.55
                            MouseArea {
                                id: rMouse
                                anchors.fill: parent; anchors.margins: -6
                                hoverEnabled: true; preventStealing: true
                                cursorShape: Qt.PointingHandCursor
                                onPositionChanged: (m) => {
                                    if (!pressed) return
                                        const c = mapToItem(frame, m.x, m.y)
                                        PopupSettings.setRadius(ed.popupId, (c.x + c.y) / 2 / ed.k)
                                }
                            }
                        }

                        // ---- outlines + handles ----
                        Item {
                            id: olayer
                            anchors.fill: parent

                            // swallow every click so the content never reacts
                            MouseArea { anchors.fill: parent; onClicked: ed.selected = "" }

                            Repeater {
                                model: host.elems

                                delegate: Item {
                                    id: ov
                                    required property var modelData
                                    readonly property bool sel: ed.selected === ov.modelData.elementId
                                    readonly property bool blocked: ed.blockedId === ov.modelData.elementId

                                    function sync() {
                                        const el = ov.modelData
                                        if (!el || !el.box) return
                                            const a = el.box.mapToItem(olayer, 0, 0)
                                            const b = el.box.mapToItem(olayer, el.box.width, el.box.height)
                                            ov.x = Math.min(a.x, b.x); ov.y = Math.min(a.y, b.y)
                                            ov.width = Math.max(4, Math.abs(b.x - a.x)); ov.height = Math.max(4, Math.abs(b.y - a.y))
                                    }
                                    Component.onCompleted: ov.sync()
                                    Timer { interval: 120; running: true; repeat: true; onTriggered: ov.sync() }
                                    Connections {
                                        target: ov.modelData.box
                                        ignoreUnknownSignals: true
                                        function onXChanged() { ov.sync() }
                                        function onYChanged() { ov.sync() }
                                        function onScaleChanged() { ov.sync() }
                                        function onWidthChanged() { ov.sync() }
                                        function onHeightChanged() { ov.sync() }
                                    }

                                    z: ov.sel ? 1000000 : 100000 - ov.width * ov.height / 8

                                    // a button (stretched, label kept) or any other piece (scaled)
                                    readonly property bool isBtn: ov.modelData.isButton === true || (!!ov.modelData.box && ov.modelData.box.isGlassButton === true)
                                    // has text whose alignment / size can be set
                                    readonly property bool hasText: ov.isBtn || (!!ov.modelData.box && ov.modelData.box.horizontalAlignment !== undefined)

                                    // nothing is outlined until you point at it; the one you click gets the handles
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 3
                                        color: ov.blocked ? Qt.rgba(1, 0.12, 0.12, 0.42)
                                        : (ov.sel ? Qt.rgba(Theme.accentActive.r, Theme.accentActive.g, Theme.accentActive.b, 0.14)
                                        : (move.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"))
                                        border.width: (ov.blocked || ov.sel) ? 2 : (move.containsMouse ? 1 : 0)
                                        border.color: ov.blocked ? Qt.rgba(1, 0.25, 0.25, 0.95) : (ov.sel ? Theme.accentActive : Qt.rgba(1, 1, 1, 0.6))
                                    }

                                    // move: drag the piece itself
                                    MouseArea {
                                        id: move
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        preventStealing: true        // the Settings page scrolls; a drag here must not
                                        onPressedChanged: {
                                            ed.busy = move.pressed
                                            if (!move.pressed) {
                                                if (move.bad) PopupSettings.patchElem(ed.popupId, ov.modelData.elementId, { x: move.sx + move.lx / ed.k, y: move.sy + move.ly / ed.k })
                                                    move.bad = false
                                                    ed.blockedId = ""
                                            }
                                        }
                                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        property point start
                                        property real sx: 0
                                        property real sy: 0
                                        property var r0: ({ x: 0, y: 0, w: 0, h: 0 })     // the piece's rect when the drag started (panel pixels)
                                        property var obs: []                                // what it may not cover
                                        property real lx: 0                                 // last offset that did not overlap
                                        property real ly: 0
                                        property bool bad: false                            // the piece is on top of another right now
                                        onPressed: (m) => {
                                            const id = ov.modelData.elementId
                                            ed.selected = id
                                            move.start = ov.mapToItem(olayer, m.x, m.y)
                                            move.sx = PopupSettings.elemX(ed.popupId, id)
                                            move.sy = PopupSettings.elemY(ed.popupId, id)
                                            move.r0 = ed.boxRect(ov.modelData.box, olayer)
                                            move.obs = ed.obstaclesFor(host.elems, ov.modelData, olayer, move.r0)
                                            move.lx = 0; move.ly = 0; move.bad = false
                                            ed.dbgEv = "press '" + id + "' at " + Math.round(m.x) + "," + Math.round(m.y)
                                        }
                                        onPositionChanged: (m) => {
                                            if (!pressed) return
                                                const id = ov.modelData.elementId
                                                const cur = ov.mapToItem(olayer, m.x, m.y)
                                                // the piece follows the pointer over anything (kept inside the panel); while it sits on another
                                                // piece it is red, and on release it goes back to the last spot that was free
                                                const c = ed.clampDelta(move.r0, cur.x - move.start.x, cur.y - move.start.y, olayer.width, olayer.height)
                                                let vx = c.dx, vy = c.dy
                                                if (Math.abs(move.sx + vx / ed.k) < 3) vx = -move.sx * ed.k      // click into the original place
                                                    if (Math.abs(move.sy + vy / ed.k) < 3) vy = -move.sy * ed.k
                                                        const ok = ed.free(move.r0, vx, vy, move.obs)
                                                        if (ok) { move.lx = vx; move.ly = vy }
                                                        move.bad = !ok
                                                        ed.blockedId = ok ? "" : id
                                                        const nx = move.sx + vx / ed.k, ny = move.sy + vy / ed.k
                                                        PopupSettings.patchElem(ed.popupId, id, { x: nx, y: ny })
                                                        ed.dbgEv = "drag '" + id + "' x=" + Math.round(nx) + " y=" + Math.round(ny) + (ok ? "" : " OVERLAP")
                                        }
                                    }

                                }
                            }
                        }

                        // ---- the clicked piece's toolbar and handles, ABOVE the popup's own handles ----
                        // (a piece at the popup's corner used to lose its corner handle to the popup's scale / size handles,
                        // so grabbing it resized the whole popup)
                        Item {
                            id: hlayer
                            z: 30
                            anchors.fill: parent

                            Repeater {
                                model: host.elems
                                delegate: Item {
                                    id: ov
                                    required property var modelData
                                    readonly property bool sel: ed.selected === ov.modelData.elementId
                                    visible: ov.sel
                                    function sync() {
                                        const el = ov.modelData
                                        if (!el || !el.box) return
                                            const a = el.box.mapToItem(olayer, 0, 0)
                                            const b = el.box.mapToItem(olayer, el.box.width, el.box.height)
                                            ov.x = Math.min(a.x, b.x); ov.y = Math.min(a.y, b.y)
                                            ov.width = Math.max(4, Math.abs(b.x - a.x)); ov.height = Math.max(4, Math.abs(b.y - a.y))
                                    }
                                    Component.onCompleted: ov.sync()
                                    onSelChanged: if (ov.sel) ov.sync()
                                    // loose text: no height handle (only its width means something)
                                    readonly property bool isText: !!ov.modelData.box && ov.modelData.box.isGlassButton !== true && ov.modelData.box.horizontalAlignment !== undefined && ov.modelData.box.echoMode === undefined
                                    Timer { interval: 120; running: ov.sel; repeat: true; onTriggered: ov.sync() }
                                    Connections {
                                        target: ov.modelData.box
                                        ignoreUnknownSignals: true
                                        function onXChanged() { ov.sync() }
                                        function onYChanged() { ov.sync() }
                                        function onScaleChanged() { ov.sync() }
                                        function onWidthChanged() { ov.sync() }
                                        function onHeightChanged() { ov.sync() }
                                    }
                                    readonly property bool isBtn: ov.modelData.isButton === true || (!!ov.modelData.box && ov.modelData.box.isGlassButton === true)
                                    readonly property bool hasText: ov.isBtn || (!!ov.modelData.box && ov.modelData.box.horizontalAlignment !== undefined)

                                    // options for the clicked piece only: text alignment, text size, text position
                                    Rectangle {
                                        id: tb
                                        visible: ov.sel
                                        z: 20
                                        implicitWidth: tbRow.implicitWidth + 8
                                        implicitHeight: 28
                                        width: implicitWidth; height: implicitHeight
                                        radius: 8
                                        color: Qt.rgba(0, 0, 0, 0.78)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.25)
                                        x: Math.max(-ov.x, Math.min(0, olayer.width - ov.x - tb.width))
                                        y: ov.y > 40 ? -tb.height - 6 : ov.height + 8

                                        Row {
                                            id: tbRow
                                            x: 4; y: 4
                                            spacing: 3
                                            MiniBtn { label: "Left";   on: PopupSettings.elemAlign(ed.popupId, ov.modelData.elementId) === "l"
                                                onTap: PopupSettings.setElemAlign(ed.popupId, ov.modelData.elementId, on ? "" : "l") }
                                                MiniBtn { label: "Center"; on: PopupSettings.elemAlign(ed.popupId, ov.modelData.elementId) === "c"
                                                    onTap: PopupSettings.setElemAlign(ed.popupId, ov.modelData.elementId, on ? "" : "c") }
                                                    MiniBtn { label: "Right";  on: PopupSettings.elemAlign(ed.popupId, ov.modelData.elementId) === "r"
                                                        onTap: PopupSettings.setElemAlign(ed.popupId, ov.modelData.elementId, on ? "" : "r") }
                                                        // text size
                                                        MiniBtn { visible: ov.hasText; label: "A\u2212"
                                                            onTap: PopupSettings.patchElem(ed.popupId, ov.modelData.elementId, { fs: PopupSettings.elemFs(ed.popupId, ov.modelData.elementId) - 10 }) }
                                                            MiniBtn { visible: ov.hasText; label: "A+"
                                                                onTap: PopupSettings.patchElem(ed.popupId, ov.modelData.elementId, { fs: PopupSettings.elemFs(ed.popupId, ov.modelData.elementId) + 10 }) }
                                                                // text position inside the button
                                                                MiniBtn { visible: ov.isBtn; label: "\u25C0"
                                                                    onTap: PopupSettings.patchElem(ed.popupId, ov.modelData.elementId, { tx: PopupSettings.elemTx(ed.popupId, ov.modelData.elementId) - 2 }) }
                                                                    MiniBtn { visible: ov.isBtn; label: "\u25B2"
                                                                        onTap: PopupSettings.patchElem(ed.popupId, ov.modelData.elementId, { ty: PopupSettings.elemTy(ed.popupId, ov.modelData.elementId) - 2 }) }
                                                                        MiniBtn { visible: ov.isBtn; label: "\u25BC"
                                                                            onTap: PopupSettings.patchElem(ed.popupId, ov.modelData.elementId, { ty: PopupSettings.elemTy(ed.popupId, ov.modelData.elementId) + 2 }) }
                                                                            MiniBtn { visible: ov.isBtn; label: "\u25B6"
                                                                                onTap: PopupSettings.patchElem(ed.popupId, ov.modelData.elementId, { tx: PopupSettings.elemTx(ed.popupId, ov.modelData.elementId) + 2 }) }
                                                                                MiniBtn { visible: PopupSettings.elemMoved(ed.popupId, ov.modelData.elementId); label: "Reset"
                                                                                    onTap: PopupSettings.clearElem(ed.popupId, ov.modelData.elementId) }
                                        }
                                    }

                                    // every piece: the four corners scale it uniformly (text and all); the right edge sets its width and the
                                    // bottom edge its height WITHOUT sizing the text (a button's label keeps its size, a text just gets a wider
                                    // or narrower box)
                                    Repeater {
                                        model: ov.sel ? [[0, 0, 0, 0], [1, 0, 0, 0], [0, 1, 0, 0], [1, 1, 0, 0], [1, 0.5, 1, 0]].concat(ov.isText ? [] : [[0.5, 1, 0, 1]]) : []
                                        delegate: Rectangle {
                                            id: hnd
                                            required property var modelData
                                            width: 11; height: 11; radius: (hnd.modelData[2] || hnd.modelData[3]) ? 5 : 2
                                            x: hnd.modelData[0] * ov.width - width / 2
                                            y: hnd.modelData[1] * ov.height - height / 2
                                            color: Theme.accentActive
                                            border.width: 1
                                            border.color: Theme.foreground

                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -5
                                                preventStealing: true
                                                onPressedChanged: {
                                                    ed.busy = pressed
                                                    if (!pressed) {
                                                        if (bad) {
                                                            if (hnd.modelData[2] || hnd.modelData[3]) {
                                                                if (ov.isBtn) PopupSettings.patchElem(ed.popupId, ov.modelData.elementId, { w: lastW, h: lastH })
                                                                    else PopupSettings.patchElem(ed.popupId, ov.modelData.elementId, { bw: lastGw, bh: lastGh })
                                                            } else PopupSettings.patchElem(ed.popupId, ov.modelData.elementId, { s: lastS })
                                                        }
                                                        bad = false
                                                        ed.blockedId = ""
                                                    }
                                                }
                                                cursorShape: hnd.modelData[2] ? Qt.SizeHorCursor : (hnd.modelData[3] ? Qt.SizeVerCursor : Qt.SizeFDiagCursor)
                                                property point p0
                                                property real cx: 0
                                                property real cy: 0
                                                property real d0: 1
                                                property real s0: 100
                                                property real w0: 100
                                                property real h0: 100
                                                property real bw: 1
                                                property real bh: 1
                                                property bool moved: false
                                                property var r0: ({ x: 0, y: 0, w: 0, h: 0 })
                                                property var obs: []
                                                property real lastS: 100
                                                property real gw0: 0            // the piece's own width / height in px (not stretched by the scale) when the drag started
                                                property real gh0: 0
                                                property real lastGw: 0
                                                property real lastGh: 0
                                                property bool bad: false
                                                property real lastW: 100
                                                property real lastH: 100
                                                onPressed: (m) => {
                                                    moved = false
                                                    const id = ov.modelData.elementId
                                                    p0 = mapToItem(olayer, m.x, m.y)
                                                    cx = ov.x + ov.width / 2; cy = ov.y + ov.height / 2
                                                    d0 = Math.max(4, Math.hypot(p0.x - cx, p0.y - cy))
                                                    s0 = PopupSettings.elemPct(ed.popupId, id)
                                                    w0 = PopupSettings.elemW(ed.popupId, id); h0 = PopupSettings.elemH(ed.popupId, id)
                                                    bw = Math.max(8, ov.width); bh = Math.max(8, ov.height)
                                                    r0 = ed.boxRect(ov.modelData.box, olayer)
                                                    obs = ed.obstaclesFor(host.elems, ov.modelData, olayer, r0)
                                                    lastS = s0; lastW = w0; lastH = h0; bad = false
                                                    gw0 = ov.modelData.box.width; gh0 = ov.modelData.box.height
                                                    lastGw = PopupSettings.elemBw(ed.popupId, id); lastGh = PopupSettings.elemBh(ed.popupId, id)
                                                }
                                                onPositionChanged: (m) => {
                                                    if (!pressed) return
                                                        const id = ov.modelData.elementId
                                                        const cur = mapToItem(olayer, m.x, m.y)
                                                        if (!moved && Math.hypot(cur.x - p0.x, cur.y - p0.y) < 4) return   // a click on a handle changes nothing
                                                            moved = true
                                                            // any size can be dragged to; while it covers another piece (or leaves the popup) it is red,
                                                            // and on release it goes back to the last size that fitted
                                                            const W = olayer.width, H = olayer.height
                                                            const stretch = hnd.modelData[2] || hnd.modelData[3]
                                                            if (ov.isBtn && stretch) {
                                                                let nw = w0, nh = h0
                                                                if (hnd.modelData[2]) nw = w0 * (bw + (cur.x - p0.x)) / bw
                                                                    if (hnd.modelData[3]) nh = h0 * (bh + (cur.y - p0.y)) / bh
                                                                        if (Math.abs(nw - 100) < 4) nw = 100
                                                                            if (Math.abs(nh - 100) < 4) nh = 100
                                                                                const fitB = (tw, th) => (tw <= w0 && th <= h0)
                                                                                || ed.fitsAll({ x: r0.x, y: r0.y, w: r0.w * tw / w0, h: r0.h * th / h0 }, obs, W, H)
                                                                                const ok = fitB(nw, nh)
                                                                                if (ok) { lastW = nw; lastH = nh }
                                                                                bad = !ok
                                                                                ed.blockedId = ok ? "" : id
                                                            } else if (stretch) {
                                                                // width / height in px of any other piece; its text keeps its size
                                                                const pk = Math.max(0.1, s0 / 100)
                                                                const dxv = hnd.modelData[2] ? cur.x - p0.x : 0, dyv = hnd.modelData[3] ? cur.y - p0.y : 0
                                                                const patchObj = {}
                                                                if (hnd.modelData[2]) patchObj.bw = Math.max(8, gw0 + dxv / (ed.k * pk))
                                                                    if (hnd.modelData[3]) patchObj.bh = Math.max(8, gh0 + dyv / (ed.k * pk))
                                                                        const ok = (dxv <= 0 && dyv <= 0) || ed.fitsAll({ x: r0.x, y: r0.y, w: Math.max(4, r0.w + dxv), h: Math.max(4, r0.h + dyv) }, obs, W, H)
                                                                        if (ok) { if (patchObj.bw !== undefined) lastGw = patchObj.bw; if (patchObj.bh !== undefined) lastGh = patchObj.bh }
                                                                        bad = !ok
                                                                        ed.blockedId = ok ? "" : id
                                                                        PopupSettings.patchElem(ed.popupId, id, patchObj)
                                                            } else {
                                                                let pct = s0 * Math.hypot(cur.x - cx, cur.y - cy) / d0
                                                                if (Math.abs(pct - 100) < 4) pct = 100
                                                                    const ccx = r0.x + r0.w / 2, ccy = r0.y + r0.h / 2
                                                                    const fitS = (t) => t <= s0 || ed.fitsAll({ x: ccx - r0.w * t / s0 / 2, y: ccy - r0.h * t / s0 / 2, w: r0.w * t / s0, h: r0.h * t / s0 }, obs, W, H)
                                                                    const ok = fitS(pct)
                                                                    if (ok) lastS = pct
                                                                        bad = !ok
                                                                        ed.blockedId = ok ? "" : id
                                                            }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
