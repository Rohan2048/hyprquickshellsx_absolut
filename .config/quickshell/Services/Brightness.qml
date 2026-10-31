pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Brightness.qml — event-driven via brightnessctl for control, and
// inotifywait watching the sysfs backlight node for live updates (so
// hardware brightness keys / other tools reflect here immediately too).
QtObject {
    id: root

    property int brightness: 100 // percent, 0-100
    property string device: ""

    function _refresh() {
        refreshProc.running = true
    }

    function setBrightness(pct) {
        const clamped = Math.max(0, Math.min(100, Math.round(pct)))
        root.brightness = clamped // optimistic update, inotify confirms shortly after
        Quickshell.execDetached(["brightnessctl", "set", clamped + "%"])
    }

    function _applyLine(line) {
        if (!line.trim().length) return
        const parts = line.split(",")
        if (parts.length >= 2) {
            root.device = parts[0]
            root.brightness = parseInt(parts[1]) // parseInt stops at "%"
        }
    }

    // One-shot: brightnessctl -m gives "class,device,current,percent,max"
    property Process refreshProc: Process {
        command: ["bash", "-c", "brightnessctl -m | awk -F, '{print $2\",\"$4}'"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root._applyLine(line)
        }
    }

    Component.onCompleted: root._refresh()

    // Long-lived watcher. It now prints the new "device,percent" line itself
    // (straight from sysfs) on every change, instead of making Quickshell
    // spawn bash + brightnessctl + awk for each event.
    property Process _watch: Process {
        command: ["bash", "-c",
        "dev=$(brightnessctl -m | cut -d, -f2); " +
        "bl=\"/sys/class/backlight/$dev\"; " +
        "read -r max < \"$bl/max_brightness\" || exit 1; " +
        "emit() { read -r cur < \"$bl/brightness\" && echo \"$dev,$(( (cur * 100 + max / 2) / max ))\"; }; " +
        "inotifywait -q -m -e modify \"$bl/brightness\" | while read -r _; do emit; done"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root._applyLine(line)
        }
        onExited: watchRestart.start()
    }
    property Timer watchRestart: Timer {
        interval: 1000
        onTriggered: root._watch.running = true
    }
}
