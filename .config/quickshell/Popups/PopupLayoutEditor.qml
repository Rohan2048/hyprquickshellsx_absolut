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

    readonly property real want: PopupSettings.scaleOf(ed.popupId)
    readonly property real gap: 18
    property real baseW: 340
    readonly property real dw: PopupSettings.sizeW(ed.popupId)
    readonly property real dh: PopupSettings.sizeH(ed.popupId)
    property real maxH: 0                         // > 0: the stage may not be taller than this (the preview column on the right)
    readonly property real kH: ed.maxH > 0 ? (ed.maxH - 56) / (ed.tallest + ed.dh) : 1e9
    readonly property real k: Math.max(0.25, Math.min(ed.want, kH, (stage.width - 40 - ed.gap * (ed.pages - 1)) / ((ed.baseW + ed.dw) * ed.pages)))
    property real tallest: 150

    implicitHeight: stage.height

    // ---- finding the elements inside a page ----
    property var labels: ({})
    function labelFor(id) { return ed.labels[id] ?? id }
    function collect(item, out) {
        if (!item) return
            const kids = item.children
            for (let i = 0; i < kids.length; i++) {
                const o = kids[i]
                if (o.arrangeHost === true) {
                    // Widgets/PopupArrange: pieces found automatically (edit mode keeps them current)
                    o.editing = true
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
    onPopupIdChanged: { ed.selected = ""; ed.settled = false; ed._sig = ""; Qt.callLater(ed.rescan) }

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
                    readonly property real baseH: loader.item ? loader.item.implicitHeight : 150
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
                        Rectangle {
                            id: panel
                            property string popupId: ed.popupId
                            anchors.fill: parent
                            radius: PopupSettings.radiusOf(ed.popupId) * ed.k
                            color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.07)
                            border.width: 1
                            border.color: Theme.borderMuted
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
                                                        if (host.index === 0) ed.baseW = item.implicitWidth
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
                                onPressed: (m) => { x0 = mapToItem(stage, m.x, m.y).x; w0 = PopupSettings.sizeW(ed.popupId) }
                                onPositionChanged: (m) => {
                                    if (!pressed) return
                                        const dx = mapToItem(stage, m.x, m.y).x - x0
                                        let w = w0 + dx / (ed.k * (host.index + 1))
                                        if (Math.abs(w) < 4) w = 0
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
                                onPressed: (m) => { y0 = mapToItem(stage, m.x, m.y).y; h0 = PopupSettings.sizeH(ed.popupId) }
                                onPositionChanged: (m) => {
                                    if (!pressed) return
                                        const dy = mapToItem(stage, m.x, m.y).y - y0
                                        let h = h0 + dy / ed.k
                                        if (Math.abs(h) < 4) h = 0
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
                                onPressed: (m) => {
                                    p0 = mapToItem(stage, m.x, m.y)
                                    s0 = PopupSettings.scalePct(ed.popupId)
                                    fw = Math.max(40, row.width); fh = Math.max(40, frame.height)
                                }
                                onPositionChanged: (m) => {
                                    if (!pressed) return
                                        const c = mapToItem(stage, m.x, m.y)
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
                            id: layer
                            anchors.fill: parent

                            // swallow every click so the content never reacts
                            MouseArea { anchors.fill: parent; onClicked: ed.selected = "" }

                            Repeater {
                                model: host.elems

                                delegate: Item {
                                    id: ov
                                    required property var modelData
                                    readonly property bool sel: ed.selected === ov.modelData.elementId

                                    function sync() {
                                        const el = ov.modelData
                                        if (!el || !el.box) return
                                            const a = el.box.mapToItem(layer, 0, 0)
                                            const b = el.box.mapToItem(layer, el.box.width, el.box.height)
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
                                        color: ov.sel ? Qt.rgba(Theme.accentActive.r, Theme.accentActive.g, Theme.accentActive.b, 0.14)
                                        : (move.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent")
                                        border.width: ov.sel ? 2 : (move.containsMouse ? 1 : 0)
                                        border.color: ov.sel ? Theme.accentActive : Qt.rgba(1, 1, 1, 0.6)
                                    }

                                    // move: drag the piece itself
                                    MouseArea {
                                        id: move
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        preventStealing: true        // the Settings page scrolls; a drag here must not
                                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                        property point start
                                        property real sx: 0
                                        property real sy: 0
                                        onPressed: (m) => {
                                            const id = ov.modelData.elementId
                                            ed.selected = id
                                            move.start = ov.mapToItem(layer, m.x, m.y)
                                            move.sx = PopupSettings.elemX(ed.popupId, id)
                                            move.sy = PopupSettings.elemY(ed.popupId, id)
                                        }
                                        onPositionChanged: (m) => {
                                            if (!pressed) return
                                                const id = ov.modelData.elementId
                                                const cur = ov.mapToItem(layer, m.x, m.y)
                                                let nx = move.sx + (cur.x - move.start.x) / ed.k
                                                let ny = move.sy + (cur.y - move.start.y) / ed.k
                                                if (Math.abs(nx) < 3) nx = 0          // click into the original place
                                                    if (Math.abs(ny) < 3) ny = 0
                                                        PopupSettings.patchElem(ed.popupId, id, { x: nx, y: ny })
                                        }
                                    }

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
                                        x: Math.max(-ov.x, Math.min(0, layer.width - ov.x - tb.width))
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

                                    // buttons: stretch the button only (right edge = width, bottom edge = height, corner = both); the
                                    // label keeps its size. Every other piece: four corners that scale it uniformly.
                                    Repeater {
                                        model: ov.sel ? (ov.isBtn ? [[1, 0.5, 1, 0], [0.5, 1, 0, 1], [1, 1, 1, 1]] : [[0, 0, 0, 0], [1, 0, 0, 0], [0, 1, 0, 0], [1, 1, 0, 0]]) : []
                                        delegate: Rectangle {
                                            id: hnd
                                            required property var modelData
                                            width: 11; height: 11; radius: ov.isBtn ? 5 : 2
                                            x: hnd.modelData[0] * ov.width - width / 2
                                            y: hnd.modelData[1] * ov.height - height / 2
                                            color: Theme.accentActive
                                            border.width: 1
                                            border.color: Theme.foreground

                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -5
                                                preventStealing: true
                                                cursorShape: ov.isBtn ? (hnd.modelData[2] && hnd.modelData[3] ? Qt.SizeFDiagCursor : (hnd.modelData[2] ? Qt.SizeHorCursor : Qt.SizeVerCursor)) : Qt.SizeFDiagCursor
                                                property point p0
                                                property real cx: 0
                                                property real cy: 0
                                                property real d0: 1
                                                property real s0: 100
                                                property real w0: 100
                                                property real h0: 100
                                                property real bw: 1
                                                property real bh: 1
                                                onPressed: (m) => {
                                                    const id = ov.modelData.elementId
                                                    p0 = mapToItem(layer, m.x, m.y)
                                                    cx = ov.x + ov.width / 2; cy = ov.y + ov.height / 2
                                                    d0 = Math.max(4, Math.hypot(p0.x - cx, p0.y - cy))
                                                    s0 = PopupSettings.elemPct(ed.popupId, id)
                                                    w0 = PopupSettings.elemW(ed.popupId, id); h0 = PopupSettings.elemH(ed.popupId, id)
                                                    bw = Math.max(8, ov.width); bh = Math.max(8, ov.height)
                                                }
                                                onPositionChanged: (m) => {
                                                    if (!pressed) return
                                                        const id = ov.modelData.elementId
                                                        const cur = mapToItem(layer, m.x, m.y)
                                                        if (ov.isBtn) {
                                                            let nw = w0, nh = h0
                                                            if (hnd.modelData[2]) nw = w0 * (bw + (cur.x - p0.x)) / bw
                                                                if (hnd.modelData[3]) nh = h0 * (bh + (cur.y - p0.y)) / bh
                                                                    if (Math.abs(nw - 100) < 4) nw = 100
                                                                        if (Math.abs(nh - 100) < 4) nh = 100
                                                                            PopupSettings.patchElem(ed.popupId, id, { w: nw, h: nh })
                                                        } else {
                                                            let pct = s0 * Math.hypot(cur.x - cx, cur.y - cy) / d0
                                                            if (Math.abs(pct - 100) < 4) pct = 100
                                                                PopupSettings.patchElem(ed.popupId, id, { s: pct })
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
