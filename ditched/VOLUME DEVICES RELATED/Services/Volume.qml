pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Volume.qml — event-driven volume state, ported straight from your
// volume-listener.sh (unchanged, see scripts/volume-listener.sh). Same
// trick as eww's `deflisten`: keep the bash script that watches
// `pactl subscribe`, just read its stdout line-by-line from a long-lived
// Process instead of eww's deflisten machinery.
//
// Volume.sinks is an array of objects: {sink, port, label}
//   sink  - the pactl sink or card object name to act on
//   port  - a sink port id, "profile:<name>" for an HDMI card-profile
//           fallback, or "" when there's no port to set (BT/USB sinks)
//   label - human-readable display name
QtObject {
    id: root

    property int volume: 0
    property bool muted: false
    property string label: ""
    property string sink: ""
    property var sinks: []

    function setVolume(pct) {
        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", pct + "%"])
    }

    function toggleMute() {
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    }

    function setSink(sinkName, port) {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/set-sink.sh", sinkName, port ?? ""])
    }

    property Process _proc: Process {
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/volume-listener.sh"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line.trim().length) return
                    try {
                        const data = JSON.parse(line)
                        root.volume = data.volume ?? root.volume
                        root.muted = data.muted ?? root.muted
                        root.label = data.label ?? root.label
                        root.sink = data.sink ?? root.sink
                        root.sinks = data.sinks ?? root.sinks
                    } catch (e) {
                        console.warn("Volume: bad JSON line from volume-listener.sh:", line)
                    }
            }
        }

        onExited: (exitCode, exitStatus) => {
            console.warn("Volume: volume-listener.sh exited (" + exitCode + "), restarting in 1s")
            restartTimer.start()
        }
    }

    property Timer restartTimer: Timer {
        interval: 1000
        onTriggered: root._proc.running = true
    }
}
