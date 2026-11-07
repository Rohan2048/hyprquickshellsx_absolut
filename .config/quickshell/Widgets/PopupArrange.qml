import QtQuick
import "../Services"

// Makes the pieces of a popup movable and scalable from Settings > Popups > Popup styles WITHOUT wrapping each
// one by hand. Drop one into a popup's content:
//
//     PopupArrange { containers: [contentCol] }
//
// It finds, inside the popup,
//   * every direct child of the containers you list (a row, a header, a list, a graph ...), and
//   * every GlassButton anywhere (found by its label), and every other clickable control built from an Item with a
//     MouseArea (found by its label),
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
    property bool editing: false

    // for the layout editor
    readonly property bool arrangeHost: true
    property var entries: []                       // [{ elementId, box, label }]

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

    function scan() {
        const out = []
        const used = {}
        function uniq(k) { let n = used[k] || 0; used[k] = n + 1; return n === 0 ? k : k + "#" + (n + 1) }

        // 1. direct children of the containers
        for (let ci = 0; ci < arr.containers.length; ci++) {
            const c = arr.containers[ci]
            if (!c) continue
                const kids = c.children
                for (let i = 0; i < kids.length; i++) {
                    const o = kids[i]
                    if (o === arr || arr._isRepeater(o) || o.elementId !== undefined || o.isGlassButton === true) continue
                        if (!(o.width > 0 || o.implicitWidth > 0)) continue
                            const lab = arr._label(o, 0)
                            const key = uniq("c" + ci + ":" + (lab !== "" ? arr._slug(lab) : "#" + i))
                            out.push({ elementId: key, box: o, label: lab !== "" ? lab : "Section " + (i + 1) })
                }
        }
        // 2. every button: a GlassButton, or any labelled item with a MouseArea of its own
        if (arr.includeButtons) {
            const roots = arr.containers.filter(c => !!c)
            const seen = out.map(e => e.box)
            function clickable(o) {
                const k = o.children
                for (let i = 0; i < k.length; i++) if (k[i].acceptedButtons !== undefined && k[i].containsMouse !== undefined) return true
                    return false
            }
            function walk(it) {
                const kids = it.children
                for (let i = 0; i < kids.length; i++) {
                    const o = kids[i]
                    const isGB = o.isGlassButton === true
                    if ((isGB || (o.elementId === undefined && clickable(o))) && seen.indexOf(o) < 0) {
                        const lab = arr._slug(arr._label(o, 0))
                        if (lab !== "" && o.width > 0 && o.height > 0) {
                            seen.push(o)
                            out.push({ elementId: uniq("btn:" + lab), box: o, label: lab })
                        }
                    }
                    if (!isGB) walk(o)
                }
            }
            for (let r = 0; r < roots.length; r++) walk(roots[r])
        }
        arr.entries = out
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
    property var _orig: ({})            // what a piece looked like before Settings changed it
    function _haOf(a) { return a === "l" ? Text.AlignLeft : (a === "r" ? Text.AlignRight : Text.AlignHCenter) }
    function _qtOf(a) { return a === "l" ? Qt.AlignLeft : (a === "r" ? Qt.AlignRight : Qt.AlignHCenter) }
    function _inLayout(b) { return !!b.parent && String(b.parent).indexOf("Layout") >= 0 }
    function apply() {
        const id = arr.popupId
        for (let i = 0; i < arr.entries.length; i++) {
            const e = arr.entries[i]
            if (!e.box) continue
                const key = e.elementId
                const b = e.box
                const x = PopupSettings.elemX(id, key), y = PopupSettings.elemY(id, key)
                const al = PopupSettings.elemAlign(id, key)
                const fs = PopupSettings.elemFs(id, key)
                const isBtn = b.isGlassButton === true
                const sw = isBtn ? PopupSettings.elemW(id, key) / 100 : 1
                const sh = isBtn ? PopupSettings.elemH(id, key) / 100 : 1
                const p = isBtn ? 100 : PopupSettings.elemPct(id, key)      // buttons stretch, everything else scales
                const tx = PopupSettings.elemTx(id, key), ty = PopupSettings.elemTy(id, key)

                if (isBtn) {
                    // the button itself: size, label alignment, label size and label offset
                    if (b.stretchW !== sw) b.stretchW = sw
                        if (b.stretchH !== sh) b.stretchH = sh
                            b.labelAlign = al !== "" ? arr._qtOf(al) : Qt.AlignHCenter
                            b.fontScale = fs / 100
                            b.textDx = tx; b.textDy = ty
                            // outside a layout the size is set here, and only for a button that is actually stretched (and put back
                            // when the stretch is cleared), so a button whose size the popup binds itself is never touched
                            if (!arr._inLayout(b)) {
                                if (sw !== 1) { b.width = b.implicitWidth * sw; arr._orig[key + "#w"] = true }
                                else if (arr._orig[key + "#w"]) { b.width = b.implicitWidth; delete arr._orig[key + "#w"] }
                                if (sh !== 1) { b.height = b.implicitHeight * sh; arr._orig[key + "#h"] = true }
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
                if (al !== "" && !isBtn && b.parent) {
                    const pw = b.parent.width
                    dx = al === "l" ? -b.x : (al === "c" ? (pw - b.width) / 2 - b.x : pw - b.width - b.x)
                }
                const moved = x !== 0 || y !== 0 || p !== 100 || dx !== 0
                let has = false
                const list = b.transform
                for (let j = 0; j < list.length; j++) if (list[j].objectName === "pa-scale") { has = true; break }
                if (!moved && !has) continue
                    const t = arr._tf(b)
                    t.tr.x = x + dx; t.tr.y = y
                    t.sc.xScale = p / 100; t.sc.yScale = p / 100
        }
    }

    Timer { id: first; interval: 350; onTriggered: arr.scan() }
    Timer { id: later; interval: 1500; onTriggered: arr.scan() }
    // lists that fill in later: keep picking them up while a layout is saved (or while Settings is editing)
    Timer { interval: 1200; repeat: true; running: arr.visible && arr.wanted; onTriggered: arr.scan() }
    Timer { id: soon; interval: 16; onTriggered: arr.apply() }
    Connections { target: PopupSettings; function onCfgChanged() { soon.restart() } }
    onEditingChanged: if (arr.editing) arr.scan()
    Component.onCompleted: { first.start(); later.start() }
}
