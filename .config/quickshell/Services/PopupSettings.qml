pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Theme"

/**
 * PopupSettings.qml -- Settings > Popups: per-popup scale, plus the Commands palette,
 * Shortcuts palette and Applications options. Main shell only.
 *
 * Stored in ~/.config/quickshell/state/popup-settings.json (watched, hand-edits apply live):
 *   scales    { "<popup id>": percent }   missing = 100
 *   commands / shortcuts / apps / clipboard   { ...options, see the pages that own them }
 *
 * A popup is scaled as a whole -- its panel, text, icons and every button inside it --
 * by Widgets/PopupScale.qml, and its window grows with it so the bar placement maths
 * (PopupPlacement) keeps working.
 *
 * Sliders fire continuously while dragging: values apply in memory at once and the
 * file is written once things settle.
 */
Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.config/quickshell/state/popup-settings.json"
    readonly property int minPct: 60
    readonly property int maxPct: 200

    // The popups that can be scaled. `group` is only for the settings page.
    readonly property var popups: [
        { id: "volume",        label: "Volume",             group: "bar" },
        { id: "battery",       label: "Battery",            group: "bar" },
        { id: "notifications", label: "Notifications",      group: "bar" },
        { id: "wifi",          label: "Wi-Fi",              group: "bar" },
        { id: "bluetooth",     label: "Bluetooth",          group: "bar" },
        { id: "datetime",      label: "Date & time",        group: "bar" },
        { id: "music",         label: "Music",              group: "bar" },
        { id: "clock",         label: "Timer & stopwatch",  group: "bar" },
        { id: "commands",      label: "Commands palette",   group: "palette" },
        { id: "shortcuts",     label: "Shortcuts palette",  group: "palette" },
        { id: "powermenu",     label: "Power menu",         group: "power" },
        { id: "schedule",      label: "Power schedule",     group: "power" },
        { id: "hdmi",          label: "Display toggle",     group: "power" },
        { id: "wallpaper",     label: "Wallpaper picker",   group: "pickers" },
        { id: "animscale",     label: "Animation scale",    group: "pickers" },
        { id: "settings",      label: "Settings window",    group: "settings" }
    ]
    // true while a scale slider is held down: the Settings window waits for you to let go before it resizes
    property bool scaleDragging: false

    // the whole file
    property var cfg: ({})
    property string _lastWritten: ""

    // ---- generic access (pages added later use these) ----
    function get(section, key, def) {
        const s = root.cfg[section]
        return (s && typeof s === "object" && s[key] !== undefined) ? s[key] : def
    }
    function put(section, key, value) {
        const all = Object.assign({}, root.cfg)
        const s = Object.assign({}, (all[section] && typeof all[section] === "object") ? all[section] : {})
        if (value === null || value === undefined) delete s[key]
            else s[key] = value
                if (Object.keys(s).length === 0) delete all[section]
                    else all[section] = s
                        root.cfg = all
                        saveTimer.restart()
    }
    function resetSection(section) {
        const all = Object.assign({}, root.cfg)
        delete all[section]
        root.cfg = all
        saveTimer.restart()
    }

    // ---- Commands palette ----
    // placement: "<top|center|bottom>-<left|center|right>" (default: right edge, vertically centred,
    // which is how it always looked). style: "rofi" (the + button opens the rofi menus) |
    // "quickshell" (in-shell dialog that follows the shell theme).
    readonly property var commandsPlacements: [
        "top-left", "top-center", "top-right", "center-left", "center-right",
        "bottom-left", "bottom-center", "bottom-right"
    ]
    readonly property string commandsPlacement: {
        const v = root.get("commands", "placement", "center-right")
        return root.commandsPlacements.indexOf(v) >= 0 ? v : "center-right"
    }
    readonly property string commandsStyle: root.get("commands", "style", "rofi") === "quickshell" ? "quickshell" : "rofi"

    // ---- Shortcuts palette ----
    // placement: same 8 spots as the Commands palette (default: left edge, centred = the original dock).
    // style: how the + button picks an app: "rofi" (scripts/shortcuts-add.sh) | "quickshell" (in-shell
    //        app picker, grid / list). trigger: "keybind" (IPC / SUPER+W only, default) |
    //        "hover" (a thin trigger zone at the dock's edge reveals it, it hides again when the
    //        pointer leaves) | "both".
    readonly property string shortcutsPlacement: {
        const v = root.get("shortcuts", "placement", "center-left")
        return root.commandsPlacements.indexOf(v) >= 0 ? v : "center-left"
    }
    readonly property string shortcutsStyle: root.get("shortcuts", "style", "rofi") === "quickshell" ? "quickshell" : "rofi"
    readonly property string shortcutsTrigger: {
        const v = root.get("shortcuts", "trigger", "keybind")
        return (v === "hover" || v === "both") ? v : "keybind"
    }

    // ---- Applications ----
    // style: "rofi" (SUPER+R runs `rofi -show drun`, as before) | "quickshell" (in-shell launcher,
    // see Popups/AppLauncherPopup.qml). view: "grid" (default, like the rofi theme) | "list"
    // (one row per app with its description). The launcher keybind goes through
    // scripts/launcher.sh, which reads the style from this file.
    readonly property string appsStyle: root.get("apps", "style", "rofi") === "quickshell" ? "quickshell" : "rofi"
    readonly property string appsView: root.get("apps", "view", "grid") === "list" ? "list" : "grid"
    // open / closed state of the Quickshell launcher (not saved)
    property bool appsOpen: false

    // ---- Clipboard history ----
    // style: "rofi" (SUPER+P runs the rofi list over `cliphist`, as before) | "quickshell" (in-shell list,
    // see Popups/ClipboardPopup.qml). The keybind goes through scripts/clipboard.sh, which reads the style
    // from this file and falls back to rofi if the shell does not answer. Stored as clipboard.style.
    readonly property string clipboardStyle: root.get("clipboard", "style", "rofi") === "quickshell" ? "quickshell" : "rofi"
    // open / closed state of the Quickshell clipboard history (not saved)
    property bool clipboardOpen: false

    // ---- Power menu / Power schedule / Display toggle ----
    // Each of the three keybind menus (SUPER+Esc, SUPER+SHIFT+Esc, ALT+S) can be drawn by rofi
    // (default) or by the shell (Popups/ChoicePopup.qml). The keybind scripts ask
    // scripts/qs-pick.sh, which reads the style from here and opens the shell version over IPC;
    // if the shell is not running (crashed, killed) the IPC call fails and the script just runs
    // its normal rofi menu. Nothing watches the shell: the decision is made when the key is pressed.
    // Stored as power.<id>Style = "quickshell" (missing = rofi).
    readonly property var powerIds: ["powermenu", "schedule", "hdmi"]
    // Wallpaper picker (SUPER+SHIFT+W) and Animation scale (ALT+R) work the same way: style stored as
    // power.<id>Style, same rofi fallback when the shell does not answer.
    readonly property var pickerIds: ["wallpaper", "animscale"]
    // folder the Quickshell wallpaper picker lists ("" = ~/Downloads/WALLPAPERS, what the rofi script uses)
    readonly property string wallpaperDir: {
        const d = root.get("wallpaper", "dir", "")
        return (typeof d === "string" && d.trim() !== "") ? d.trim() : (Quickshell.env("HOME") + "/Downloads/WALLPAPERS")
    }
    signal wallpaperRequested()      // "Try Quickshell version" in Settings
    function setWallpaperDir(d) { root.put("wallpaper", "dir", (d && d.trim() !== "") ? d.trim() : null) }
    function powerStyle(id) { return root.get("power", id + "Style", "rofi") === "quickshell" ? "quickshell" : "rofi" }
    function setPowerStyle(id, style) { root.put("power", id + "Style", style === "quickshell" ? "quickshell" : null) }
    // id of the menu being previewed from Settings ("" = none); ChoicePopup watches it (not saved)
    property string choicePreview: ""

    // ---- corner radius ----
    // Every popup listed in Settings > Popups has a corner radius (px). Missing = its normal look
    // (12, the Music popup 20). Stored in "radii" { "<popup id>": px }.
    readonly property int maxRadius: 40
    readonly property var radiusItems: [
        { id: "volume", label: "Volume" }, { id: "battery", label: "Battery" },
        { id: "notifications", label: "Notifications" }, { id: "wifi", label: "Wi-Fi" },
        { id: "bluetooth", label: "Bluetooth" }, { id: "datetime", label: "Date & time" },
        { id: "music", label: "Music" }, { id: "clock", label: "Timer & stopwatch" },
        { id: "commands", label: "Commands palette" }, { id: "shortcuts", label: "Shortcuts palette" },
        { id: "apps", label: "Application launcher" }, { id: "clipboard", label: "Clipboard history" },
        { id: "powermenu", label: "Power menu" }, { id: "schedule", label: "Power schedule" },
        { id: "hdmi", label: "Display toggle" },
        { id: "wallpaper", label: "Wallpaper picker" }, { id: "animscale", label: "Animation scale" },
        { id: "settings", label: "Settings window" }
    ]
    function defaultRadius(id) { return id === "music" ? 20 : Theme.radiusMd }
    function radiusOf(id) {
        const v = root.get("radii", id, undefined)
        return (typeof v === "number") ? Math.max(0, Math.min(root.maxRadius, Math.round(v))) : root.defaultRadius(id)
    }
    function setRadius(id, px) {
        const p = Math.max(0, Math.min(root.maxRadius, Math.round(px)))
        root.put("radii", id, p === root.defaultRadius(id) ? null : p)
    }
    function resetRadii() { root.resetSection("radii") }

    // ---- button style ----
    // Every button inside a popup takes its look from that popup (Settings > Popups > Popup styles):
    //   corner radius (px), width and height (% of the normal size), text offset (px, right / down positive).
    // Stored in "buttons" { "<popup id>": { r, w, h, dx, dy } }; "all" is the fallback for every popup, and
    // a button that sets its own `defaultRadius` (the pill shaped ones) keeps that until a radius is set.
    readonly property int defaultButtonRadius: Theme.radiusSm
    readonly property var buttonLimits: ({ r: [0, 40], w: [50, 250], h: [50, 250], dx: [-30, 30], dy: [-30, 30] })
    readonly property var buttonDefaults: ({ w: 100, h: 100, dx: 0, dy: 0 })
    // the popup id of the nearest ancestor that has one (PopupScale sets it; the Settings window too)
    function ctxOf(item) {
        let p = item ? item.parent : null
        while (p) {
            if (p.popupId !== undefined && p.popupId !== "") return p.popupId
                p = p.parent
        }
        return ""
    }
    function _num(o, k) { return (o && typeof o === "object" && typeof o[k] === "number") ? o[k] : undefined }
    function buttonVal(id, key, def) {
        const lim = root.buttonLimits[key]
        let v = (id !== "") ? root._num(root.get("buttons", id, undefined), key) : undefined
        if (v === undefined) v = root._num(root.get("buttons", "all", undefined), key)
            if (v === undefined) return def
                return Math.max(lim[0], Math.min(lim[1], Math.round(v)))
    }
    // is this popup's own value set? (the page shows "Reset" only then)
    function buttonValSet(id, key) { return root._num(root.get("buttons", id, undefined), key) !== undefined }
    function setButtonVal(id, key, v) {
        const cur = Object.assign({}, root.get("buttons", id, {}) || {})
        cur[key] = Math.round(v)
        root.put("buttons", id, cur)
    }
    function clearButtonVal(id, key) {
        const cur = Object.assign({}, root.get("buttons", id, {}) || {})
        delete cur[key]
        root.put("buttons", id, Object.keys(cur).length ? cur : null)
    }
    function clearButtonStyle(id) { root.put("buttons", id, null) }
    function resetButtonStyles() { root.resetSection("buttons") }
    function buttonRadiusOf(id, def) {
        const v = root.buttonVal(id, "r", undefined)
        return v !== undefined ? v : (def !== undefined ? def : root.defaultButtonRadius)
    }
    function buttonRadiusFor(item, def) { return root.buttonRadiusOf(root.ctxOf(item), def) }
    // everything a button needs, in one object: { r, w, h (factors), dx, dy (px) }
    function styleFor(item, defR) {
        const id = root.ctxOf(item)
        return {
            r: root.buttonRadiusOf(id, defR),
            w: root.buttonVal(id, "w", 100) / 100,
            h: root.buttonVal(id, "h", 100) / 100,
            dx: root.buttonVal(id, "dx", 0),
            dy: root.buttonVal(id, "dy", 0)
        }
    }

    // ---- scale ----
    function scalePct(id) {
        const v = root.get("scales", id, 100)
        return (typeof v === "number") ? Math.max(root.minPct, Math.min(root.maxPct, Math.round(v))) : 100
    }
    function scaleOf(id) { return root.scalePct(id) / 100 }
    function setScalePct(id, pct) {
        const p = Math.max(root.minPct, Math.min(root.maxPct, Math.round(pct)))
        root.put("scales", id, p === 100 ? null : p)
    }
    function resetScales() { root.resetSection("scales") }

    // ---- persistence ----
    function _apply(raw) {
        if (raw === root._lastWritten || saveTimer.running) return   // our own write / unsaved edits win
            let d
            try { d = JSON.parse(raw) } catch (e) { return }
            if (d && typeof d === "object" && !Array.isArray(d)) root.cfg = d
    }
    function _save() {
        const txt = JSON.stringify(root.cfg, null, 2)
        root._lastWritten = txt
        file.setText(txt)
    }

    Timer { id: saveTimer; interval: 300; onTriggered: root._save() }

    FileView {
        id: file
        path: root.stateFile
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._apply(text())
    }

    Component.onCompleted: {
        try { root._apply(file.text()) } catch (e) {}
    }
}
