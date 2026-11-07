pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * BatteryInfo.qml -- Settings > Battery. Main shell only.
 *
 * Everything the Battery page shows, read through scripts/battery-info.py (sysfs, no extra packages):
 *   info   live numbers: percentage, power (W), energy (Wh), design capacity, health, cycles,
 *          manufacturer, model, time left, and what charge limit this laptop supports
 *   hist   the last 24 h (one sample every 2 minutes) + a summary + the last 30 days
 *
 * The sampler runs for as long as the shell runs (shell.qml touches this singleton once at start), so the
 * 24 h graph is already filled when you open the page. Machines without a battery run the check once
 * (`hasBattery` = false) and then do nothing. The live numbers refresh every 5 s, but only while
 * the Battery page is open (`watching`).
 *
 * Charge limit: setLimit(true) stops charging at 80 %, setLimit(false) charges to 100 %. The script writes the
 * kernel file through `sudo -n tee` and remembers the choice (it puts it back by itself if the firmware forgets).
 */
Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/quickshell/scripts/battery-info.py"

    property bool watching: false
    property bool loaded: false
    // false on desktops and laptops without a battery: Settings then has no Battery section at all
    readonly property bool hasBattery: root.loaded && root.info.present !== false
    property var info: ({ present: true })
    property var hist: ({ now: 0, points: [], summary: ({}), daily: [] })

    property bool limitBusy: false
    property string limitError: ""

    // Called once from shell.qml: merely naming the singleton creates it, which starts the sampler below.
    function start() { root.refresh() }

    function refresh() {
        if (!infoProc.running) infoProc.running = true
    }
    function refreshHistory() {
        if (!histProc.running) histProc.running = true
    }

    function setLimit(on) {
        if (root.limitBusy) return
            root.limitBusy = true
            root.limitError = ""
            limitProc.command = ["python3", root.script, "limit", on ? "on" : "off"]
            limitProc.running = true
    }

    Process {
        id: infoProc
        command: ["python3", root.script, "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.info = JSON.parse(text); root.loaded = true } catch (e) { }
            }
        }
    }

    Process {
        id: histProc
        command: ["python3", root.script, "history"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.hist = JSON.parse(text) } catch (e) { }
            }
        }
    }

    Process {
        id: limitProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.limitBusy = false
                try {
                    const r = JSON.parse(text)
                    root.limitError = r.ok ? "" : (r.error || "The laptop refused the change.")
                } catch (e) {
                    root.limitError = "Could not change the charge limit."
                }
                root.refresh()
            }
        }
    }

    // log a sample every 2 minutes, always (also re-applies the saved charge limit)
    Process { id: sampler; command: ["python3", root.script, "sample"] }
    Timer {
        interval: 120000
        running: !root.loaded || root.hasBattery
        repeat: true
        triggeredOnStart: true
        onTriggered: { if (!sampler.running) sampler.running = true }
    }

    // live numbers + graph while the Battery page is open
    Timer {
        interval: 5000
        running: root.watching
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
    Timer {
        interval: 30000
        running: root.watching
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshHistory()
    }
}
