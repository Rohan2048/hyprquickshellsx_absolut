import QtQuick
import QtQuick.Layouts
import "../Services"

// Makes the pieces of a popup movable and scalable from Settings > Popups > Popup styles WITHOUT wrapping each
// one by hand. Drop one into a popup's content:
//
//     PopupArrange { containers: [contentCol] }
//
// It finds, inside the popup,
//   * every direct child of the containers you list (a row, a header, a list, a graph ...), and
//   * every button anywhere, ONE object each however it is drawn: a GlassButton (text, symbol or icon) or any other
//     clickable control built from an Item with a MouseArea (its label / icon is part of it), and
//   * every loose Text (one that is not the label of a button, and not a row of a list),
// and applies the saved place of each (PopupSettings "layout": an offset in px and a uniform scale in percent,
// never a stretch) as plain visual transforms. That moves / scales a piece without pushing the others around and
// without touching the item's own scale / hover animation, exactly like Widgets/PopupElement does for the pieces
// that are wrapped in one. The popup's own layout, sizes and behaviour are never changed.
//
// While Settings has the popup open in the preview, `editing` is true: the pieces are listed in `entries` for the
// layout editor (Popups/PopupLayoutEditor), which outlines them and writes the new place when you drag.
Item {
    id: arr

    property var containers: []
    property bool includeButtons: true
    // true: buttons / rows inside a list or grid (apps, clipboard entries ...) are not objects; they come and go
    property bool skipListButtons: false
    property bool editing: false

    // for the layout editor
    readonly property bool arrangeHost: true
    property var entries: []                       // [{ elementId, box, label }]
    property string dbg: ""                       // last scan / apply result (shown in the layout editor while debugging)

    readonly property string popupId: PopupSettings.ctxOf(arr)
    readonly property bool wanted: arr.editing || PopupSettings.layoutChanged(arr.popupId)

    width: 0
    height: 0

    function _label(item, depth) {
        if (!item || depth > 6) return ""
            if (typeof item.text === "string" && item.text.trim() !== "" && item.text.length < 60) return item.text.trim()
                const k = item.children
                for (let i = 0; i < k.length; i++) {
                    const t = arr._label(k[i], depth + 1)
                    if (t !== "") return t
                }
                return ""
    }
    function _slug(t) { return t.replace(/^[^A-Za-z0-9]+/, "").replace(/\s+/g, " ").trim().slice(0, 40) }
    function _isRepeater(o) { return o.model !== undefined && o.delegate !== undefined }
    // a Text (not a TextInput / TextField, not a button)
    function _isText(o) { return typeof o.text === "string" && o.elide !== undefined && o.echoMode === undefined && o.font !== undefined }
    // name of the first Image inside an item ("settings" for .../settings.svg), for buttons that have an icon and no text
    function _iconName(item, depth) {
        if (!item || depth > 4) return ""
            if (item.fillMode !== undefined && item.sourceSize !== undefined && item.source !== undefined) {
                const n = String(item.source).split("/").pop().replace(/\.[A-Za-z0-9]+$/, "")
                if (n !== "") return n
            }
            const k = item.children
            for (let i = 0; i < k.length; i++) {
                const t = arr._iconName(k[i], depth + 1)
                if (t !== "") return t
            }
            return ""
    }
    // what a button is called: its text, else its symbol (+ \u2715 \u2713), else its objectName, else its icon
    function _btnLabel(o, isGB) {
        const raw = arr._label(o, 0).trim()
        let t = arr._slug(raw)
        if (t === "") t = raw.slice(0, 40)
            if (t === "" && o.objectName) t = o.objectName
                if (t === "") t = (typeof o.icon === "string" && o.icon !== "") ? String(o.icon).split("/").pop().replace(/\.[A-Za-z0-9]+$/, "") : ""
                    if (t === "") t = arr._iconName(o, 0)
                        if (t === "" && isGB) t = "Button"
                            return t
    }

    function scan() {
        try { arr._scan() } catch (err) { arr.dbg = "scan ERROR: " + err; console.log("[PA] scan error:", err) }
    }
    function _contains(a, b) {
        let p = b, g = 0
        while (p && g++ < 60) { if (p === a) return true; p = p.parent }
        return false
    }
    // does `it` hold something that is not a button / text / field (an icon, a graph, a list)? Those stay with the section.
    function _hasMedia(it, leaves, depth) {
        if (!it || depth > 8) return false
            const k = it.children
            for (let i = 0; i < k.length; i++) {
                const o = k[i]
                if (!o || leaves.indexOf(o) >= 0 || !o.visible) continue
                    if ((o.fillMode !== undefined && o.source !== undefined) || o.renderStrategy !== undefined) return true
                        if (o.model !== undefined && o.delegate !== undefined && !arr._isRepeater(o)) return true
                            if (arr._hasMedia(o, leaves, depth + 1)) return true
            }
            return false
    }
    function _scan() {
        const used = {}
        function uniq(k) { let n = used[k] || 0; used[k] = n + 1; return n === 0 ? k : k + "#" + (n + 1) }
        const out = []            // fields, and sections that hold more than buttons / texts
        const leaves = []         // buttons, loose texts, fields: one object each
        const seen = []

        // 1. direct children of the containers
        const direct = []
        for (let ci = 0; ci < arr.containers.length; ci++) {
            const c = arr.containers[ci]
            if (!c) continue
                const kids = c.children
                for (let i = 0; i < kids.length; i++) {
                    const o = kids[i]
                    if (o === arr || arr._isRepeater(o) || o.elementId !== undefined || o.isGlassButton === true) continue
                        if (!(o.width > 0 || o.implicitWidth > 0)) continue
                            direct.push({ o: o, ci: ci, i: i, lab: arr._label(o, 0) })
                }
        }
        // a field (search box ...) is one object
        for (let d = 0; d < direct.length; d++) {
            const e = direct[d]
            if (e.o.echoMode === undefined) continue
                seen.push(e.o)
                out.push({ elementId: uniq("c" + e.ci + ":" + (e.lab !== "" ? arr._slug(e.lab) : "#" + e.i)), box: e.o, label: e.lab !== "" ? e.lab : "Field" })
        }
        // 2. every button, every loose text and every field, one object each
        if (arr.includeButtons) {
            const roots = arr.containers.filter(c => !!c)
            seen.push(...out.map(e => e.box).filter(b => seen.indexOf(b) < 0))
            // a text or custom button that sat directly in a section keeps the name it was saved under
            function keyFor(o, fresh) {
                for (let d = 0; d < direct.length; d++)
                    if (direct[d].o === o) return uniq("c" + direct[d].ci + ":" + (direct[d].lab !== "" ? arr._slug(direct[d].lab) : "#" + direct[d].i))
                        return uniq(fresh)
            }
            function clickable(o) {
                const k = o.children
                for (let i = 0; i < k.length; i++) if (k[i].acceptedButtons !== undefined && k[i].containsMouse !== undefined) return true
                    return false
            }
            // noText: inside a button (its label is the button's); inList: inside a list / scroll area (rows come and go)
            function walk(it, noText, inList) {
                const kids = it.children
                for (let i = 0; i < kids.length; i++) {
                    const o = kids[i]
                    if (!o || o === arr || o.noArrange === true) continue
                        if (o.echoMode !== undefined) {                       // a field: one object, never looked into
                            if (!noText && !inList && o.elementId === undefined && seen.indexOf(o) < 0 && o.visible && o.width > 0 && o.height > 0) {
                                const raw = (typeof o.placeholderText === "string" && o.placeholderText !== "") ? o.placeholderText : "Field"
                                seen.push(o)
                                leaves.push({ elementId: uniq("fld:" + arr._slug(raw)), box: o, label: arr._slug(raw) })
                            }
                            continue
                        }
                        const isGB = o.isGlassButton === true
                        let isBtn = false
                        if ((isGB || (o.elementId === undefined && clickable(o))) && seen.indexOf(o) < 0 && !(arr.skipListButtons && inList)) {
                            const lab = arr._btnLabel(o, isGB)
                            if (lab !== "" && o.width > 0 && o.height > 0) {
                                seen.push(o)
                                leaves.push({ elementId: keyFor(o, "btn:" + ((isGB && o.arrangeId !== "") ? o.arrangeId : lab)), box: o, label: lab })
                                isBtn = true
                            }
                        } else if (!noText && !inList && o.elementId === undefined && seen.indexOf(o) < 0 && arr._isText(o)
                            && o.visible && o.text.trim() !== "" && o.width > 0 && o.height > 0) {
                            const raw = o.text.trim().slice(0, 40)
                            const lab = arr._slug(raw) !== "" ? arr._slug(raw) : raw
                            seen.push(o)
                            leaves.push({ elementId: keyFor(o, "txt:" + lab), box: o, label: lab })
                            }
                            if (!isGB) walk(o, noText || isBtn, inList || o.contentItem !== undefined)
                }
            }
            for (let r = 0; r < roots.length; r++) walk(roots[r], false, false)
        }
        // 3. a row / section that only holds buttons and texts is NOT an object (they are, each on its own); one that also
        //    holds an icon, a graph or a list stays one
        const leafBoxes = leaves.map(e => e.box).concat(out.map(e => e.box))
        for (let d = 0; d < direct.length; d++) {
            const e = direct[d]
            if (e.o.echoMode !== undefined || seen.indexOf(e.o) >= 0) continue
                let holds = false
                for (let k = 0; k < leaves.length; k++) if (arr._contains(e.o, leaves[k].box)) { holds = true; break }
                if (holds && !arr._hasMedia(e.o, leafBoxes, 0)) continue
                    out.push({ elementId: uniq("c" + e.ci + ":" + (e.lab !== "" ? arr._slug(e.lab) : "#" + e.i)), box: e.o, label: e.lab !== "" ? e.lab : "Section " + (e.i + 1) })
        }
        arr.entries = out.concat(leaves)
        arr._watchAll()
        arr.dbg = "scan: popup='" + arr.popupId + "' entries=" + arr.entries.length
        arr.apply()
    }

    // find / create the two transforms this item carries
    function _tf(item) {
        const list = item.transform
        for (let i = 0; i < list.length; i++) if (list[i].objectName === "pa-scale") return { sc: list[i], tr: list[i + 1] }
        const sc = Qt.createQmlObject('import QtQuick; Scale { objectName: "pa-scale"; property Item it; origin.x: it ? it.width / 2 : 0; origin.y: it ? it.height / 2 : 0 }', item)
        const tr = Qt.createQmlObject('import QtQuick; Translate { objectName: "pa-move" }', item)
        sc.it = item
        const keep = []
        for (let i = 0; i < list.length; i++) keep.push(list[i])
            keep.push(sc); keep.push(tr)
            item.transform = keep
            return { sc: sc, tr: tr }
    }
    // a piece's width / height in px (set by the edge handles); text and everything inside keep their size. In a layout the piece
    // is pinned with Layout.minimum / maximum, outside one its width / height is set. Cleared = back to what the popup gave it.
    property var _lay: ({})
    function _setSize(b, key, bw, bh) {
        try {
            if (arr._inLayout(b)) {
                let o = arr._lay[key]
                if (!o) {
                    if (bw <= 0 && bh <= 0) return
                        o = { minW: b.Layout.minimumWidth, maxW: b.Layout.maximumWidth, minH: b.Layout.minimumHeight, maxH: b.Layout.maximumHeight }
                        arr._lay[key] = o
                }
                if (bw > 0) { b.Layout.minimumWidth = bw; b.Layout.maximumWidth = bw } else { b.Layout.minimumWidth = o.minW; b.Layout.maximumWidth = o.maxW }
                if (bh > 0) { b.Layout.minimumHeight = bh; b.Layout.maximumHeight = bh } else { b.Layout.minimumHeight = o.minH; b.Layout.maximumHeight = o.maxH }
                if (bw <= 0 && bh <= 0) delete arr._lay[key]
            } else {
                let o = arr._orig[key + "#sz"]
                if (!o) {
                    if (bw <= 0 && bh <= 0) return
                        o = { w: b.width, h: b.height }
                        arr._orig[key + "#sz"] = o
                }
                if (bw > 0) b.width = bw; else b.width = b.implicitWidth > 0 ? b.implicitWidth : o.w
                    if (bh > 0) b.height = bh; else b.height = b.implicitHeight > 0 ? b.implicitHeight : o.h
                        if (bw <= 0 && bh <= 0) delete arr._orig[key + "#sz"]
            }
        } catch (err) { console.log("[PA] size error:", err) }
    }
    property var _sig: ({})                  // key -> the size settings last applied (a change opens the "keep the others still" window)
    property var _changed: ({})
    property real _entryT: 0
    function _entryWin() { return Date.now() - arr._entryT < 400 }
    property var _orig: ({})            // what a piece looked like before Settings changed it
    property string _lastLog: ""
    property var _trace: []
    function _haOf(a) { return a === "l" ? Text.AlignLeft : (a === "r" ? Text.AlignRight : Text.AlignHCenter) }
    function _qtOf(a) { return a === "l" ? Qt.AlignLeft : (a === "r" ? Qt.AlignRight : Qt.AlignHCenter) }
    function _inLayout(b) { return !!b.parent && String(b.parent).indexOf("Layout") >= 0 }
    function apply() {
        try { arr._apply() } catch (err) { arr.dbg = "apply ERROR: " + err; console.log("[PA] apply error:", err) }
    }
    function _apply() {
        const id = arr.popupId
        let nm = 0
        arr._trace = []
        for (let i = 0; i < arr.entries.length; i++) {
            const e = arr.entries[i]
            if (!e.box) continue
                const key = e.elementId
                const b = e.box
                if (arr.editing) stamp.restart()
                    if (arr.editing && !arr._resizing() && !arr._entryWin()) { arr._changed = ({}); const nn = arr._natRoot(b); if (nn) arr._nat[key] = nn }
                    const x = PopupSettings.elemX(id, key), y = PopupSettings.elemY(id, key)
                    const al = PopupSettings.elemAlign(id, key)
                    const fs = PopupSettings.elemFs(id, key)
                    const isBtn = b.isGlassButton === true
                    const sw = isBtn ? PopupSettings.elemW(id, key) / 100 : 1
                    const sh = isBtn ? PopupSettings.elemH(id, key) / 100 : 1
                    const p = PopupSettings.elemPct(id, key)      // every piece scales (buttons also stretch, see below)
                    const tx = PopupSettings.elemTx(id, key), ty = PopupSettings.elemTy(id, key)
                    const bw = PopupSettings.elemBw(id, key), bh = PopupSettings.elemBh(id, key)
                    // a piece whose size was just changed pushes its neighbours around in a layout: for that moment every OTHER piece is
                    // held where it was (see _drift), so each object stays independent of the others
                    const sig = sw + "|" + sh + "|" + bw + "|" + bh
                    if (arr.editing && arr._sig[key] !== undefined && arr._sig[key] !== sig) { arr._entryT = Date.now(); arr._changed[key] = true }
                    arr._sig[key] = sig
                    if (!isBtn) arr._setSize(b, key, bw, bh)

                        if (isBtn) {
                            // the button itself: size, label alignment, label size and label offset
                            if (b.stretchW !== sw) b.stretchW = sw
                                if (b.stretchH !== sh) b.stretchH = sh
                                    b.labelAlign = al !== "" ? arr._qtOf(al) : Qt.AlignHCenter
                                    b.fontScale = fs / 100
                                    b.textDx = tx; b.textDy = ty
                                    // outside a layout the size is set here, and only for a button that is actually stretched (and put back
                                    // when the stretch is cleared), so a button whose size the popup binds itself is never touched
                                    // (a button that fills a wrapper is sized by the wrapper, which follows the button's styledWidth)
                                    if (!arr._inLayout(b) && !(b.anchors && b.anchors.fill)) {
                                        if (b._pinW) { b.width = b._baseW * b._fw; arr._orig[key + "#w"] = true }
                                        else if (arr._orig[key + "#w"]) { b.width = b.implicitWidth; delete arr._orig[key + "#w"] }
                                        if (b._pinH) { b.height = b._baseH * b._fh; arr._orig[key + "#h"] = true }
                                        else if (arr._orig[key + "#h"]) { b.height = b.implicitHeight; delete arr._orig[key + "#h"] }
                                    }
                        } else if (b.horizontalAlignment !== undefined && b.font !== undefined) {
                            // a text piece: alignment and size
                            if (arr._orig[key] === undefined) arr._orig[key] = { ha: b.horizontalAlignment, px: b.font.pixelSize }
                            const o = arr._orig[key]
                            b.horizontalAlignment = al !== "" ? arr._haOf(al) : o.ha
                            if (o.px > 0) b.font.pixelSize = Math.max(6, Math.round(o.px * fs / 100))
                        }
                        // where the piece sits in the space it was given: left / centre / right of its parent
                        let dx = 0
                        if (al !== "" && b.parent) {
                            const pw = b.parent.width
                            dx = al === "l" ? -b.x : (al === "c" ? (pw - b.width) / 2 - b.x : pw - b.width - b.x)
                        }
                        const moved = x !== 0 || y !== 0 || p !== 100 || dx !== 0 || !!arr._adj[key]
                        let has = false
                        const list = b.transform
                        for (let j = 0; j < list.length; j++) if (list[j].objectName === "pa-scale") { has = true; break }
                        if (!moved && !has) continue
                            const t = arr._tf(b)
                            t.sc.xScale = p / 100; t.sc.yScale = p / 100
                            // Pending shift from a popup resize (see _drift): the piece is held where it was while the popup grows / shrinks.
                            const ad = arr._adj[key]
                            let mx = x + dx + (ad ? ad.x : 0), my = y + (ad ? ad.y : 0)
                            // Real popup only (never while Settings edits, never written back): a piece that would land outside the
                            // panel, e.g. on a screen whose popup is smaller than the one it was arranged on, is slid back inside.
                            // In the Settings preview nothing is clamped, so resizing the popup never moves a piece.
                            const root = arr.parent
                            // The real popup's panel is not the size this was arranged on (another screen): the piece goes to the same
                            // relative spot (its centre as a fraction of the panel) instead of the same pixel offset.
                            const fx = PopupSettings.elemFx(id, key), fy = PopupSettings.elemFy(id, key)
                            const pw0 = PopupSettings.elemPw(id, key), ph0 = PopupSettings.elemPh(id, key)
                            if (!arr.editing && al === "" && fx !== undefined && fy !== undefined && root && root.width > 0 && root.height > 0
                                && b.width > 0 && b.height > 0 && (Math.abs(root.width - pw0) > 1 || Math.abs(root.height - ph0) > 1)) {
                                t.tr.x = 0; t.tr.y = 0
                                const cc = b.mapToItem(root, b.width / 2, b.height / 2)
                                mx = fx * root.width - cc.x; my = fy * root.height - cc.y
                                }
                                if (!arr.editing && (x !== 0 || y !== 0) && root && root.width > 0 && root.height > 0 && b.width > 0 && b.height > 0) {
                                    t.tr.x = 0; t.tr.y = 0
                                    const q1 = b.mapToItem(root, 0, 0), q2 = b.mapToItem(root, b.width, b.height)
                                    const x0 = Math.min(q1.x, q2.x), x1 = Math.max(q1.x, q2.x)
                                    const y0 = Math.min(q1.y, q2.y), y1 = Math.max(q1.y, q2.y)
                                    const loX = -x0, hiX = root.width - x1, loY = -y0, hiY = root.height - y1
                                    mx = hiX < loX ? (loX + hiX) / 2 : Math.max(loX, Math.min(hiX, mx))
                                    my = hiY < loY ? (loY + hiY) / 2 : Math.max(loY, Math.min(hiY, my))
                                }
                                t.tr.x = mx; t.tr.y = my
                                arr._trace.push(key + " saved=(" + Math.round(x) + "," + Math.round(y) + ") shown=(" + Math.round(mx) + "," + Math.round(my) + ")")
                                nm++
        }
        arr.dbg = "apply: popup='" + id + "' entries=" + arr.entries.length + " moved=" + nm
        // what the real popup did with the saved layout (printed once per change; read it in the terminal running `qs`)
        if (!arr.editing) {
            const saved = Object.keys(PopupSettings.get("layout", id, {}) || {})
            const found = arr.entries.map(e => e.elementId)
            const missing = saved.filter(k => found.indexOf(k) < 0)
            const rootSize = arr.parent ? Math.round(arr.parent.width) + "x" + Math.round(arr.parent.height) : "?"
            const line = "[PA] popup='" + id + "' panel=" + rootSize + " found=" + found.length + " saved=" + saved.length
            + (missing.length ? " NOT-FOUND=[" + missing.join(" | ") + "]" : "") + (arr._trace.length ? " " + arr._trace.join(" ; ") : "")
            if (saved.length > 0 && line !== arr._lastLog) { arr._lastLog = line; console.log(line) }
        }
    }

    // ---- holding pieces still while the popup is resized (Settings preview) ----
    // A piece's saved place is an offset from where the popup's layout puts it. When the popup grows or shrinks, a layout can
    // move that natural spot (centred items, fill-width rows, right / bottom anchored items) and the piece would travel with it.
    // So while Settings edits: if the popup's size changed a moment ago and the natural spot of a moved piece (measured in the
    // popup's own coordinates, ignoring every transform) changed, the offset is corrected by exactly that much, in the same frame.
    // The corrections are kept in `_adj` (shown at once) and written to the saved layout once, when the resizing pauses.
    property var _nat: ({})              // key -> natural position in the popup's coordinates
    property var _adj: ({})              // key -> { x, y } correction not saved yet
    property real _stampT: 0
    property real _lw: 0
    property real _lh: 0
    property var _watched: []
    property var _watchObjs: []
    function _resizing() { return Date.now() - arr._stampT < 400 }
    function _natRoot(b) {
        const root = arr.parent
        if (!root || !b) return null
            let x = b.x, y = b.y
            let p = b.parent
            let guard = 0
            while (p && p !== root && guard++ < 40) { x += p.x; y += p.y; p = p.parent }
            return p === root ? { x: x, y: y } : null
    }
    function _drift() {
        if (!arr.editing) return
            const rs = arr._resizing(), en = arr._entryWin()
            if (!rs && !en) return
                let any = false
                for (let i = 0; i < arr.entries.length; i++) {
                    const e = arr.entries[i]
                    if (!e.box) continue
                        const key = e.elementId, id = arr.popupId
                        if (PopupSettings.elemAlign(id, key) !== "") continue            // an aligned piece follows its parent on purpose
                            const was = PopupSettings.elemX(id, key) !== 0 || PopupSettings.elemY(id, key) !== 0 || !!arr._adj[key]
                            // a moved piece is held while the popup resizes or any piece changes size; an unmoved one only when ANOTHER piece changed size
                            if (!was && !(en && !arr._changed[key])) continue
                                const n = arr._natRoot(e.box), o = arr._nat[key]
                                if (!n) continue
                                    arr._nat[key] = n
                                    if (!o) continue
                                        const dx = n.x - o.x, dy = n.y - o.y
                                        if (Math.abs(dx) < 0.01 && Math.abs(dy) < 0.01) continue
                                            const ad = arr._adj[key] || { x: 0, y: 0 }
                                            ad.x -= dx; ad.y -= dy
                                            arr._adj[key] = ad
                                            const tf = arr._tf(e.box)
                                            tf.tr.x -= dx; tf.tr.y -= dy
                                            any = true
                }
                if (any) flush.restart()
    }
    function flushAdj() {
        const id = arr.popupId
        const keys = Object.keys(arr._adj)
        if (keys.length === 0) return
            const adj = arr._adj
            arr._adj = ({})
            for (let i = 0; i < keys.length; i++) {
                const k = keys[i]
                PopupSettings.patchElem(id, k, { x: PopupSettings.elemX(id, k) + adj[k].x, y: PopupSettings.elemY(id, k) + adj[k].y })
            }
    }
    // watch the piece and every ancestor up to the popup's root: any of them moving is a natural-position change
    function _watch(it) {
        if (!it || it === arr.parent || arr._watched.indexOf(it) >= 0) return
            const w = Qt.createQmlObject('import QtQuick; Connections { property var pa; ignoreUnknownSignals: true; function onXChanged() { pa._drift() } function onYChanged() { pa._drift() } }', arr)
            w.pa = arr
            w.target = it
            arr._watched.push(it)
            arr._watchObjs.push(w)
    }
    function _watchAll() {
        for (let i = arr._watched.length - 1; i >= 0; i--) {
            if (!arr._watched[i]) { arr._watchObjs[i].destroy(); arr._watched.splice(i, 1); arr._watchObjs.splice(i, 1) }
        }
        if (!arr.editing) return
            for (let i = 0; i < arr.entries.length; i++) {
                let p = arr.entries[i].box
                let guard = 0
                while (p && p !== arr.parent && guard++ < 40) { arr._watch(p); p = p.parent }
            }
    }
    // Remember where each moved piece's centre is as a fraction of the panel, and the panel size, next to its pixel offset.
    function _stamp() {
        arr.flushAdj()
        const root = arr.parent
        if (!root || root.width <= 0 || root.height <= 0) return
            const id = arr.popupId
            for (let i = 0; i < arr.entries.length; i++) {
                const e = arr.entries[i]
                const b = e.box
                if (!b || b.width <= 0 || b.height <= 0) continue
                    const key = e.elementId
                    if (PopupSettings.elemX(id, key) === 0 && PopupSettings.elemY(id, key) === 0) continue
                        if (PopupSettings.elemAlign(id, key) !== "") continue
                            const c = b.mapToItem(root, b.width / 2, b.height / 2)
                            const fx = Math.round(c.x / root.width * 10000) / 10000, fy = Math.round(c.y / root.height * 10000) / 10000
                            const cx = PopupSettings.elemFx(id, key), cy = PopupSettings.elemFy(id, key)
                            if (cx === undefined || cy === undefined || Math.abs(cx - fx) > 0.0006 || Math.abs(cy - fy) > 0.0006
                                || PopupSettings.elemPw(id, key) !== Math.round(root.width) || PopupSettings.elemPh(id, key) !== Math.round(root.height))
                                PopupSettings.patchElem(id, key, { fx: fx, fy: fy, pw: root.width, ph: root.height })
            }
    }
    Timer { id: stamp; interval: 300; onTriggered: arr._stamp() }
    Timer { id: flush; interval: 250; onTriggered: arr.flushAdj() }
    Connections {
        target: arr.parent
        ignoreUnknownSignals: true
        function onWidthChanged() { if (arr._lw > 0) arr._stampT = Date.now(); arr._lw = arr.parent.width }
        function onHeightChanged() { if (arr._lh > 0) arr._stampT = Date.now(); arr._lh = arr.parent.height }
    }
    Component.onDestruction: { if (arr.editing) arr._stamp(); else arr.flushAdj() }

    // A popup with a saved layout looks for its pieces right away and keeps looking for the first seconds (the popup is still
    // sliding in and its lists are still filling), so the layout is already there when it appears and not applied a moment later.
    Timer {
        id: burst
        interval: 100; repeat: true
        property int n: 0
        onTriggered: { if (arr.wanted) arr.scan(); if (++burst.n >= 30) burst.stop() }
    }
    // lists that fill in later: keep picking them up while a layout is saved (or while Settings is editing)
    Timer { interval: 600; repeat: true; running: arr.visible && arr.wanted; onTriggered: arr.scan() }
    Connections { target: PopupSettings; function onCfgChanged() { Qt.callLater(arr.apply) } }
    onEditingChanged: { if (arr.editing) arr.scan(); else arr._stamp() }
    Component.onCompleted: { arr._lw = arr.parent ? arr.parent.width : 0; arr._lh = arr.parent ? arr.parent.height : 0; if (arr.wanted) arr.scan(); burst.start() }
}
