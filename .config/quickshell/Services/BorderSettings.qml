pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Theme"

/**
 * BorderSettings.qml -- Settings > Theme > Border: the border of every panel (bar, popups, OSD, notifications).
 * Main shell only. One setting for ALL themes, so it does not change when you switch theme.
 *
 * Stored in ~/.config/quickshell/state/border-settings.json (watched, hand-edits apply live):
 *   enabled      false = no borders anywhere
 *   thickness    px (1-8)
 *   radiusMode   "panel" = every panel keeps its own corner radius | "custom" = all panels use customRadius
 *   customRadius px (0-40)
 *   colorType    "theme" (the theme's own muted border) | "solid" | "gradient"
 *   color        { mode: "dyn", i } | { mode: "fix", hex }   (same format as the theme colours)
 *   stops        2-6 colours of the gradient
 *   rotate       a streak / the whole gradient travels around the border
 *   rotateDir    "cw" | "ccw"
 *   rotateMode   "streak" (a comet of `streakPct` % of the border) | "whole" (the gradient itself turns)
 *   streakPct    5-60
 *   pulse        the border fades in and out
 *   speed        1-10 (shared by rotate and pulse)
 *   anime        "Anime streaks": NFS Unbound style, stepped (5-15 fps) speed streaks, jitter and glitch artefacts
 *   animeFps     5-15 frames per second of that effect
 *   animeStreaks 1-8 speed streaks
 *   animeGlitch  0-10 amount of artefacts (specks, ghost copy of the outline)
 *
 * Drawn by Widgets/PanelBorder.qml, which GlassPanel puts on every panel.
 */
Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.config/quickshell/state/border-settings.json"

    property bool enabled: true
    property int thickness: 1
    property string radiusMode: "panel"
    property int customRadius: 12
    property string colorType: "theme"
    property var color: ({ mode: "dyn", i: 8 })
    property var stops: [{ mode: "dyn", i: 3 }, { mode: "dyn", i: 7 }]
    property bool rotate: false
    property string rotateDir: "cw"
    property string rotateMode: "streak"
    property int streakPct: 25
    property bool pulse: false
    property int speed: 5
    property bool anime: false
    property int animeFps: 10
    property int animeStreaks: 4
    property int animeGlitch: 4

    // ---- what the painter needs ----
    readonly property bool animated: root.enabled && (root.rotate || root.pulse || root.anime)
    function radiusFor(panelRadius) { return root.radiusMode === "custom" ? root.customRadius : panelRadius }
    readonly property color baseColor: root.colorType === "theme" ? Theme.borderMuted
    : Theme.colorOf(root.color, Theme.effectiveDark, true)
    readonly property var gradientColors: {
        const out = []
        const l = root.stops
        for (let i = 0; i < l.length && i < 6; i++) out.push(Theme.colorOf(l[i], Theme.effectiveDark, true))
            return out.length >= 2 ? out : [root.baseColor, root.baseColor]
    }
    // one turn of a rotation, in ms
    readonly property int turnMs: Math.round(9000 / root.speed)
    // one fade out + in of the pulse, in ms
    readonly property int pulseMs: Math.round(3600 / root.speed)

    // ---- persistence ----
    property string _lastWritten: ""
    property bool _ready: false

    function _clampInt(v, lo, hi, def) { return (typeof v === "number") ? Math.max(lo, Math.min(hi, Math.round(v))) : def }
    function _apply(raw) {
        if (raw === root._lastWritten || saveTimer.running) return
            let d
            try { d = JSON.parse(raw) } catch (e) { root._ready = true; return }
            if (!d || typeof d !== "object") { root._ready = true; return }
            if (typeof d.enabled === "boolean") root.enabled = d.enabled
                root.thickness = root._clampInt(d.thickness, 1, 8, 1)
                root.radiusMode = d.radiusMode === "custom" ? "custom" : "panel"
                root.customRadius = root._clampInt(d.customRadius, 0, 40, 12)
                root.colorType = (d.colorType === "solid" || d.colorType === "gradient") ? d.colorType : "theme"
                if (d.color && typeof d.color === "object") root.color = d.color
                    if (Array.isArray(d.stops) && d.stops.length >= 2) root.stops = d.stops.slice(0, 6)
                        if (typeof d.rotate === "boolean") root.rotate = d.rotate
                            root.rotateDir = d.rotateDir === "ccw" ? "ccw" : "cw"
                            root.rotateMode = d.rotateMode === "whole" ? "whole" : "streak"
                            root.streakPct = root._clampInt(d.streakPct, 5, 60, 25)
                            if (typeof d.pulse === "boolean") root.pulse = d.pulse
                                root.speed = root._clampInt(d.speed, 1, 10, 5)
                                if (typeof d.anime === "boolean") root.anime = d.anime
                                    root.animeFps = root._clampInt(d.animeFps, 5, 15, 10)
                                    root.animeStreaks = root._clampInt(d.animeStreaks, 1, 8, 4)
                                    root.animeGlitch = root._clampInt(d.animeGlitch, 0, 10, 4)
                                    root._ready = true
    }
    function _save() {
        const txt = JSON.stringify({
            enabled: root.enabled, thickness: root.thickness, radiusMode: root.radiusMode,
            customRadius: root.customRadius, colorType: root.colorType, color: root.color, stops: root.stops,
            rotate: root.rotate, rotateDir: root.rotateDir, rotateMode: root.rotateMode,
            streakPct: root.streakPct, pulse: root.pulse, speed: root.speed,
            anime: root.anime, animeFps: root.animeFps, animeStreaks: root.animeStreaks, animeGlitch: root.animeGlitch
        }, null, 2)
        root._lastWritten = txt
        file.setText(txt)
    }
    // every setter changes the value at once and writes the file once things settle
    function set(key, value) {
        if (root[key] === value) return
            root[key] = value
            saveTimer.restart()
    }
    function reset() {
        root.enabled = true; root.thickness = 1; root.radiusMode = "panel"; root.customRadius = 12
        root.colorType = "theme"; root.color = { mode: "dyn", i: 8 }
        root.stops = [{ mode: "dyn", i: 3 }, { mode: "dyn", i: 7 }]
        root.rotate = false; root.rotateDir = "cw"; root.rotateMode = "streak"; root.streakPct = 25
        root.pulse = false; root.speed = 5
        root.anime = false; root.animeFps = 10; root.animeStreaks = 4; root.animeGlitch = 4
        saveTimer.restart()
    }

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
        try { root._apply(file.text()) } catch (e) { root._ready = true }
    }
}
