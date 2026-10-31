pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * SoundDevices.qml -- Settings > Sounds. Main shell only.
 *
 * Every output (speakers, headphones, HDMI, Bluetooth, USB ...) and every input (microphones) as its own
 * device, read through scripts/sound-devices.py (pactl, so it works on PipeWire and PulseAudio):
 * the card's profiles, the port, left / right volume, mute, combining several outputs into one, and which one is the default.
 * The lists follow `pactl subscribe` while `watching` is on (the Sounds page turns it on).
 *
 * Slider changes are coalesced (one pactl call per 90 ms per device) and every command runs one at a time.
 * The laptop-speaker delay is sent once, 450 ms after the slider stops, so nothing is heard while dragging.
 */
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/scripts/sound-devices.py"

    readonly property string micScript: Quickshell.env("HOME") + "/.config/quickshell/scripts/mic-level.py"

    property var outputs: []
    property var inputs: []
    property string defaultSink: ""
    property string defaultSource: ""
    property var combined: ({ active: false, isDefault: false, members: [], channels: [], muted: false })
    property var delay: ({ available: false, running: false, ms: 0, speaker: "" })   // laptop-speaker delay, -10..500 ms
    property var outNames: []          // device names only: the page's lists follow these, so a volume
    property var inNames: []           // change never rebuilds a card (and never drops a slider mid-drag)
    property string error: ""
    property bool watching: false

    // ── reading ──
    function refresh() {
        if (lister.running) { root._again = true; return }
        lister.running = true
    }
    property bool _again: false
    Process {
        id: lister
        command: ["python3", root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.error = d.error ?? ""
                    // while a slider is being moved the numbers we just set are the truth
                    if (!root._holding) {
                        root.outputs = d.outputs ?? []
                        root.inputs = d.inputs ?? []
                        root._names()
                    }
                    root.combined = d.combined ?? root.combined
                    if (!delayTimer.running) root.delay = d.delay ?? root.delay
                        root.defaultSink = d.defaultSink ?? ""
                        root.defaultSource = d.defaultSource ?? ""
                } catch (e) { root.error = "Could not read the audio devices" }
            }
        }
        onExited: { if (root._again) { root._again = false; root.refresh() } }
    }
    function _names() {
        const o = root.outputs.map(function (x) { return x.name })
        const i = root.inputs.map(function (x) { return x.name })
        if (o.join("\n") !== root.outNames.join("\n")) root.outNames = o
            if (i.join("\n") !== root.inNames.join("\n")) root.inNames = i
    }
    // the device now, looked up by name (bindings that call this follow every refresh)
    function byName(kind, name) {
        const l = kind === "sink" ? root.outputs : root.inputs
        for (let i = 0; i < l.length; i++) if (l[i].name === name) return l[i]
            return ({ name: name, desc: name, kind: "audio", channels: [], profiles: [], ports: [], muted: false, isDefault: false })
    }
    property bool _holding: false
    Timer { id: holdTimer; interval: 500; onTriggered: { root._holding = false; root.refresh() } }
    Timer { id: soon; interval: 160; onTriggered: root.refresh() }
    onWatchingChanged: { if (root.watching) root.refresh() }

    Process {
        id: events
        running: root.watching
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (line.indexOf("sink") >= 0 || line.indexOf("source") >= 0 || line.indexOf("card") >= 0 || line.indexOf("server") >= 0)
                    soon.restart()
            }
        }
    }

    // ── running commands, one at a time ──
    property var _queue: []
    function _enqueue(args) {
        root._queue.push(args)
        root._next()
    }
    function _next() {
        if (runner.running || root._queue.length === 0) return
            const a = root._queue.shift()
            runner.command = ["python3", root.script].concat(a)
            runner.running = true
    }
    Process {
        id: runner
        onExited: {
            if (root._queue.length > 0) root._next()
                else soon.restart()
        }
    }

    // ── helpers on the lists ──
    function _dev(kind, name) {
        const l = kind === "sink" ? root.outputs : root.inputs
        for (let i = 0; i < l.length; i++) if (l[i].name === name) return l[i]
            return null
    }
    function _touch(kind) {
        if (kind === "sink") root.outputs = root.outputs.slice()
            else root.inputs = root.inputs.slice()
    }

    // ── actions ──
    function setProfile(card, profile) { if (card !== "") root._enqueue(["set-profile", card, profile]) }
    function setPort(kind, name, port) { root._enqueue(["set-port", kind, name, port]) }
    function setDefault(kind, name) { root._enqueue(["set-default", kind, name]) }
    // play to several outputs at once (needs two or more), or stop
    function combine(members) { root._enqueue(["combine", "on"].concat(members)) }
    function uncombine() { root._enqueue(["combine", "off"]) }
    function setCombinedVolume(pct) {
        pct = Math.max(0, Math.min(100, Math.round(pct)))
        const c = root.combined
        root.combined = { active: c.active, isDefault: c.isDefault, members: c.members, muted: c.muted,
            channels: c.channels.map(function (x) { return { ch: x.ch, pct: pct } }) }
            root._holding = true
            holdTimer.restart()
            root._pending["sink|qs_combined"] = c.channels.map(function () { return String(pct) })
            volTimer.restart()
    }
    function toggleMute(kind, name) {
        const d = root._dev(kind, name)
        if (d) { d.muted = !d.muted; root._touch(kind) }
        root._enqueue(["mute", kind, name, "toggle"])
    }

    // laptop-speaker delay, -10..500 ms. Only the number on screen changes while dragging; the audio is
    // touched once, 450 ms after the slider stops, so sliding makes no noise.
    property int _delayMs: 0
    function setSpeakerDelay(ms) {
        ms = Math.max(-10, Math.min(500, Math.round(ms)))
        const d = root.delay
        root.delay = { available: d.available, running: d.running, speaker: d.speaker, ms: ms }
        root._delayMs = ms
        delayTimer.restart()
    }
    Timer {
        id: delayTimer
        interval: 450
        onTriggered: root._enqueue(["delay", String(root._delayMs)])
    }

    // volume: ch = channel index, or -1 for every channel at once
    property var _pending: ({})
    function setVolume(kind, name, ch, pct) {
        const d = root._dev(kind, name)
        if (!d) return
            pct = Math.max(0, Math.min(150, Math.round(pct)))
            for (let i = 0; i < d.channels.length; i++)
                if (ch < 0 || i === ch) d.channels[i].pct = pct
                    root._touch(kind)
                    root._holding = true
                    holdTimer.restart()
                    root._pending[kind + "|" + name] = d.channels.map(function (c) { return String(c.pct) })
                    volTimer.restart()
    }
    Timer {
        id: volTimer
        interval: 90
        onTriggered: {
            const p = root._pending
            root._pending = ({})
            for (const k in p) {
                const i = k.indexOf("|")
                root._enqueue(["volume", k.substring(0, i), k.substring(i + 1)].concat(p[k]))
            }
        }
    }

    // ── what the page shows ──
    function level(d) {                       // the louder of the channels, for the one big slider
        let m = 0
        for (let i = 0; i < d.channels.length; i++) m = Math.max(m, d.channels[i].pct)
            return m
    }
    function chLabel(c) {
        const n = (c || "").toLowerCase()
        if (n === "front-left" || n === "left") return "Left"
            if (n === "front-right" || n === "right") return "Right"
                if (n === "mono") return "Mono"
                    if (n === "front-center") return "Centre"
                        if (n === "lfe") return "Sub"
                            return c
    }
    function kindLabel(k) {
        return ({ bluetooth: "Bluetooth", hdmi: "HDMI / DisplayPort", usb: "USB", headphones: "Headphones",
            speaker: "Speakers", line: "Line / Aux", mic: "Microphone" })[k] || "Audio"
    }
}
