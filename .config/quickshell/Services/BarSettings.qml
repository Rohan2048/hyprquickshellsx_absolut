pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Theme"

/**
 * BarSettings.qml — persisted bar configuration (main shell only, SBS unaffected).
 *
 * Stored in ~/.config/quickshell/state/bar-settings.json, so every setting
 * survives reboot / re-login. The file is watched, so hand-edits apply live.
 *
 *   position   "bottom-center" | "top-center" | "left-center" | "right-center"
 *   autohide   true  -> bar slides away until hovered
 *              false -> always visible AND reserves screen space
 *   fillScreen true  -> bar spans the whole screen edge to edge
 *              false -> bar fits its content
 *   extras     which of the optional buttons (extraIds) are switched on; they sit in `order` too
 *   order      icon order: every item of defaultOrder (nothing of those can be removed) plus the
 *              switched-on extras, in any order
 *   scalePct   whole-bar scale in percent (70-160, default 100)
 *   roundnessPct  corner roundness of the floating pill in percent (0-100, 100 = full pill);
 *              only used while autohide is on (a docked bar is always square)
 *
 * Live control:
 *   qs ipc call bar position top-center
 *   qs ipc call bar autohide off|on|toggle
 *   qs ipc call bar fill full|fit|toggle
 *   qs ipc call bar extra lock on|off|toggle      (extras: launcher settings lock commands shortcuts overview display schedule workspaces)
 *   qs ipc call bar swap wifi bluetooth
 *   qs ipc call bar move bell 0
 *   qs ipc call bar order power,music,apps,wifi,bluetooth,volume,battery,clock,stopwatch,timer,bell
 *   qs ipc call bar scale 120
 *   qs ipc call bar roundness 60
 *   qs ipc call bar reset
 *   qs ipc call bar status
 */
Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.config/quickshell/state/bar-settings.json"

    readonly property var validPositions: ["bottom-center", "top-center", "left-center", "right-center"]
    readonly property var defaultOrder: ["power", "music", "apps", "wifi", "bluetooth", "volume", "battery", "clock", "stopwatch", "timer", "bell"]

    // The optional items (same ones a preset bar can hold; "workspaces" is the 1 2 ... 9 0 switcher). Off by default, so the classic bar is unchanged.
    readonly property var extraIds: ["launcher", "settings", "lock", "commands", "shortcuts", "overview", "display", "schedule", "workspaces"]
    property var extras: []
    // every item that is in the bar right now, in a fixed order (the Icon order editor lists these)
    readonly property var activeIds: defaultOrder.concat(extraIds.filter(function (id) { return extras.indexOf(id) >= 0 }))

    property string position: "bottom-center"
    property bool autohide: true
    property bool fillScreen: false
    property var order: ["power", "music", "apps", "wifi", "bluetooth", "volume", "battery", "clock", "stopwatch", "timer", "bell"]
    property int scalePct: 100
    property int roundnessPct: 100
    readonly property real scale: scalePct / 100

    readonly property string edge: position.split("-")[0]
    readonly property bool vertical: edge === "left" || edge === "right"
    // Cross-axis size of the bar: Theme.barHeight when horizontal, wider when vertical.
    readonly property real thickness: vertical ? 48 : Theme.barHeight

    property bool _ready: false

    function _normExtras(list) {
        var out = []
        if (Array.isArray(list))
            for (var i = 0; i < list.length; i++) {
                var id = String(list[i])
                if (extraIds.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
            }
            return out
    }

    // keeps what is in `list` (in its order) that the bar really has; then adds anything missing
    function _normalize(list, ex) {
        var on = ex !== undefined ? ex : extras
        var valid = defaultOrder.concat(extraIds.filter(function (id) { return on.indexOf(id) >= 0 }))
        var out = []
        if (Array.isArray(list)) {
            for (var i = 0; i < list.length; i++) {
                var id = String(list[i])
                if (valid.indexOf(id) >= 0 && out.indexOf(id) < 0) out.push(id)
            }
        }
        for (var j = 0; j < valid.length; j++) {
            if (out.indexOf(valid[j]) < 0) out.push(valid[j])
        }
        return out
    }

    function _apply(raw) {
        var d
        try { d = JSON.parse(raw) } catch (e) { _ready = true; return }
        if (!d || typeof d !== "object") { _ready = true; return }

        if (validPositions.indexOf(d.position) >= 0 && d.position !== position) position = d.position
            if (typeof d.autohide === "boolean" && d.autohide !== autohide) autohide = d.autohide
                if (typeof d.fillScreen === "boolean" && d.fillScreen !== fillScreen) fillScreen = d.fillScreen

                    if (typeof d.scalePct === "number") {
                        var sp = Math.max(70, Math.min(160, Math.round(d.scalePct)))
                        if (sp !== scalePct) scalePct = sp
                    }
                    if (typeof d.roundnessPct === "number") {
                        var rp = Math.max(0, Math.min(100, Math.round(d.roundnessPct)))
                        if (rp !== roundnessPct) roundnessPct = rp
                    }

                    var ex = _normExtras(d.extras !== undefined ? d.extras : extras)
                    if (JSON.stringify(ex) !== JSON.stringify(extras)) extras = ex
                        var o = _normalize(d.order !== undefined ? d.order : order, ex)
                        if (JSON.stringify(o) !== JSON.stringify(order)) order = o
                            _ready = true
    }

    function _save() {
        if (!_ready) return
            file.setText(JSON.stringify({
                position: position,
                autohide: autohide,
                fillScreen: fillScreen,
                scalePct: scalePct,
                roundnessPct: roundnessPct,
                extras: extras,
                order: order
            }, null, 2))
    }

    // Sliders fire continuously while dragging: apply instantly, write once settled.
    Timer { id: saveTimer; interval: 300; onTriggered: root._save() }

    FileView {
        id: file
        path: root.stateFile
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._apply(text())
        onLoadFailed: (error) => { root._ready = true }
    }

    Component.onCompleted: {
        try { _apply(file.text()) } catch (e) { _ready = true }
    }

    // ---------------- setters (all persist) ----------------
    function setPosition(p) {
        p = String(p).toLowerCase().trim()
        if (validPositions.indexOf(p) < 0) return false
            position = p
            _save()
            return true
    }
    function setAutohide(v) { autohide = !!v; _save() }
    function setFill(v) { fillScreen = !!v; _save() }
    function setScale(pct) {
        scalePct = Math.max(70, Math.min(160, Math.round(Number(pct))))
        saveTimer.restart()
    }
    function setRoundness(pct) {
        roundnessPct = Math.max(0, Math.min(100, Math.round(Number(pct))))
        saveTimer.restart()
    }

    function swap(a, b) {
        var o = order.slice()
        var i = o.indexOf(a), j = o.indexOf(b)
        if (i < 0 || j < 0) return false
            o[i] = b
            o[j] = a
            order = o
            _save()
            return true
    }
    function move(id, index) {
        if (order.indexOf(id) < 0) return false
            var o = order.filter(function (x) { return x !== id })
            o.splice(Math.max(0, Math.min(index, o.length)), 0, id)
            order = o
            _save()
            return true
    }
    function setOrder(list) {
        order = _normalize(list)
        _save()
    }
    // switch one optional button on / off; a button that is switched on joins the end of the bar
    function setExtra(id, on) {
        id = String(id)
        if (extraIds.indexOf(id) < 0) return false
            var ex = extras.filter(function (x) { return x !== id })
            if (on) ex.push(id)
                extras = ex
                order = _normalize(order, ex)
                _save()
                return true
    }
    function hasExtra(id) { return extras.indexOf(id) >= 0 }
    function reset() {
        position = "bottom-center"
        autohide = true
        fillScreen = false
        scalePct = 100
        roundnessPct = 100
        extras = []
        order = defaultOrder.slice()
        _save()
    }

    IpcHandler {
        target: "bar"

        function position(p: string): string {
            return root.setPosition(p) ? "ok" : "invalid, use: " + root.validPositions.join(", ")
        }
        function autohide(mode: string): string {
            if (mode === "toggle") root.setAutohide(!root.autohide)
                else if (mode === "on") root.setAutohide(true)
                    else if (mode === "off") root.setAutohide(false)
                        else return "use: on | off | toggle"
                            return "autohide " + (root.autohide ? "on" : "off")
        }
        function fill(mode: string): string {
            if (mode === "toggle") root.setFill(!root.fillScreen)
                else if (mode === "full") root.setFill(true)
                    else if (mode === "fit") root.setFill(false)
                        else return "use: full | fit | toggle"
                            return root.fillScreen ? "full" : "fit"
        }
        function extra(id: string, mode: string): string {
            if (root.extraIds.indexOf(id) < 0) return "unknown button, use: " + root.extraIds.join(", ")
                if (mode === "toggle") root.setExtra(id, !root.hasExtra(id))
                    else if (mode === "on") root.setExtra(id, true)
                        else if (mode === "off") root.setExtra(id, false)
                            else return "use: on | off | toggle"
                                return id + " " + (root.hasExtra(id) ? "on" : "off")
        }
        function swap(a: string, b: string): string {
            return root.swap(a, b) ? root.order.join(",") : "unknown id, valid: " + root.activeIds.join(",")
        }
        function move(id: string, index: int): string {
            return root.move(id, index) ? root.order.join(",") : "unknown id, valid: " + root.activeIds.join(",")
        }
        function order(csv: string): string {
            root.setOrder(csv.split(",").map(function (s) { return s.trim() }))
            return root.order.join(",")
        }
        function scale(pct: int): string {
            root.setScale(pct)
            return "scale " + root.scalePct + "%"
        }
        function roundness(pct: int): string {
            root.setRoundness(pct)
            return "roundness " + root.roundnessPct + "%"
        }
        function reset(): void { root.reset() }
        function status(): string {
            return JSON.stringify({ position: root.position, autohide: root.autohide, fillScreen: root.fillScreen, scalePct: root.scalePct, roundnessPct: root.roundnessPct, extras: root.extras, order: root.order })
        }
    }
}
