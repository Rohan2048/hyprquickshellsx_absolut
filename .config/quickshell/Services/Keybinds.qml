pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Keybinds.qml — rebindable Hyprland keybinds (Settings -> Keybindings).
 *
 * Flow:
 *   - Only the keys YOU changed are stored, in
 *       ~/.config/quickshell/state/keybinds.json   (the source of truth)
 *   - ~700 ms after the last change a Lua override table is generated at
 *       ~/.config/quickshell/state/keybinds.lua
 *     and `hyprctl reload` is run once it is on disk (same pattern as SBS).
 *   - hyprland.lua reads that table through bindk(id, default, ...); a missing
 *     file or id just means "use the default".
 *
 * `defs` below must list the same ids / default combos as the bindk() calls in
 * hyprland.lua. Volume, brightness and the mouse drag/resize binds are not
 * rebindable here (they stay plain hl.bind lines in hyprland.lua).
 *
 * An override of "" means "unbound".
 *
 * Live control:
 *   qs ipc call keybinds status
 *   qs ipc call keybinds set lock "SUPER + ALT + L"
 *   qs ipc call keybinds reset lock          (or "all")
 *   qs ipc call keybinds apply               (re-generate + reload now)
 */
Singleton {
    id: root

    readonly property string stateDir: Quickshell.env("HOME") + "/.config/quickshell/state"
    readonly property string jsonPath: stateDir + "/keybinds.json"
    readonly property string luaPath: stateDir + "/keybinds.lua"

    // mode: "always" | "normal" (only outside SBS mode) | "sbs" (only in SBS mode)
    // kind: "combo" (modifiers + key) | "mod" (modifier(s) only; keys are fixed)
    readonly property var groups: ["Shell", "Apps", "System", "Media", "Windows", "Focus", "Workspaces"]
    readonly property var defs: [
        { id: "toggle_bar",      group: "Shell",   label: "Toggle bar",               def: "SUPER + SHIFT + T",      mode: "always", kind: "combo" },
        { id: "settings",        group: "Shell",   label: "Settings",                 def: "SUPER + SHIFT + A",      mode: "normal", kind: "combo" },
        { id: "commands",        group: "Shell",   label: "Commands",                 def: "SUPER + A",              mode: "normal", kind: "combo" },
        { id: "shortcuts",       group: "Shell",   label: "Shortcuts",                def: "SUPER + W",              mode: "normal", kind: "combo" },
        // { id: "music_picker",    group: "Shell",   label: "Music picker",             def: "SUPER + T",              mode: "always", kind: "combo" },
        { id: "screenshot",      group: "Shell",   label: "Screenshot",               def: "SUPER + S",              mode: "always", kind: "combo" },
        { id: "overview",        group: "Shell",   label: "Workspace overview",       def: "ALT + Tab",              mode: "always", kind: "combo" },
        { id: "lock",            group: "Shell",   label: "Lock screen",              def: "SUPER + L",              mode: "always", kind: "combo" },
        { id: "rofi_anim",       group: "Shell",   label: "Animation scale",          def: "ALT + R",                mode: "normal", kind: "combo" },
        { id: "sbs_hide",        group: "Shell",   label: "SBS: hide interface",      def: "CTRL + H",               mode: "sbs",    kind: "combo" },

        { id: "terminal",        group: "Apps",    label: "Terminal",                 def: "SUPER + Q",              mode: "always", kind: "combo" },
        { id: "files",           group: "Apps",    label: "File manager",             def: "SUPER + E",              mode: "always", kind: "combo" },
        { id: "launcher",        group: "Apps",    label: "App launcher",             def: "SUPER + R",              mode: "normal", kind: "combo" },
        { id: "clipboard",       group: "Apps",    label: "Clipboard history",        def: "SUPER + P",              mode: "always", kind: "combo" },

        { id: "powermenu",       group: "System",  label: "Power menu",               def: "SUPER + escape",         mode: "always", kind: "combo" },
        { id: "schedule",        group: "System",  label: "Schedule action",          def: "SUPER + SHIFT + escape", mode: "always", kind: "combo" },
        { id: "touchpad",        group: "System",  label: "Toggle touchpad",          def: "ALT + M",                mode: "always", kind: "combo" },
        { id: "hdmi",            group: "System",  label: "HDMI output",              def: "ALT + S",                mode: "always", kind: "combo" },
        { id: "hdmi_refresh",    group: "System",  label: "HDMI refresh",             def: "ALT + SHIFT + S",        mode: "always", kind: "combo" },
        { id: "vnc",             group: "System",  label: "VNC",                      def: "ALT + V",                mode: "always", kind: "combo" },
        { id: "wallpaper",       group: "System",  label: "Wallpaper switcher",       def: "SUPER + SHIFT + W",      mode: "normal", kind: "combo" },
        { id: "video_wallpaper", group: "System",  label: "Video wallpaper",          def: "SUPER + SHIFT + V",      mode: "always", kind: "combo" },

        { id: "player_next",     group: "Media",   label: "Next track",               def: "ALT + N",                mode: "always", kind: "combo" },
        { id: "player_prev",     group: "Media",   label: "Previous track",           def: "ALT + P",                mode: "always", kind: "combo" },
        { id: "media_next",      group: "Media",   label: "Next track (media key)",   def: "XF86AudioNext",          mode: "always", kind: "combo" },
        { id: "media_pause",     group: "Media",   label: "Pause (media key)",        def: "XF86AudioPause",         mode: "always", kind: "combo" },
        { id: "media_play",      group: "Media",   label: "Play / pause (media key)", def: "XF86AudioPlay",          mode: "always", kind: "combo" },
        { id: "media_prev",      group: "Media",   label: "Previous (media key)",     def: "XF86AudioPrev",          mode: "always", kind: "combo" },

        { id: "close",           group: "Windows", label: "Close window",             def: "SUPER + C",              mode: "always", kind: "combo" },
        { id: "float",           group: "Windows", label: "Toggle floating",          def: "SUPER + V",              mode: "always", kind: "combo" },
        { id: "split",           group: "Windows", label: "Toggle split",             def: "SUPER + J",              mode: "always", kind: "combo" },
        { id: "fullscreen",      group: "Windows", label: "Fullscreen",               def: "SUPER + F",              mode: "always", kind: "combo" },
        { id: "maximize",        group: "Windows", label: "Maximize",                 def: "SUPER + SHIFT + F",      mode: "always", kind: "combo" },
        { id: "minimize",        group: "Windows", label: "Minimize window",          def: "SUPER + N",              mode: "always", kind: "combo" },
        { id: "show_minimized",  group: "Windows", label: "Show minimized windows",   def: "SUPER + SHIFT + N",      mode: "always", kind: "combo" },

        { id: "focus_left",      group: "Focus",   label: "Focus left",               def: "SUPER + left",           mode: "always", kind: "combo" },
        { id: "focus_right",     group: "Focus",   label: "Focus right",              def: "SUPER + right",          mode: "always", kind: "combo" },
        { id: "focus_up",        group: "Focus",   label: "Focus up",                 def: "SUPER + up",             mode: "always", kind: "combo" },
        { id: "focus_down",      group: "Focus",   label: "Focus down",               def: "SUPER + down",           mode: "always", kind: "combo" },

        { id: "ws_goto",         group: "Workspaces", label: "Go to workspace 1-10 (modifier + 1..0)",         def: "SUPER",         mode: "always", kind: "mod" },
        { id: "ws_move",         group: "Workspaces", label: "Move window to workspace 1-10 (modifier + 1..0)", def: "SUPER + SHIFT", mode: "always", kind: "mod" }
    ]

    // id -> combo string, only for keys that differ from the default ("" = unbound)
    property var overrides: ({})
    property bool _ready: false

    readonly property var modOrder: ["SUPER", "CTRL", "ALT", "SHIFT"]
    readonly property var modLabels: ({ "SUPER": "Super", "CTRL": "Ctrl", "ALT": "Alt", "SHIFT": "Shift" })

    // ---------------- lookups ----------------
    function def(id) {
        for (var i = 0; i < defs.length; i++) if (defs[i].id === id) return defs[i]
            return null
    }
    function isOverridden(id) { return overrides[id] !== undefined }
    function effective(id) {
        if (overrides[id] !== undefined) return overrides[id]
            var d = def(id)
            return d ? d.def : ""
    }

    // ---------------- combo helpers ----------------
    function _modName(t) {
        t = t.toUpperCase()
        if (t === "CONTROL" || t === "CTRL") return "CTRL"
            if (t === "WIN" || t === "MOD4" || t === "SUPER") return "SUPER"
                if (t === "MOD1" || t === "ALT") return "ALT"
                    if (t === "SHIFT") return "SHIFT"
                        return ""
    }
    // "SUPER + SHIFT + T" -> { mods: ["SUPER","SHIFT"], key: "T" }
    function parse(c) {
        var toks = String(c).split("+").map(function (s) { return s.trim() }).filter(function (s) { return s.length > 0 })
        var mods = [], key = ""
        for (var i = 0; i < toks.length; i++) {
            var m = _modName(toks[i])
            if (m !== "") { if (mods.indexOf(m) < 0) mods.push(m) }
            else key = toks[i]
        }
        return { mods: sortMods(mods), key: key }
    }
    function sortMods(mods) {
        return modOrder.filter(function (m) { return mods.indexOf(m) >= 0 })
    }
    function compose(mods, key) {
        var parts = sortMods(mods)
        if (key !== "") parts.push(key)
            return parts.join(" + ")
    }
    function normalize(c) {
        var p = parse(c)
        return p.mods.join("+") + "|" + p.key.toLowerCase()
    }
    function display(c) {
        if (c === "") return "Unbound"
            var p = parse(c)
            var parts = p.mods.map(function (m) { return modLabels[m] })
            if (p.key !== "") {
                var k = p.key
                parts.push(k.length === 1 ? k.toUpperCase() : (k.charAt(0).toUpperCase() + k.slice(1)))
            }
            return parts.join(" + ")
    }

    function _modesOverlap(a, b) { return a === "always" || b === "always" || a === b }

    // Labels of the OTHER actions that currently use `combo`.
    function usersOf(id, combo) {
        if (combo === "") return []
            var d = def(id)
            var n = normalize(combo)
            var out = []
            for (var i = 0; i < defs.length; i++) {
                var o = defs[i]
                if (o.id === id || o.kind !== d.kind) continue
                    if (!_modesOverlap(d.mode, o.mode)) continue
                        var oc = effective(o.id)
                        if (oc !== "" && normalize(oc) === n) out.push(o.label)
            }
            return out
    }
    function conflictsOf(id) { return usersOf(id, effective(id)) }

    // ---------------- key names (Qt -> Hyprland/xkb) ----------------
    function isModifierKey(key) {
        return key === Qt.Key_Shift || key === Qt.Key_Control || key === Qt.Key_Alt
        || key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R
        || key === Qt.Key_AltGr || key === Qt.Key_CapsLock
    }
    function modOfKey(key) {
        if (key === Qt.Key_Shift) return "SHIFT"
            if (key === Qt.Key_Control) return "CTRL"
                if (key === Qt.Key_Alt || key === Qt.Key_AltGr) return "ALT"
                    if (key === Qt.Key_Meta || key === Qt.Key_Super_L || key === Qt.Key_Super_R) return "SUPER"
                        return ""
    }
    function keyName(key) {
        if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
            if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
                if (key >= Qt.Key_F1 && key <= Qt.Key_F35) return "F" + (key - Qt.Key_F1 + 1)
                    switch (key) {
                        // Shift+digit row (US layout)
                        case Qt.Key_Exclam: return "1"
                        case Qt.Key_At: return "2"
                        case Qt.Key_NumberSign: return "3"
                        case Qt.Key_Dollar: return "4"
                        case Qt.Key_Percent: return "5"
                        case Qt.Key_AsciiCircum: return "6"
                        case Qt.Key_Ampersand: return "7"
                        case Qt.Key_Asterisk: return "8"
                        case Qt.Key_ParenLeft: return "9"
                        case Qt.Key_ParenRight: return "0"
                        case Qt.Key_Left: return "left"
                        case Qt.Key_Right: return "right"
                        case Qt.Key_Up: return "up"
                        case Qt.Key_Down: return "down"
                        case Qt.Key_Escape: return "escape"
                        case Qt.Key_Tab: return "Tab"
                        case Qt.Key_Backtab: return "Tab"
                        case Qt.Key_Return: return "Return"
                        case Qt.Key_Enter: return "Return"
                        case Qt.Key_Space: return "space"
                        case Qt.Key_Backspace: return "BackSpace"
                        case Qt.Key_Delete: return "Delete"
                        case Qt.Key_Insert: return "Insert"
                        case Qt.Key_Home: return "Home"
                        case Qt.Key_End: return "End"
                        case Qt.Key_PageUp: return "Prior"
                        case Qt.Key_PageDown: return "Next"
                        case Qt.Key_Print: return "Print"
                        case Qt.Key_Pause: return "Pause"
                        case Qt.Key_Comma: return "comma"
                        case Qt.Key_Period: return "period"
                        case Qt.Key_Slash: return "slash"
                        case Qt.Key_Semicolon: return "semicolon"
                        case Qt.Key_Apostrophe: return "apostrophe"
                        case Qt.Key_Minus: return "minus"
                        case Qt.Key_Equal: return "equal"
                        case Qt.Key_BracketLeft: return "bracketleft"
                        case Qt.Key_BracketRight: return "bracketright"
                        case Qt.Key_Backslash: return "backslash"
                        case Qt.Key_QuoteLeft: return "grave"
                        case Qt.Key_MediaNext: return "XF86AudioNext"
                        case Qt.Key_MediaPrevious: return "XF86AudioPrev"
                        case Qt.Key_MediaPlay: return "XF86AudioPlay"
                        case Qt.Key_MediaTogglePlayPause: return "XF86AudioPlay"
                        case Qt.Key_MediaPause: return "XF86AudioPause"
                        case Qt.Key_MediaStop: return "XF86AudioStop"
                    }
                    return ""
    }

    // A key with no modifier is only allowed if it can't break normal typing.
    function _bareKeyOk(key) {
        return /^(F[0-9]+|XF86[A-Za-z0-9]+|Print|Pause|Insert|Menu)$/.test(key)
    }

    // ---------------- editing ----------------
    // Returns "" on success, otherwise a message to show the user.
    function setCombo(id, combo) {
        var d = def(id)
        if (!d) return "Unknown action."
            combo = String(combo).trim()
            if (combo !== "") {
                var p = parse(combo)
                if (d.kind === "mod") {
                    if (p.mods.length === 0) return "Pick at least one modifier."
                        combo = p.mods.join(" + ")
                } else {
                    if (p.key === "") return "Press a key first."
                        if (p.mods.length === 0 && !_bareKeyOk(p.key)) return "Add a modifier (Super, Ctrl, Alt or Shift)."
                            combo = compose(p.mods, p.key)
                }
                var users = usersOf(id, combo)
                if (users.length > 0) return "Already used by: " + users.join(", ") + "."
            }
            var o = Object.assign({}, overrides)
            if (combo !== "" && combo === d.def) delete o[id]
                else o[id] = combo
                    overrides = o
                    _changed()
                    return ""
    }
    function reset(id) {
        if (overrides[id] === undefined) return
            var o = Object.assign({}, overrides)
            delete o[id]
            overrides = o
            _changed()
    }
    function resetAll() {
        overrides = ({})
        _changed()
    }

    // ---------------- persistence ----------------
    function _changed() {
        saveJson()
        applyTimer.restart()
    }

    function _apply(raw) {
        var d
        try { d = JSON.parse(raw) } catch (e) { _ready = true; return }
        if (!d || typeof d !== "object" || typeof d.overrides !== "object" || d.overrides === null) { _ready = true; return }
        var o = {}
        for (var i = 0; i < defs.length; i++) {
            var id = defs[i].id
            if (typeof d.overrides[id] === "string") o[id] = d.overrides[id]
        }
        if (JSON.stringify(o) !== JSON.stringify(overrides)) overrides = o
            _ready = true
    }

    function saveJson() {
        if (!_ready) return
            jsonFile.setText(JSON.stringify({ overrides: overrides }, null, 2))
    }

    function _esc(s) { return String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') }
    function luaText() {
        var lines = [
            "-- Generated by Quickshell (Settings -> Keybindings). Do not edit by hand.",
            "-- Only changed keys are listed; \"\" means unbound. Everything else uses hyprland.lua's defaults.",
            "return {"
        ]
        for (var i = 0; i < defs.length; i++) {
            var id = defs[i].id
            if (overrides[id] !== undefined) lines.push('    ["' + id + '"] = "' + _esc(overrides[id]) + '",')
        }
        lines.push("}")
        return lines.join("\n") + "\n"
    }

    // Write the Lua table, then reload Hyprland once it is on disk
    // (reloading right after setText() would race the async write).
    function apply() {
        if (!_ready) return
            luaFile.setText(luaText())
    }

    Timer { id: applyTimer; interval: 700; onTriggered: root.apply() }

    FileView {
        id: jsonFile
        path: root.jsonPath
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._apply(text())
        onLoadFailed: (error) => { root._ready = true }
    }

    FileView {
        id: luaFile
        path: root.luaPath
        onSaved: Quickshell.execDetached(["hyprctl", "reload"])
    }

    Component.onCompleted: {
        try { _apply(jsonFile.text()) } catch (e) { _ready = true }
    }

    IpcHandler {
        target: "keybinds"

        function status(): string { return JSON.stringify(root.overrides) }
        function set(id: string, combo: string): string {
            var msg = root.setCombo(id, combo)
            return msg === "" ? "ok" : msg
        }
        function reset(id: string): string {
            if (id === "all") root.resetAll()
                else root.reset(id)
                    return "ok"
        }
        function apply(): void { root.apply() }
    }
}
