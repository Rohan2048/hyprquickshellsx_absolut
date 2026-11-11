pragma Singleton
import QtQuick
import Quickshell

Singleton {
    id: root

    property int durationMs: 5 * 60 * 1000
    property real remainingMs: 5 * 60 * 1000
    property real accumulatedRemaining: 5 * 60 * 1000
    property bool running: false
    property var startTime: null
    property bool timesUp: false

    property bool untilMode: false
    property real endAt: 0
    property string untilText: ""
    property real _manualDuration: 5 * 60 * 1000
    property bool _restore: false

    property string timeText: "00:05:00"
    property string shortText: "05:00"

    readonly property bool active: running || timesUp || remainingMs !== durationMs

    Component.onCompleted: _show(durationMs)

    function _show(ms) {
        timeText = fmt(ms)
        shortText = fmtShort(ms)
    }

    function start() { if (!running && remainingMs > 0) { startTime = Date.now(); running = true } }
    function pause() { if (running) { accumulatedRemaining = remainingMs; running = false; untilMode = false } }

    // Count down to the next time the clock reads h:m (today if still ahead, otherwise tomorrow).
    // The duration is counted from the start of the current minute, so 20:05:37 -> 20:10 is exactly 05:00
    // (it ends at 20:10:37). To end at exactly 20:10:00 instead, use `const base = now`.
    function startUntil(h, m) {
        const now = new Date()
        const t = new Date(now)
        t.setHours(h, m, 0, 0)
        if (t.getTime() <= now.getTime()) t.setDate(t.getDate() + 1)

            const base = new Date(now)
            base.setSeconds(0, 0)
            const ms = t.getTime() - base.getTime()

            if (!_restore) _manualDuration = durationMs
                _restore = true
                running = false
                timesUp = false
                durationMs = ms
                accumulatedRemaining = ms
                remainingMs = ms
                _show(ms)
                endAt = now.getTime() + ms
                untilText = (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
                untilMode = true
                startTime = Date.now()
                running = true
    }

    function reset() {
        if (_restore) { durationMs = _manualDuration; _restore = false }
        untilMode = false
        running = false
        accumulatedRemaining = durationMs
        remainingMs = durationMs
        _show(durationMs)
        timesUp = false
    }

    function adjust(deltaMs) {
        if (running) return
            _restore = false
            untilMode = false
            durationMs = Math.max(0, durationMs + deltaMs)
            _manualDuration = durationMs
            accumulatedRemaining = durationMs
            remainingMs = durationMs
            _show(durationMs)
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
        running: root.running
        repeat: true
        onTriggered: {
            let elapsed = Date.now() - root.startTime
            root.remainingMs = root.untilMode ? Math.max(0, root.endAt - Date.now())
            : Math.max(0, root.accumulatedRemaining - elapsed)
            root._show(root.remainingMs)

            if (root.remainingMs <= 0) {
                root.running = false
                root.timesUp = true
            }
        }
    }

    // seconds are rounded UP so a fresh 5:00 shows 05:00, not 04:59
    function fmt(ms) {
        let t = Math.max(0, Math.ceil(ms / 1000) * 1000)
        let h = (t / 3600000) | 0, m = ((t % 3600000) / 60000) | 0, s = ((t % 60000) / 1000) | 0
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return pad(h) + ":" + pad(m) + ":" + pad(s)
    }

    function fmtShort(ms) {
        let t = Math.max(0, Math.ceil(ms / 1000) * 1000)
        let h = (t / 3600000) | 0, m = ((t % 3600000) / 60000) | 0, s = ((t % 60000) / 1000) | 0
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return h > 0 ? (pad(h) + ":" + pad(m) + ":" + pad(s)) : (pad(m) + ":" + pad(s))
    }
}
