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

    // One-shot: brightnessctl -m gives "class,device,current,percent,max"
    property Process refreshProc: Process {
        command: ["bash", "-c", "brightnessctl -m | awk -F, '{print $2\",\"$4}'"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line.trim().length) return
                    const parts = line.split(",")
                    if (parts.length >= 2) {
                        root.device = parts[0]
                        root.brightness = parseInt(parts[1]) // parseInt stops at "%"
                    }
            }
        }
    }

    Component.onCompleted: root._refresh()

    property Process _watch: Process {
        command: ["bash", "-c",
        "dev=$(brightnessctl -m | cut -d, -f2); " +
        "inotifywait -q -m -e modify \"/sys/class/backlight/$dev/brightness\""]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root._refresh()
        }
        onExited: watchRestart.start()
    }
    property Timer watchRestart: Timer {
        interval: 1000
        onTriggered: root._watch.running = true
    }
}
