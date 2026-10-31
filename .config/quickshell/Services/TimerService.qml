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
    function pause() { if (running) { accumulatedRemaining = remainingMs; running = false } }
    function reset() {
        running = false
        accumulatedRemaining = durationMs
        remainingMs = durationMs
        _show(durationMs)
        timesUp = false
    }

    function adjust(deltaMs) {
        if (running) return
        durationMs = Math.max(0, durationMs + deltaMs)
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
            root.remainingMs = Math.max(0, root.accumulatedRemaining - elapsed)
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
