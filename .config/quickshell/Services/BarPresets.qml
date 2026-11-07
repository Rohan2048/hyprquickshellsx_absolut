pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * BarPresets.qml -- Settings > Bar > Presets: your own bar layouts. Main shell only.
 *
 * A preset is a set of mini bars. Each mini bar sits on one screen edge (several can share
 * an edge or use different ones), has its own size / alignment / auto-hide / scale / roundness /
 * background / module list. With no preset applied the shell shows the classic single bar from
 * Services/BarSettings.qml (the "Default" preset), exactly as before.
 *
 * ~/.config/quickshell/state/bar-presets.json (watched):
 *   { "active": "<preset id>" | "",
 *     "presets": [ { "id", "name", "bars": [ { "id", "edge": "top|bottom|left|right",
 *        "align": "start|center|end", "offset": px, "sizeMode": "fit|fill|fixed", "lengthPx": px,
 *        "autohide": bool, "scalePct": 70-160, "roundnessPct": 0-100, "bg": "theme|transparent",
 *        "popupMode": "float|merge", "modules": [ ids in order ],
 *        "places": null | { "<module id>": px } } ] } ] }
 *
 * "places" = free layout: each module sits at its own distance (px, unscaled units) from the start of
 * the bar's content area, with room left between icons. null = the icons flow one after another.
 *
 * Bars are keyed by their id, so editing a bar changes the live window instead of rebuilding it.
 * `previewData` (not saved) is what Settings shows on screen while a draft is being previewed.
 *
 * While any popup or app-tray thumbnail of any mini bar is open, every mini bar of the preset
 * stays shown (see setBusy / anyBusy).
 *
 *   qs ipc call barpreset apply <preset id | default>
 *   qs ipc call barpreset list
 */
Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.config/quickshell/state/bar-presets.json"

    // every module a mini bar can hold (the first 11 are the classic bar's items)
    readonly property var moduleIds: ["power", "music", "apps", "wifi", "bluetooth", "volume", "battery", "clock", "stopwatch", "timer", "bell", "workspaces",
    "launcher", "settings", "lock", "commands", "shortcuts", "overview", "display", "schedule"]
    readonly property var moduleNames: ({
        "power": "Power", "music": "Music", "apps": "App tray", "wifi": "Wi-Fi",
        "bluetooth": "Bluetooth", "volume": "Volume", "battery": "Battery",
        "clock": "Clock", "stopwatch": "Stopwatch", "timer": "Timer", "bell": "Notifications",
        "workspaces": "Workspaces 0-9",
        "launcher": "Button: App launcher", "settings": "Button: Settings", "lock": "Button: Lock",
        "commands": "Button: Commands palette", "shortcuts": "Button: Shortcuts palette",
        "overview": "Button: Workspace overview", "display": "Button: Display toggle", "schedule": "Button: Power schedule"
    })

    property string active: ""
    property var presets: []
    property var previewData: null            // a preset object being previewed, or null
    property bool _ready: false
    property string _lastWritten: ""

    function presetById(id) {
        for (let i = 0; i < root.presets.length; i++) if (root.presets[i].id === id) return root.presets[i]
            return null
    }
    readonly property var effective: root.previewData !== null ? root.previewData : root.presetById(root.active)
    readonly property bool custom: root.effective !== null && root.effective !== undefined && Array.isArray(root.effective.bars) && root.effective.bars.length > 0

    // ids of the bar windows to create
    readonly property var barIds: {
        if (!root.custom) return ["default"]
            return root.effective.bars.map(function (b) { return b.id })
    }
    function barData(id) {
        if (!root.custom) return null
            const l = root.effective.bars
            for (let i = 0; i < l.length; i++) if (l[i].id === id) return l[i]
                return null
    }

    // ---- which bar reserves screen space on an edge ----
    // Several docked (auto-hide off) bars on one edge must not stack their reservations:
    // the thickest one reserves, the others sit inside that space.
    function _thick(b) { return (b.edge === "left" || b.edge === "right" ? 48 : 40) * (b.scalePct / 100) }
    function reserverId(edge) {
        if (!root.custom) return ""
            let best = null
            const l = root.effective.bars
            for (let i = 0; i < l.length; i++) {
                const b = l[i]
                if (b.edge !== edge || b.autohide) continue
                    if (best === null || root._thick(b) > root._thick(best)) best = b
            }
            return best ? best.id : ""
    }

    // ---- group reveal ----
    // Bars report here while one of their popups / thumbnails is open; all bars of a preset
    // then stay shown, so the whole set never half-vanishes behind an open popup.
    property var busyMap: ({})
    readonly property bool anyBusy: {
        const m = root.busyMap
        for (const k in m) if (m[k]) return true
            return false
    }
    function setBusy(id, on) {
        if (!!root.busyMap[id] === !!on) return
            const m = Object.assign({}, root.busyMap)
            if (on) m[id] = true; else delete m[id]
                root.busyMap = m
    }

    // ---- defaults / normalising ----
    function newId(prefix) {
        return prefix + Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36)
    }
    function newBar() {
        return {
            id: root.newId("b"), edge: "bottom", align: "center", offset: 0,
            sizeMode: "fit", lengthPx: 600, autohide: false, scalePct: 100, roundnessPct: 100,
            bg: "theme", popupMode: "float",
            modules: ["clock", "battery"], places: null
        }
    }
    function newPreset() {
        return { id: root.newId("p"), name: "My bar", bars: [root.newBar()] }
    }
    function clone(o) { return JSON.parse(JSON.stringify(o)) }

    function _normBar(b) {
        const d = root.newBar()
        const o = (b && typeof b === "object") ? b : {}
        const r = {}
        r.id = (typeof o.id === "string" && o.id !== "") ? o.id : d.id
        r.edge = ["top", "bottom", "left", "right"].indexOf(o.edge) >= 0 ? o.edge : d.edge
        r.align = ["start", "center", "end"].indexOf(o.align) >= 0 ? o.align : d.align
        r.offset = typeof o.offset === "number" ? Math.max(0, Math.min(4000, Math.round(o.offset))) : 0
        r.sizeMode = ["fit", "fill", "fixed"].indexOf(o.sizeMode) >= 0 ? o.sizeMode : d.sizeMode
        r.lengthPx = typeof o.lengthPx === "number" ? Math.max(60, Math.min(4000, Math.round(o.lengthPx))) : d.lengthPx
        r.autohide = o.autohide === undefined ? true : !!o.autohide
        r.scalePct = typeof o.scalePct === "number" ? Math.max(70, Math.min(160, Math.round(o.scalePct))) : 100
        r.roundnessPct = typeof o.roundnessPct === "number" ? Math.max(0, Math.min(100, Math.round(o.roundnessPct))) : 100
        r.bg = o.bg === "transparent" ? "transparent" : "theme"
        r.popupMode = o.popupMode === "merge" ? "merge" : "float"
        const mods = []
        if (Array.isArray(o.modules))
            for (let i = 0; i < o.modules.length; i++) {
                const m = String(o.modules[i])
                if (root.moduleIds.indexOf(m) >= 0 && mods.indexOf(m) < 0) mods.push(m)
            }
            r.modules = mods
            // free layout: a px offset per module (only for modules the bar has); none = the icons flow
            let pl = null
            if (o.places && typeof o.places === "object" && !Array.isArray(o.places)) {
                pl = {}
                for (const k in o.places)
                    if (mods.indexOf(k) >= 0 && typeof o.places[k] === "number" && isFinite(o.places[k]))
                        pl[k] = Math.max(0, Math.min(8000, Math.round(o.places[k])))
                        if (Object.keys(pl).length === 0) pl = null
            }
            r.places = pl
            return r
    }
    function normPreset(p) {
        const o = (p && typeof p === "object") ? p : {}
        const seen = {}
        const bars = []
        const src = Array.isArray(o.bars) ? o.bars : []
        for (let i = 0; i < src.length && bars.length < 8; i++) {
            const b = root._normBar(src[i])
            while (seen[b.id]) b.id = root.newId("b")
                seen[b.id] = true
                bars.push(b)
        }
        return {
            id: (typeof o.id === "string" && o.id !== "") ? o.id : root.newId("p"),
            name: (typeof o.name === "string" && o.name.trim() !== "") ? o.name.trim().slice(0, 40) : "Preset",
            bars: bars
        }
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
        root.previewData = null
        root.active = (id !== "" && root.presetById(id) !== null) ? id : ""
        root._save()
    }

    // ---- persistence ----
    function _load(raw) {
        if (raw === root._lastWritten) return
            let d
            try { d = JSON.parse(raw) } catch (e) { root._ready = true; return }
            if (!d || typeof d !== "object") { root._ready = true; return }
            const l = Array.isArray(d.presets) ? d.presets.map(root.normPreset) : []
            root.presets = l
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
        target: "barpreset"
        function apply(id: string): string {
            root.apply(id === "default" ? "" : id)
            return root.active === "" ? "default" : root.active
        }
        function list(): string {
            return JSON.stringify(root.presets.map(function (p) { return { id: p.id, name: p.name } }))
        }
    }
}
