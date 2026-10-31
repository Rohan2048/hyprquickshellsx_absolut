pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Theme"

/**
 * LockPresets.qml -- Settings > Lock screen: your own lock screen layouts. Main shell only.
 *
 * With no preset applied the lock screen looks exactly as it always did (`classic()`).
 * A preset moves things and adds a background / shapes. The password, unlocking and the power
 * buttons' behaviour are never touched, only where things sit and how they look.
 *
 * ~/.config/quickshell/state/lock-presets.json (watched):
 *   { "active": "<preset id>" | "", "presets": [ { "id", "name", "layout": { ... } } ] }
 *
 * layout (positions are fractions 0..1 of the room an element has, so they follow any screen size;
 * 0 = flush with the left / top, 1 = flush with the right / bottom, 0.5 = centred):
 *   clock     { fx, fy, showDate, sx, sy }      sx / sy = stretch factors (1 = normal) of the clock + date block
 *   password  { follow: true  -> sits under the clock like always,
 *               follow: false -> free at fx, fy }
 *   power     { fx, fy, sx, sy, radius }   suspend / restart / power off; radius = corner radius of the buttons (px, -1 = normal)
 *   settings  { fx, fy, sx, sy, radius, push, panelSide, panelX, panelY, contentX, contentY }  quick-settings button;
 *             push = move the clock away while its panel is open; panelSide = "auto" | "above" | "below" |
 *             "left" | "right" (where the panel opens from the button), panelX / panelY = offset of the panel,
 *             contentX / contentY = offset of what is inside the panel (px)
 *   battery   { fx, fy, sx, sy }
 *   user      { show, fx, fy, showPfp, showName, pfp ("" = the system's picture), size (px) }
 *   text      { mode: "theme" | "solid" | "gradient", color, stops, horizontal }  the clock / date / name colour;
 *             drawn as real coloured text (a gradient is a true gradient, never a tint laid over the text)
 *   bg        { mode: "blur" | "wallpaper", path, dim }   dim = darkening in percent
 *   shapes    [ { id, kind: "rect" | "ellipse" | "arrow" | "star" | "polygon", filled, stroke,
 *                 fx, fy, fw, fh (fractions of the screen), fill: <theme fill def>,
 *                 radius (rect: corner radius px, 0 = square), points + inner (star), sides (polygon),
 *                 arrowDir "right|left|up|down" + arrowDouble + shaft + head (arrow) } ]
 *             (the older kind "rounded" is read as a rect with radius 24)
 *   notes     [ { id, kind: "message" | "signature", fx, fy, sx, sy, text, size, pen, color, strokes } ]
 *             a line of text you wrote / your handwritten signature (strokes: lists of x, y pairs, 0..1 of a
 *             300 x 120 pad); color = { mode: "theme" | "solid" | "gradient", color, stops, horizontal }
 *
 *   qs ipc call lockpreset apply <preset id | default>
 */
Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.config/quickshell/state/lock-presets.json"

    property string active: ""
    property var presets: []
    property bool _ready: false
    property string _lastWritten: ""

    readonly property int margin: 24          // gap kept from the screen edge by the corner elements

    function clone(o) { return JSON.parse(JSON.stringify(o)) }
    function newId(prefix) { return prefix + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36) }
    function _clamp(v, lo, hi, d) { const n = Number(v); return isFinite(n) ? Math.max(lo, Math.min(hi, n)) : d }

    // ---- the look the lock screen always had ----
    function classic() {
        return {
            clock: { fx: 0.5, fy: 0.5, showDate: true, sx: 1, sy: 1 },
            password: { follow: true, fx: 0.5, fy: 0.62 },
            power: { fx: 0.5, fy: 0, sx: 1, sy: 1, radius: -1 },
            settings: { fx: 1, fy: 0, sx: 1, sy: 1, radius: -1, push: true, panelSide: "auto", panelX: 0, panelY: 0, contentX: 0, contentY: 0 },
            battery: { fx: 1, fy: 1, sx: 1, sy: 1 },
            user: { show: false, fx: 0.5, fy: 0.12, showPfp: true, showName: true, pfp: "", size: 96 },
            text: { mode: "theme", color: { mode: "dyn", i: 7 },
            stops: [{ mode: "dyn", i: 7 }, { mode: "dyn", i: 3 }], horizontal: true },
            bg: { mode: "blur", path: "", dim: 40 },
            shapes: [],
            notes: []
        }
    }
    // the text colour of a layout as the real thing draws it: a solid colour, or a gradient (else null)
    function textColor(l) {
        const t = l.text
        if (t.mode === "solid") return Theme.colorOf(t.color, Theme.effectiveDark, true)
            return Theme.foreground
    }
    function textGrad(l) {
        const t = l.text
        if (t.mode !== "gradient" || !t.stops || t.stops.length < 2) return null
            const cols = []
            for (let i = 0; i < t.stops.length && i < 6; i++) cols.push(Theme.colorOf(t.stops[i], Theme.effectiveDark, true))
                return { colors: cols, horizontal: t.horizontal !== false }
    }
    // the colour / gradient of a note ({ mode, color, stops, horizontal }) as the real thing draws it
    function specColor(t) {
        if (t && t.mode === "solid") return Theme.colorOf(t.color, Theme.effectiveDark, true)
            return Theme.foreground
    }
    function specGrad(t) {
        if (!t || t.mode !== "gradient" || !t.stops || t.stops.length < 2) return null
            const cols = []
            for (let i = 0; i < t.stops.length && i < 6; i++) cols.push(Theme.colorOf(t.stops[i], Theme.effectiveDark, true))
                return { colors: cols, horizontal: t.horizontal !== false }
    }
    function newFill() {
        return {
            type: "solid", opacity: 60, brightness: 0,
            color: { mode: "dyn", i: 3 },
            stops: [{ mode: "dyn", i: 1 }, { mode: "dyn", i: 3 }], horizontal: false,
            image: "", tile: false, tint: { mode: "dyn", i: 1 }, tintAmt: 0
        }
    }
    function newShape(kind) {
        return { id: root.newId("s"), kind: kind || "rect", filled: true, stroke: 3,
            fx: 0.35, fy: 0.3, fw: 0.3, fh: 0.4, fill: root.newFill(),
            radius: kind === "rect" ? 24 : 0, points: 5, inner: 45, sides: 6,
            arrowDir: "right", arrowDouble: false, shaft: 40, head: 35 }
    }
    function newTextSpec() {
        return { mode: "theme", color: { mode: "dyn", i: 7 },
        stops: [{ mode: "dyn", i: 7 }, { mode: "dyn", i: 3 }], horizontal: true }
    }
    function newNote(kind) {
        return { id: root.newId("n"), kind: kind === "signature" ? "signature" : "message",
            fx: 0.5, fy: 0.8, sx: 1, sy: 1, text: "Hello", size: 40, pen: 3,
            color: root.newTextSpec(), strokes: [] }
    }
    function newPreset() { return { id: root.newId("p"), name: "My lock screen", layout: root.classic() } }

    function _normShape(s) {
        const o = (s && typeof s === "object") ? s : {}
        const d = root.newShape("rect")
        const fill = (o.fill && typeof o.fill === "object") ? o.fill : d.fill
        const kinds = ["rect", "ellipse", "arrow", "star", "polygon"]
        // older layouts: "rounded" was a rectangle with fixed round corners, "rect" a square one
        const kind = o.kind === "rounded" ? "rect" : (kinds.indexOf(o.kind) >= 0 ? o.kind : "rect")
        const radius = o.kind === "rounded" ? 24 : (typeof o.radius === "number" ? root._clamp(o.radius, 0, 400, 0) : (kind === "rect" ? 0 : 0))
        return {
            id: (typeof o.id === "string" && o.id !== "") ? o.id : d.id,
            kind: kind,
            filled: o.filled !== false,
            stroke: root._clamp(o.stroke, 1, 40, 3),
            fx: root._clamp(o.fx, -0.5, 1.5, d.fx), fy: root._clamp(o.fy, -0.5, 1.5, d.fy),
            fw: root._clamp(o.fw, 0.02, 2, d.fw), fh: root._clamp(o.fh, 0.02, 2, d.fh),
            fill: fill,
            radius: radius,
            points: Math.round(root._clamp(o.points, 3, 12, 5)),
            inner: Math.round(root._clamp(o.inner, 20, 90, 45)),
            sides: Math.round(root._clamp(o.sides, 3, 12, 6)),
            arrowDir: ["left", "up", "down"].indexOf(o.arrowDir) >= 0 ? o.arrowDir : "right",
            arrowDouble: o.arrowDouble === true,
            shaft: Math.round(root._clamp(o.shaft, 15, 80, 40)),
            head: Math.round(root._clamp(o.head, 15, 60, 35))
        }
    }
    function _normTextSpec(t) {
        const d = root.newTextSpec()
        const o = (t && typeof t === "object") ? t : {}
        const okCol = function (c, def) { return (c && typeof c === "object") ? c : def }
        const stops = []
        if (Array.isArray(o.stops))
            for (let i = 0; i < o.stops.length && i < 6; i++) stops.push(okCol(o.stops[i], { mode: "dyn", i: 7 }))
                return {
                    mode: ["solid", "gradient"].indexOf(o.mode) >= 0 ? o.mode : "theme",
                    color: okCol(o.color, d.color),
                    stops: stops.length >= 2 ? stops : d.stops,
                    horizontal: o.horizontal !== false
                }
    }
    function _normNote(n) {
        const o = (n && typeof n === "object") ? n : {}
        const d = root.newNote("message")
        const strokes = []
        if (Array.isArray(o.strokes))
            for (let i = 0; i < o.strokes.length && i < 300; i++) {
                const st = o.strokes[i]
                if (!Array.isArray(st) || st.length < 2) continue
                    const pts = []
                    for (let j = 0; j + 1 < st.length && j < 3000; j += 2)
                        pts.push(Math.round(root._clamp(st[j], 0, 1, 0) * 10000) / 10000, Math.round(root._clamp(st[j + 1], 0, 1, 0) * 10000) / 10000)
                        strokes.push(pts)
            }
            return {
                id: (typeof o.id === "string" && o.id !== "") ? o.id : d.id,
                kind: o.kind === "signature" ? "signature" : "message",
                fx: root._clamp(o.fx, 0, 1, 0.5), fy: root._clamp(o.fy, 0, 1, 0.8),
                sx: root._clamp(o.sx, 0.3, 4, 1), sy: root._clamp(o.sy, 0.3, 4, 1),
                text: typeof o.text === "string" ? o.text.slice(0, 400) : "Hello",
                size: Math.round(root._clamp(o.size, 12, 200, 40)),
                pen: Math.round(root._clamp(o.pen, 1, 12, 3)),
                color: root._normTextSpec(o.color),
                strokes: strokes
            }
    }
    function normLayout(l) {
        const c = root.classic()
        const o = (l && typeof l === "object") ? l : {}
        const pos = function (k, extra) {
            const src = (o[k] && typeof o[k] === "object") ? o[k] : {}
            const r = { fx: root._clamp(src.fx, 0, 1, c[k].fx), fy: root._clamp(src.fy, 0, 1, c[k].fy) }
            // clock, power, settings and battery can be stretched
            if (c[k].sx !== undefined) { r.sx = root._clamp(src.sx, 0.3, 4, 1); r.sy = root._clamp(src.sy, 0.3, 4, 1) }
            return Object.assign(r, extra(src))
        }
        const tx = (o.text && typeof o.text === "object") ? o.text : {}
        const okCol = function (c, d) { return (c && typeof c === "object") ? c : d }
        const stops = []
        if (Array.isArray(tx.stops))
            for (let i = 0; i < tx.stops.length && i < 6; i++) stops.push(okCol(tx.stops[i], { mode: "dyn", i: 7 }))
                const bgSrc = (o.bg && typeof o.bg === "object") ? o.bg : {}
                const notes = []
                if (Array.isArray(o.notes))
                    for (let i = 0; i < o.notes.length && i < 8; i++) notes.push(root._normNote(o.notes[i]))
                        const shapes = []
                        if (Array.isArray(o.shapes))
                            for (let i = 0; i < o.shapes.length && i < 40; i++) shapes.push(root._normShape(o.shapes[i]))
                                return {
                                    clock: pos("clock", function (s) { return { showDate: s.showDate !== false } }),
                                    password: pos("password", function (s) { return { follow: s.follow !== false } }),
                                    power: pos("power", function (s) { return { radius: root._clamp(s.radius, -1, 40, -1) } }),
                                    settings: pos("settings", function (s) {
                                        return { push: s.push !== false, radius: root._clamp(s.radius, -1, 40, -1),
                                            panelSide: ["above", "below", "left", "right"].indexOf(s.panelSide) >= 0 ? s.panelSide : "auto",
                                                  panelX: root._clamp(s.panelX, -600, 600, 0), panelY: root._clamp(s.panelY, -600, 600, 0),
                                                  contentX: root._clamp(s.contentX, -150, 150, 0), contentY: root._clamp(s.contentY, -150, 150, 0) }
                                    }),
                                    battery: pos("battery", function () { return {} }),
                                    user: pos("user", function (s) {
                                        return { show: s.show === true, showPfp: s.showPfp !== false, showName: s.showName !== false,
                                            pfp: typeof s.pfp === "string" ? s.pfp : "", size: root._clamp(s.size, 32, 240, 96) }
                                    }),
                                    text: {
                                        mode: ["solid", "gradient"].indexOf(tx.mode) >= 0 ? tx.mode : "theme",
                                        color: okCol(tx.color, c.text.color),
                                        stops: stops.length >= 2 ? stops : c.text.stops,
                                        horizontal: tx.horizontal !== false
                                    },
                                    bg: {
                                        mode: bgSrc.mode === "wallpaper" ? "wallpaper" : "blur",
                                        path: typeof bgSrc.path === "string" ? bgSrc.path : "",
                                        dim: root._clamp(bgSrc.dim, 0, 90, 40)
                                    },
                                    shapes: shapes,
                                    notes: notes
                                }
    }
    function normPreset(p) {
        const o = (p && typeof p === "object") ? p : {}
        return {
            id: (typeof o.id === "string" && o.id !== "") ? o.id : root.newId("p"),
            name: (typeof o.name === "string" && o.name.trim() !== "") ? o.name.trim().slice(0, 40) : "Lock screen",
            layout: root.normLayout(o.layout)
        }
    }

    function presetById(id) {
        for (let i = 0; i < root.presets.length; i++) if (root.presets[i].id === id) return root.presets[i]
            return null
    }
    // what the real lock screen uses
    readonly property var layout: {
        const p = root.presetById(root.active)
        return p ? p.layout : root.classic()
    }
    readonly property bool custom: root.presetById(root.active) !== null

    // ---- geometry shared by the lock screen and the editor preview ----
    // left / top edge of an element `itemLen` long inside `parentLen`, at fraction f
    function place(f, parentLen, itemLen, m) { return m + f * Math.max(0, parentLen - itemLen - 2 * m) }
    // inverse (used when dragging in the editor)
    function fraction(pos, parentLen, itemLen, m) {
        const room = parentLen - itemLen - 2 * m
        return room <= 0 ? 0.5 : Math.max(0, Math.min(1, (pos - m) / room))
    }
    // Where the settings button sits decides which way the clock is pushed while its panel is open:
    // right column -> left, left column -> right, centre column: top half -> down, else up.
    function pushVector(fx, fy, push, amount) {
        if (!push) return { dx: 0, dy: 0 }
        if (fx > 2 / 3) return { dx: -amount, dy: 0 }
        if (fx < 1 / 3) return { dx: amount, dy: 0 }
        return { dx: 0, dy: fy < 0.5 ? amount : -amount }
    }

    // Where the settings panel (pw x ph) opens, given the button (bx, by, bw, bh) on a screen sw x sh.
    // Always starts from the button: above / below it (aligned left / centre / right like the button's
    // column) or to its left / right (aligned top / middle / bottom like its row). "auto" = below in the
    // top half of the screen, above in the bottom half. Then the offsets, kept on screen.
    // Returns { x, y, origin } (origin = the Item.transformOrigin the panel grows from).
    function panelRect(s, bx, by, bw, bh, pw, ph, sw, sh, m) {
        const gap = 12
        const top = (by + bh / 2) < sh / 2
        const side = s.panelSide === "auto" ? (top ? "below" : "above") : s.panelSide
        const h = s.fx > 2 / 3 ? "right" : (s.fx < 1 / 3 ? "left" : "center")
        const v = s.fy < 1 / 3 ? "top" : (s.fy > 2 / 3 ? "bottom" : "middle")
        let x, y, o
        if (side === "below" || side === "above") {
            y = side === "below" ? by + bh + gap : by - gap - ph
            x = h === "right" ? bx + bw - pw : (h === "left" ? bx : bx + (bw - pw) / 2)
            const vert = side === "below" ? "Top" : "Bottom"
            o = vert + (h === "right" ? "Right" : (h === "left" ? "Left" : ""))
        } else {
            x = side === "right" ? bx + bw + gap : bx - gap - pw
            y = v === "top" ? by : (v === "bottom" ? by + bh - ph : by + (bh - ph) / 2)
            const hor = side === "right" ? "Left" : "Right"
            o = (v === "top" ? "Top" : (v === "bottom" ? "Bottom" : "")) + hor
        }
        x = Math.max(m, Math.min(sw - pw - m, x + s.panelX))
        y = Math.max(m, Math.min(sh - ph - m, y + s.panelY))
        const origins = { Top: Item.Top, Bottom: Item.Bottom, Left: Item.Left, Right: Item.Right,
            TopLeft: Item.TopLeft, TopRight: Item.TopRight, BottomLeft: Item.BottomLeft, BottomRight: Item.BottomRight }
            return { x: x, y: y, origin: origins[o] !== undefined ? origins[o] : Item.Center }
    }

    // ---- editing API ----
    function savePreset(p) {
        const n = root.normPreset(p)
        const l = root.presets.slice()
        let at = -1
        for (let i = 0; i < l.length; i++) if (l[i].id === n.id) { at = i; break }
        if (at >= 0) l[at] = n; else l.push(n)
            root.presets = l
            root._save()
            return n.id
    }
    function deletePreset(id) {
        root.presets = root.presets.filter(function (p) { return p.id !== id })
        if (root.active === id) root.active = ""
            root._save()
    }
    function apply(id) {
        root.active = (id !== "" && root.presetById(id) !== null) ? id : ""
        root._save()
    }

    // ---- persistence ----
    function _load(raw) {
        if (raw === root._lastWritten) return
            let d
            try { d = JSON.parse(raw) } catch (e) { root._ready = true; return }
            if (!d || typeof d !== "object") { root._ready = true; return }
            root.presets = Array.isArray(d.presets) ? d.presets.map(root.normPreset) : []
            root.active = (typeof d.active === "string" && root.presetById(d.active) !== null) ? d.active : ""
            root._ready = true
    }
    function _save() {
        const txt = JSON.stringify({ active: root.active, presets: root.presets }, null, 2)
        root._lastWritten = txt
        file.setText(txt)
    }

    FileView {
        id: file
        path: root.stateFile
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._load(text())
        onLoadFailed: (error) => { root._ready = true }
    }
    Component.onCompleted: {
        try { root._load(file.text()) } catch (e) { root._ready = true }
    }

    IpcHandler {
        target: "lockpreset"
        function apply(id: string): string {
            root.apply(id === "default" ? "" : id)
            return root.active === "" ? "default" : root.active
        }
        function list(): string {
            return JSON.stringify(root.presets.map(function (p) { return { id: p.id, name: p.name } }))
        }
    }
}
