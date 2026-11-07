pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Volume.qml — event-driven volume state.
//
// volume-listener.sh  -> volume / muted / label / sink / sinks
// audio-ports.py      -> ports / pinned / activePortKey
//
// `outputs` is the SINGLE list the UI should render. It merges the two
// sources above and removes duplicates (the same physical device showing up
// once as a sink description and once as a port entry) and the PipeWire
// "Dummy Output" fallback. Do not render `sinks`, `ports` or `pinned`
// directly in the popup.
QtObject {
    id: root

    property int volume: 0
    property bool muted: false
    property string label: ""
    property string sink: ""
    property var sinks: []

    property var ports: []
    property var pinned: []
    property string activePortKey: ""

    // ── Single source of truth for the output picker ─────────────────────
    // Each item: { key, label, active, card, port, sink }
    //   card/port set  -> activate with setPort(card, port)
    //   sink set       -> activate with setSink(sink)
    property var outputs: {
        const items = []
        const seen = new Set()

        // 1. Port entries win (pinned speakers first, then HDMI/aux/etc.)
        for (const e of pinned.concat(ports)) {
            items.push({
                key: e.key,
                label: e.label,
                active: e.active,
                card: e.card,
                port: e.port,
                sink: ""
            })
            if (e.sinkDesc) seen.add(e.sinkDesc)
        }

        // 2. Sinks no port entry already covers (e.g. Bluetooth, which
        //    audio-ports.py skips on purpose). Never the dummy fallback.
        for (const d of sinks) {
            if (d === "Dummy Output" || seen.has(d)) continue
                items.push({
                    key: "sink|" + d,
                    label: d,
                    active: d === sink,
                    card: "",
                    port: "",
                    sink: d
                })
        }

        return items
    }

    function setVolume(pct) {
        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", pct + "%"])
    }

    function toggleMute() {
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    }

    function setSink(sinkName) {
        Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/set-sink.sh", sinkName])
    }

    function setPort(cardName, portName) {
        Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/audio-ports.py", "set", cardName, portName])
    }

    // Unconditionally switch back to the built-in laptop speakers, regardless
    // of whatever is currently active. Always issues the port-activation
    // commands (profile switch + set-default-sink + move streams) rather than
    // short-circuiting when the speakers already look active, since the
    // "pinned" bookkeeping can lag a manual profile change.
    function resetToDefault() {
        const speaker = pinned.find((p) => p.label === "Speakers") || pinned[0]
        if (speaker) setPort(speaker.card, speaker.port)
    }

    // Convenience: activate any item from `outputs`
    function activate(item) {
        if (item.card !== "") setPort(item.card, item.port)
            else setSink(item.sink)
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

    property Process _portsProc: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/audio-ports.py", "listen"]
        running: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line.trim().length) return
                    try {
                        const data = JSON.parse(line)
                        root.ports = data.ports ?? root.ports
                        root.pinned = data.pinned ?? root.pinned
                        root.activePortKey = data.activeKey ?? root.activePortKey
                    } catch (e) {
                        console.warn("Volume: bad JSON line from audio-ports.py:", line)
                    }
            }
        }

        onExited: (exitCode, exitStatus) => {
            console.warn("Volume: audio-ports.py exited (" + exitCode + "), restarting in 1s")
            portsRestartTimer.start()
        }
    }

    property Timer portsRestartTimer: Timer {
        interval: 1000
        onTriggered: root._portsProc.running = true
    }
}
