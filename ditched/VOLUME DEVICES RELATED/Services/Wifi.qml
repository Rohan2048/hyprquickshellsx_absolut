pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
// Wifi.qml — event-driven wifi state via scripts/wifi-history.sh (unchanged,
// same nmcli monitor loop as your eww deflisten WIFI_STATE). Bar-level state
// only for now (ssid + on/off) — WifiPopup.qml with the saved-networks list
// is the next thing to port.
QtObject {
    id: root
    property string ssid: "Disconnected"
    property var history: []
    readonly property bool radioOn: ssid !== "WiFi-OFF"
    readonly property bool connected: radioOn && ssid !== "Disconnected"
    // Gear icon next to the ON/OFF toggle — reveals this live list.
    property bool liveMode: false
    function toggleLiveMode() { liveMode = !liveMode }
    property var scanList: [] // [{ssid, signal, security, connected}, ...] while liveMode is on

    // Driven by WifiPopup's onVisibleChanged. Scanning must never run
    // unless the popup is actually open on screen, regardless of what
    // liveMode is set to — this is what stops the scan process from
    // surviving popup close.
    property bool popupOpen: false

    // ---- Auth failure state — surfaced by connectWithPassword below when
    // nmcli exits non-zero (wrong password, secrets rejected, etc). Popup
    // reads authError/authErrorSsid to show "Authentication failed" next
    // to the network that failed, and calls dismissAuthError() to clear it. ----
    property string authError: ""
    property string authErrorSsid: ""
    function dismissAuthError() { root.authError = "" }

    // ---- Connecting state — true while connectProc is actively trying to
    // authenticate against connectingSsid. Popup reads this to show a
    // "Connecting..." status without reserving its own layout space. ----
    property bool connecting: false
    property string connectingSsid: ""

    function _q(s) { return "'" + s.replace(/'/g, "'\\''") + "'" }

    function toggleRadio() {
        Quickshell.execDetached(["bash", "-c",
                                "if nmcli -t -f WIFI g | grep -q enabled; then nmcli radio wifi off; else nmcli radio wifi on; fi"])
    }
    function scriptPath(name) {
        return Quickshell.env("HOME") + "/.config/quickshell/scripts/" + name
    }

    // Single entry point for "connect me to this ssid" from anywhere in the
    // UI (open-network click, saved-network click via forceConnectTo).
    // No-op if we're already on that ssid — clicking the currently-active
    // network should do nothing. Otherwise disconnects whatever's currently
    // active first, then connects to the target, so switching is always a
    // clean down->up rather than relying on nmcli/NetworkManager to sort out
    // an overlapping connect-while-connected.
    function connectTo(ssidName) {
        if (ssidName === root.ssid) return

            const disconnectCmd = root.connected
            ? ("nmcli connection down " + root._q(root.ssid) + "; sleep 0.5; ")
            : ""
            Quickshell.execDetached(["bash", "-c",
                                    disconnectCmd +
                                    "bash " + scriptPath("wifi-history.sh") + " connect " + root._q(ssidName) +
                                    " && bash " + scriptPath("wifi-history.sh") + " update " + root._q(ssidName)])
    }
    // Drops the active connection without deleting the saved NM profile —
    // ssid stays in history, just no longer connected. Same _q()-quoting
    // pattern as connectTo/connectWithPassword.
    function disconnect(ssidName) {
        Quickshell.execDetached(["bash", "-c",
                                "nmcli connection down " + root._q(ssidName)])
    }
    // Used by WifiPopup's NameEntryButton in the Saved Networks list. Kept
    // as its own name since the popup calls it explicitly, but the
    // disconnect-then-connect behavior now lives in connectTo itself, so
    // this just delegates.
    function forceConnectTo(ssidName) {
        connectTo(ssidName)
    }
    // For brand-new/secured networks — called directly from the popup's inline
    // password field. Runs through connectProc (tracked, not execDetached) so
    // we can see the exit code: 0 means nmcli actually authenticated, non-zero
    // means the password/secrets were rejected. Only registers the ssid into
    // history (moving it from "new networks" into "Saved Networks") on success;
    // on failure, sets authError instead so the popup can surface it.
    // Same no-op-if-already-connected guard, and disconnects the current
    // network first (mirrors connectTo) so switching to a new secured
    // network is also a clean down->up.
    function connectWithPassword(ssidName, password) {
        if (connectProc.running) return
            if (ssidName === root.ssid) return
                root.authError = ""
                root.connecting = true
                root.connectingSsid = ssidName
                connectProc.ssidName = ssidName
                connectProc.pendingPassword = password
                connectProc.running = true
    }
    property Process connectProc: Process {
        property string ssidName: ""
        property string pendingPassword: ""
        running: false
        command: ["bash", "-c",
        (root.connected ? ("nmcli connection down " + root._q(root.ssid) + "; sleep 0.5; ") : "") +
        "nmcli device wifi connect " + root._q(ssidName) + " password " + root._q(pendingPassword)]
        onExited: (exitCode) => {
            root.connecting = false
            if (exitCode === 0) {
                root.authError = ""
                const ssid = connectProc.ssidName.replace(/ +$/, "")
                Quickshell.execDetached(["bash", root.scriptPath("wifi-history.sh"), "update", ssid])
                let hist = root.history.filter(h => h.ssid !== ssid)
                hist.unshift({ ssid: ssid })
                root.history = hist.slice(0, 10)
            } else {
                root.authError = "Authentication failed"
                root.authErrorSsid = connectProc.ssidName
            }
        }
    }
    // Deletes the NM connection profile AND removes the ssid from the
    // persisted history file (wifi-history.sh handles both now). Also
    // splices it out of `history` here immediately — the row disappears
    // on click instead of waiting for the background nmcli-monitor loop
    // to notice and re-emit, which may not happen right away since a
    // profile deletion doesn't always produce a monitor line that matches
    // what the script watches for.
    function forget(ssidName) {
        const wasActive = (ssidName === root.ssid)
        Quickshell.execDetached(["bash", "-c",
                                "nmcli connection delete " + root._q(ssidName) + "; " +
                                "bash " + scriptPath("wifi-history.sh") + " forget " + root._q(ssidName)])
        root.history = root.history.filter(h => h.ssid !== ssidName)
        if (wasActive) root.ssid = "Disconnected"
    }
    property Process _proc: Process {
        command: ["bash", root.scriptPath("wifi-history.sh")]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line.trim().length) return
                    try {
                        const data = JSON.parse(line)
                        root.ssid = data.ssid ?? root.ssid
                        root.history = data.history ?? root.history
                    } catch (e) {
                        console.warn("Wifi: bad JSON from wifi-history.sh:", line)
                    }
            }
        }
        onExited: restartTimer.start()
    }
    property Timer restartTimer: Timer {
        interval: 1000
        onTriggered: root._proc.running = true
    }
    // Live scan — only runs while the gear icon has liveMode toggled on
    // AND the popup is actually visible, so it's not burning a background
    // `nmcli rescan` loop when nothing's on screen to show it to.
    property Process _scanProc: Process {
        running: root.liveMode && root.popupOpen
        command: ["bash", root.scriptPath("wifi-scan-listener.sh")]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line.trim().length) return
                    try {
                        root.scanList = JSON.parse(line)
                    } catch (e) {
                        console.warn("Wifi: bad JSON from wifi-scan-listener.sh:", line)
                    }
            }
        }
        onExited: if (root.liveMode && root.popupOpen) scanRestartTimer.start()
    }
    property Timer scanRestartTimer: Timer {
        interval: 1000
        onTriggered: root._scanProc.running = true
    }
}
