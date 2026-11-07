pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Theme"

/**
 * SBSState.qml — Super Battery Saver mode.
 *
 * `active` is persisted to a state file and survives a Quickshell/Hyprland
 * restart. It is only ever cleared by calling disable() (the Exit button in
 * SBSShell.qml) — there's no auto-revert on session start.
 *
 * hyprland.lua reads this same state file directly and wraps the handful
 * of keybinds that open the heavy rofi/eww-era tools (app menu, clipboard
 * picker, wallpaper switcher, commands/shortcuts popups, autoplay toggle)
 * in `if not sbsMode then ... end`, so enable()/disable() just need to
 * persist the new state; `hyprctl reload` is fired from FileView.onSaved
 * (after the write completes) so Hyprland re-evaluates the config with the
 * new value, never the stale one. No script rewrites
 * hyprland.lua on disk anymore.
 *
 * enable()/disable() also force the system theme (GTK/KDE/Konsole/Kate,
 * via apply-theme.sh) independently of Theme.isDark: SBS's own shell is
 * fixed black/white regardless of theme, but whatever's still running
 * underneath (a terminal, a file manager) should match while SBS is on.
 * This is a one-shot detached call on toggle, not a persistent process.
 *
 * `uiHidden` drives SBSShell's hide/reveal (CTRL+H via `qs ipc call sbs
 * toggleHide`, bound in hyprland.lua). It's shared across every screen's
 * PanelWindow instance since it lives here rather than as a local property
 * on each one, and it's NOT persisted — always starts false, unlike
 * `active`.
 *
 * Stopwatch/timer state below is hoisted here (rather than living inside
 * SBSStopwatch.qml / SBSTimer.qml) so there's exactly one stopwatch and
 * one timer, shared between whichever SettingsPanel view is mounted and
 * the status pills in SBSShell.qml -- both just bind to these properties
 * and call these functions, neither owns the state. stopwatchActive /
 * timerActive drive pill visibility; both go false again on reset, which
 * is what makes "reset" cause the corresponding pill to disappear. These
 * pills are an exception to uiHidden -- SBSShell.qml doesn't gate them on
 * !uiHidden the way it does everything else.
 */
Singleton {
    id: root

    readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell"
    readonly property string stateFile: configDir + "/state/sbs-mode.json"

    property bool active: false
    property bool _loaded: false

    property bool uiHidden: false
    function toggleHide() {
        uiHidden = !uiHidden
    }

    IpcHandler {
        target: "sbs"
        function toggleHide(): void {
            root.toggleHide()
        }
    }

    FileView {
        id: fileView
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        // hyprland.lua reads this file at config-parse time, so the reload
        // must only happen once the new state is on disk. Firing it right
        // after setText() raced the async write on slow machines and the
        // config was evaluated with the previous state (inverted binds).
        onSaved: Quickshell.execDetached(["hyprctl", "reload"])
        onLoaded: {
            try {
                const data = JSON.parse(text())
                root.active = !!data.active
            } catch (e) {
                root.active = false
            }
            root._loaded = true
        }
        onLoadFailed: (error) => {
            root.active = false
            root._loaded = true
        }
    }

    function _persist() {
        fileView.setText(JSON.stringify({ active: root.active }, null, 2))
    }

    function _applySystemTheme(mode) {
        Quickshell.execDetached(["bash", "-c",
                                "mkdir -p ~/.cache/quickshell && printf '%s' '" + mode + "' > ~/.cache/quickshell/theme_mode && " +
                                "~/.config/hypr/apply-theme.sh " + mode])
    }

    function enable() {
        if (root.active) return
            root.active = true
            _persist()
            _applySystemTheme("dark")
    }

    function disable() {
        if (!root.active) return
            root.active = false
            _persist()
            _applySystemTheme(Theme.isDark ? "dark" : "light")
    }

    function toggle() {
        if (active) disable()
            else enable()
    }

    // ---------------------------------------------------------------
    // Stopwatch
    // ---------------------------------------------------------------

    readonly property bool stopwatchActive: swRunning || swAccumulated > 0

    property bool swRunning: false
    property real swAccumulated: 0
    property var swStartTime: null
    property real swLiveMs: 0
    property string swTimeText: "00:00:00.00"
    property alias swLapModel: _swLapModel

    ListModel { id: _swLapModel }

    function swStart() { if (!swRunning) { swStartTime = Date.now(); swRunning = true } }
    function swPause() { if (swRunning) { swAccumulated += Date.now() - swStartTime; swLiveMs = swAccumulated; swRunning = false } }
    function swReset() {
        swRunning = false; swAccumulated = 0; swStartTime = null; swLiveMs = 0
        swTimeText = "00:00:00.00"
        _swLapModel.clear()
    }
    function swLap() {
        if (swRunning) _swLapModel.insert(0, { "time": swLiveMs })
    }

    Timer {
        interval: 30
        running: root.swRunning
        repeat: true
        onTriggered: {
            root.swLiveMs = root.swAccumulated + (Date.now() - root.swStartTime)
            root.swTimeText = root.swFmt(root.swLiveMs)
        }
    }

    function swFmt(ms) {
        let t = ms | 0
        let h = (t / 3600000) | 0, m = ((t % 3600000) / 60000) | 0
        let s = ((t % 60000) / 1000) | 0, cs = ((t % 1000) / 10) | 0
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return pad(h) + ":" + pad(m) + ":" + pad(s) + "." + pad(cs)
    }

    // ---------------------------------------------------------------
    // Timer
    // ---------------------------------------------------------------

    readonly property bool timerActive: tRunning || timesUp || remainingMs !== durationMs

    property int durationMs: 5 * 60 * 1000
    property real remainingMs: durationMs
    property real accumulatedRemaining: durationMs
    property bool tRunning: false
    property var tStartTime: null
    property bool timesUp: false
    property string tTimeText: "00:00:00"

    Component.onCompleted: tTimeText = root.tFmt(durationMs)

    function tStart() { if (!tRunning && remainingMs > 0) { tStartTime = Date.now(); tRunning = true } }
    function tPause() { if (tRunning) { accumulatedRemaining = remainingMs; tRunning = false } }
    function tReset() {
        tRunning = false; accumulatedRemaining = durationMs; remainingMs = durationMs
        tTimeText = root.tFmt(durationMs)
        timesUp = false
    }
    function tAdjust(deltaMs) {
        if (tRunning) return
            durationMs = Math.max(0, durationMs + deltaMs)
            accumulatedRemaining = durationMs
            remainingMs = durationMs
            tTimeText = root.tFmt(durationMs)
    }

    function playAlarmLoop() {
        Quickshell.execDetached(["bash", "-c",
                                "while true; do gst-launch-1.0 -q playbin uri=file://" + Quickshell.env("HOME") + "/.config/sounds/Timer.mp3; done"])
    }
    function stopAlarmLoop() {
        Quickshell.execDetached(["bash", "-c",
                                "pkill -f 'playbin uri=file://" + Quickshell.env("HOME") + "/.config/sounds/Timer.mp3'"])
    }

    onTimesUpChanged: {
        if (timesUp) {
            Quickshell.execDetached(["notify-send", "-u", "critical", "Timer", "Time's Up!"])
            playAlarmLoop()
        } else {
            stopAlarmLoop()
        }
    }

    Timer {
        interval: 200
        running: root.tRunning
        repeat: true
        onTriggered: {
            let elapsed = Date.now() - root.tStartTime
            root.remainingMs = Math.max(0, root.accumulatedRemaining - elapsed)
            root.tTimeText = root.tFmt(root.remainingMs)
            if (root.remainingMs <= 0) {
                root.tRunning = false
                root.timesUp = true
            }
        }
    }

    function tFmt(ms) {
        let t = Math.max(0, ms | 0)
        let h = (t / 3600000) | 0, m = ((t % 3600000) / 60000) | 0, s = ((t % 60000) / 1000) | 0
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return pad(h) + ":" + pad(m) + ":" + pad(s)
    }

    // Compact "mm:ss" (or "hh:mm:ss" past an hour) for the collapsed
    // pills in SBSShell.qml -- both timer and stopwatch use this.
    function fmtShort(ms) {
        let t = Math.max(0, ms | 0)
        let h = (t / 3600000) | 0, m = ((t % 3600000) / 60000) | 0, s = ((t % 60000) / 1000) | 0
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return h > 0 ? (pad(h) + ":" + pad(m) + ":" + pad(s)) : (pad(m) + ":" + pad(s))
    }
}
