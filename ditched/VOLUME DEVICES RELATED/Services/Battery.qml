pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Battery.qml — polling equivalent of eww's (defpoll BATTERY_STATE :interval "10s" ...).
// battery-listener.sh is unchanged from your eww config (scripts/battery-listener.sh).
// CPU governor / tuned profile / turbo state follow the same Process+Timer pattern;
// wire them here the same way once you're ready to port the rest of the battery popup.
QtObject {
    id: root

    property bool hasBattery: true
    property int capacity: 100
    property string time: "---"
    property string icon: "FULL"
    property string status: "full"
    property real powerWatts: 0

    property string cpuGovernor: "unknown"
    property string tunedProfile: "unknown"
    property string turboMode: "unknown" // "ON" | "OFF" | "UNSUPPORTED"

    function setGovernor(gov) {
        Quickshell.execDetached(["bash", scriptPath("set-governor.sh"), gov])
    }
    function setTuned(profile) {
        Quickshell.execDetached(["bash", scriptPath("set-tuned.sh"), profile])
    }
    function toggleTurbo() {
        Quickshell.execDetached(["bash", scriptPath("turbo-toggle.sh")])
    }

    function scriptPath(name) {
        return Quickshell.env("HOME") + "/.config/quickshell/scripts/" + name
    }

    property Process _pollProc: Process {
        command: ["bash", root.scriptPath("battery-listener.sh")]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line.trim().length) return
                    try {
                        const data = JSON.parse(line)
                        root.capacity = data.capacity ?? root.capacity
                        root.time = data.time ?? root.time
                        root.icon = data.icon ?? root.icon
                        root.status = data.status ?? root.status
                        root.powerWatts = data.power_watts ?? root.powerWatts
                    } catch (e) {
                        console.warn("Battery: bad JSON from battery-listener.sh:", line)
                    }
            }
        }
    }

    property Timer _pollTimer: Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._pollProc.running = true
    }

    // "test -d /sys/class/power_supply/BAT0" check, run once at startup
    property Process _hasBatteryProc: Process {
        command: ["bash", "-c", "test -d /sys/class/power_supply/BAT0 && echo true || echo false"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root.hasBattery = line.trim() === "true"
        }
    }

    // ---- CPU_GOVERNOR / TUNED_PROFILE / TURBO_MODE ----
    // Ported line-for-line from your eww deflisten commands: read the value
    // once, then `touch` + `tail -f` the same trigger file your
    // set-governor.sh/set-tuned.sh/turbo-toggle.sh scripts already write to.
    // No polling — this only updates when you actually change something.
    property Process _govProc: Process {
        command: ["bash", "-c",
        "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo 'unknown'\n" +
        "mkdir -p /tmp/quickshell && touch /tmp/quickshell/cpu_governor_trigger\n" +
        "tail -f /tmp/quickshell/cpu_governor_trigger 2>/dev/null"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { if (line.trim().length) root.cpuGovernor = line.trim() }
        }
        onExited: govRestart.start()
    }
    property Timer govRestart: Timer { interval: 1000; onTriggered: root._govProc.running = true }

    property Process _tunedProc: Process {
        command: ["bash", "-c",
        "tuned-adm active 2>/dev/null | awk '/Current active profile:/{print $NF}' || echo 'unknown'\n" +
        "mkdir -p /tmp/quickshell && touch /tmp/quickshell/tuned_profile_trigger\n" +
        "tail -f /tmp/quickshell/tuned_profile_trigger 2>/dev/null"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { if (line.trim().length) root.tunedProfile = line.trim() }
        }
        onExited: tunedRestart.start()
    }
    property Timer tunedRestart: Timer { interval: 1000; onTriggered: root._tunedProc.running = true }

    property Process _turboProc: Process {
        command: ["bash", "-c",
        "bash " + root.scriptPath("turbo-status.sh") + "\n" +
        "mkdir -p /tmp/quickshell && touch /tmp/quickshell/turbo_state_trigger\n" +
        "tail -f /tmp/quickshell/turbo_state_trigger 2>/dev/null"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => { if (line.trim().length) root.turboMode = line.trim() }
        }
        onExited: turboRestart.start()
    }
    property Timer turboRestart: Timer { interval: 1000; onTriggered: root._turboProc.running = true }
}
