pragma Singleton
import QtQuick
import Quickshell

// Timer state, hoisted out of Clock/TimerPage.qml so the bar can tell when a
// timer is active. TimerPage (in DateTimePopup) and the bar's own timer popup
// are both just views over this singleton, so they always agree.
Singleton {
    id: root

    property int durationMs: 5 * 60 * 1000
    property real remainingMs: 5 * 60 * 1000
    property real accumulatedRemaining: 5 * 60 * 1000
    property bool running: false
    property var startTime: null
    property bool timesUp: false

    // "Until a clock time" timers (Start > Until in the timer page): the countdown runs to a fixed wall-clock
    // moment, so it stays right across suspend. Everything that shows the timer (the page, the bar chip, both popups)
    // just reads remainingMs like any other timer; these only add the caption and the exact end.
    property bool untilMode: false
    property real endAt: 0              // epoch ms the timer ends at (untilMode)
    property string untilText: ""       // "20:00"
    property real _manualDuration: 5 * 60 * 1000   // the duration to come back to when an until timer is reset
    property bool _restore: false

    // "00:05:00" for the page, "05:00" (or "hh:mm:ss" past an hour) for the bar.
    // Assigned from the tick instead of bound, so QML only emits a change
    // signal when the visible text actually changes.
    property string timeText: "00:05:00"
    property string shortText: "05:00"

    // Shown in the bar from the moment the timer is started until it is reset.
    // Paused still counts (same idea as the music button showing while Paused),
    // and so does "Time's Up" so the alarm can be dismissed from the bar.
    readonly property bool active: running || timesUp || remainingMs !== durationMs

    Component.onCompleted: _show(durationMs)

    function _show(ms) {
        timeText = fmt(ms)
        shortText = fmtShort(ms)
    }

    function start() { if (!running && remainingMs > 0) { startTime = Date.now(); running = true } }
    function pause() { if (running) { accumulatedRemaining = remainingMs; running = false; untilMode = false } }

    // Count down to the next time the clock reads h:m (today if it is still ahead, otherwise tomorrow).
    function startUntil(h, m) {
        const now = new Date()
        const t = new Date(now)
        t.setHours(h, m, 0, 0)
        if (t.getTime() <= now.getTime()) t.setDate(t.getDate() + 1)
            const ms = t.getTime() - now.getTime()
            if (!_restore) _manualDuration = durationMs
                _restore = true
                running = false
                timesUp = false
                durationMs = ms
                accumulatedRemaining = ms
                remainingMs = ms
                _show(ms)
                endAt = t.getTime()
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

    function fmt(ms) {
        let t = Math.max(0, ms | 0)
        let h = (t / 3600000) | 0, m = ((t % 3600000) / 60000) | 0, s = ((t % 60000) / 1000) | 0
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return pad(h) + ":" + pad(m) + ":" + pad(s)
    }

    function fmtShort(ms) {
        let t = Math.max(0, ms | 0)
        let h = (t / 3600000) | 0, m = ((t % 3600000) / 60000) | 0, s = ((t % 60000) / 1000) | 0
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return h > 0 ? (pad(h) + ":" + pad(m) + ":" + pad(s)) : (pad(m) + ":" + pad(s))
    }
}
