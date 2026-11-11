pragma Singleton
import QtQuick
import Quickshell

// Stopwatch state, hoisted out of Clock/StopwatchPage.qml (see TimerService).
Singleton {
    id: root

    property bool running: false
    property real accumulated: 0
    property var startTime: null
    property real liveMs: 0

    property string timeText: "00:00:00.00"   // page: centiseconds
    property string shortText: "00:00"        // bar: changes once per second

    property alias lapModel: _lapModel
    ListModel { id: _lapModel }

    // Shown in the bar while running, and while paused with time on the clock.
    // Reset hides it again.
    readonly property bool active: running || accumulated > 0

    function _refresh() {
        timeText = fmt(liveMs)
        shortText = fmtShort(liveMs)
    }

    function start() { if (!running) { startTime = Date.now(); running = true } }
    function pause() {
        if (running) {
            accumulated += Date.now() - startTime
            liveMs = accumulated
            running = false
            _refresh()
        }
    }
    function reset() {
        running = false; accumulated = 0; startTime = null; liveMs = 0
        _refresh()
        _lapModel.clear()
    }
    function lap() {
        if (running) _lapModel.insert(0, { "time": liveMs })
    }

    Timer {
        interval: 30
        running: root.running
        repeat: true
        onTriggered: {
            root.liveMs = root.accumulated + (Date.now() - root.startTime)
            root._refresh()
        }
    }

    function fmt(ms) {
        let t = ms | 0
        let h = (t / 3600000) | 0, m = ((t % 3600000) / 60000) | 0
        let s = ((t % 60000) / 1000) | 0, cs = ((t % 1000) / 10) | 0
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return pad(h) + ":" + pad(m) + ":" + pad(s) + "." + pad(cs)
    }

    function fmtShort(ms) {
        let t = Math.max(0, ms | 0)
        let h = (t / 3600000) | 0, m = ((t % 3600000) / 60000) | 0, s = ((t % 60000) / 1000) | 0
        function pad(n) { return n < 10 ? "0" + n : "" + n }
        return h > 0 ? (pad(h) + ":" + pad(m) + ":" + pad(s)) : (pad(m) + ":" + pad(s))
    }
}
