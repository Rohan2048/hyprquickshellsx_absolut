pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    property string device: "Bluetooth-OFF"
    property string deviceMac: ""
    property var history: []
    property var connectedMacs: []

    readonly property bool radioOn: device !== "Bluetooth-OFF"
    readonly property bool connected: radioOn && device !== "Bluetooth-ON"

    property bool liveMode: false
    function toggleLiveMode() { liveMode = !liveMode }
    property var scanList: []

    property string pairingMac: ""
    property string pairingName: ""
    property bool pairingIncoming: false
    property string pairError: ""
    property var pendingConfirm: null
    property var pendingPin: null

    property string connectedName: ""
    function clearConnected() { connectedName = "" }

    function startPair(mac, name) {
        pairingMac = mac
        pairingName = name
        pairingIncoming = false
        pairError = ""
        pendingConfirm = null
        pendingPin = null
        _agent.write("pair " + mac + " " + name + "\n")
    }
    function confirmYes() {
        _agent.write("yes\n")
        pendingConfirm = null
    }
    function confirmNo() {
        _agent.write("no\n")
        pendingConfirm = null
        pairError = "Pairing rejected for " + pairingName
    }
    function submitPin(pin) {
        _agent.write("pin " + pin + "\n")
        pendingPin = null
    }
    function dismissError() { pairError = "" }

    function _adoptIncoming(mac, name) {
        if (pairingMac === "") {
            pairingMac = mac || ""
            pairingName = name || (mac || "Unknown device")
            pairingIncoming = true
        }
    }

    function _handleAgentLine(line) {
        let data
        try {
            data = JSON.parse(line)
        } catch (e) {
            return
        }
        if (data.type === "confirm") {
            _adoptIncoming(data.mac, data.name)
            pendingConfirm = { code: data.passkey }
        } else if (data.type === "pin") {
            _adoptIncoming(data.mac, data.name)
            pendingPin = {}
        } else if (data.type === "paired") {
            if (!data.mac || data.mac === pairingMac) {
                pendingConfirm = null
                pendingPin = null
            }
        } else if (data.type === "connected") {
            // Attribute to the device THIS event is about, not whatever
            // pairingName currently holds — the user may have already
            // clicked a different device while this one was still
            // resolving asynchronously.
            connectedName = data.name || pairingName
            if (!data.mac || data.mac === pairingMac) {
                pairError = ""
                pairingMac = ""
                pairingName = ""
                pairingIncoming = false
            }
        } else if (data.type === "cancel") {
            if (!data.mac || data.mac === pairingMac) {
                pendingConfirm = null
                pendingPin = null
                if (pairingIncoming) {
                    pairingMac = ""
                    pairingName = ""
                    pairingIncoming = false
                }
            }
        } else if (data.type === "error") {
            pairError = "Pairing failed with " + (data.name || pairingName)
            if (!data.mac || data.mac === pairingMac) {
                pendingConfirm = null
                pendingPin = null
            }
        }
    }

    property Process _agent: Process {
        id: agentProc
        command: ["python3", root.scriptPath("bt-agent.py")]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root._handleAgentLine(line)
        }
        onExited: agentRestart.start()
    }
    property Timer agentRestart: Timer {
        interval: 1000
        onTriggered: root._agent.running = true
    }

    function toggleRadio() {
        Quickshell.execDetached(["bash", "-c",
                                "if rfkill list bluetooth | grep -q 'Soft blocked: no'; then rfkill block bluetooth; else rfkill unblock bluetooth; fi"])
    }

    function scriptPath(name) {
        return Quickshell.env("HOME") + "/.config/quickshell/scripts/" + name
    }

    function connectTo(mac) {
        Quickshell.execDetached(["bash", scriptPath("bt-history.sh"), "connect", mac])
    }
    function disconnect(mac) {
        Quickshell.execDetached(["bash", scriptPath("bt-history.sh"), "disconnect", mac])
    }
    function forget(mac) {
        Quickshell.execDetached(["bash", scriptPath("bt-history.sh"), "forget", mac])
    }

    property Process _proc: Process {
        command: ["bash", root.scriptPath("bt-history.sh")]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line.trim().length) return
                    try {
                        const data = JSON.parse(line)
                        root.device = data.device ?? root.device
                        root.deviceMac = data.deviceMac ?? root.deviceMac
                        root.history = data.history ?? root.history
                        root.connectedMacs = data.connectedMacs ?? root.connectedMacs
                    } catch (e) {
                        console.warn("Bluetooth: bad JSON from bt-history.sh:", line)
                    }
            }
        }
        onExited: restartTimer.start()
    }

    property Timer restartTimer: Timer {
        interval: 1000
        onTriggered: root._proc.running = true
    }

    property Process _scanProc: Process {
        running: root.liveMode
        command: ["bash", root.scriptPath("bt-scan-listener.sh")]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line.trim().length) return
                    try {
                        root.scanList = JSON.parse(line)
                    } catch (e) {
                        console.warn("Bluetooth: bad JSON from bt-scan-listener.sh:", line)
                    }
            }
        }
        onExited: if (root.liveMode) scanRestartTimer.start()
    }

    property Timer scanRestartTimer: Timer {
        interval: 800
        onTriggered: if (root.liveMode) root._scanProc.running = Qt.binding(function() { return root.liveMode })

    }
}
