import QtQuick
import "../Services"

// Stands in for the popup window (`host`) when a popup's content is shown in Settings > Popups > Popup styles:
// the same properties the content reads from its window, filled from the live services so the preview shows real
// networks, devices and notifications. Nothing here opens, closes or connects anything.
QtObject {
    property var tracking: null
    property bool visible: true
    property int cur: 0                        // clipboard: highlighted row
    readonly property bool preview: true      // content can tell it is shown in Settings (sample data where there is none)
    property bool closing: false
    property bool shown: true
    property real openProgress: 1
    property real effectiveScale: 1
    property real uiScale: 1

    // Wi-Fi
    property string expandedSsid: ""
    // real lists when there are any, otherwise a few sample rows so the layout can still be arranged
    readonly property var _newNets: (Wifi.scanList || []).filter(n => n && n.ssid && !(Wifi.history || []).some(h => h.ssid === n.ssid))
    readonly property var newNetworks: _newNets.length > 0 ? _newNets : [
        { ssid: "Cafe Guest", signal: 72, security: "WPA2", connected: false },
        { ssid: "Neighbour 5G", signal: 55, security: "WPA2", connected: false },
        { ssid: "Open Network", signal: 38, security: "", connected: false }
    ]
    readonly property var savedNetworks: (Wifi.history || []).length > 0 ? Wifi.history : [
        { ssid: "Home Wi-Fi", signal: 90, security: "WPA2", connected: true },
        { ssid: "Office", signal: 64, security: "WPA2", connected: false }
    ]

    // Bluetooth
    readonly property var _newDevs: (Bluetooth.scanList || []).filter(d => !(Bluetooth.history || []).some(h => h.mac === d.mac))
    readonly property var newDevices: _newDevs.length > 0 ? _newDevs : [
        { mac: "AA:BB:CC:00:00:01", name: "Headphones" },
        { mac: "AA:BB:CC:00:00:02", name: "Keyboard" }
    ]
    property bool pairDismissed: false
    property string pinDraft: ""

    // Choice popups (power menu, power schedule, display toggle)
    property string reqId: "powermenu"
    property string mode: "list"
    property int current: 0
    property string placeholder: ""
    readonly property string title: ({ powermenu: "Power", schedule: "Schedule Action", hdmi: "Display Mode" })[reqId] ?? ""
    readonly property var items: ({
        // the exact lists rofi/powermenu.sh, hypr/schedule_action.sh and hypr/hdmi.sh send
        powermenu: ["  Shutdown", "  Reboot", "  Suspend", "  Lock", "  Logout"],
        schedule:  ["Shutdown", "Suspend", "Reboot", "Cancel Scheduled"],
        hdmi:      ["Laptop Only", "External Only", "Mirror", "Extend"]
    })[reqId] ?? ["Item 1", "Item 2", "Item 3"]
    function finish(value) {}
    function cancel() {}

    // Clipboard history
    property string query: ""
    property bool wipeArmed: false
    property bool loaded: true
    readonly property var entries: [
        { id: 1, text: "Sample copied text", image: false, info: "" },
        { id: 2, text: "https://example.com/some/long/link", image: false, info: "" },
        { id: 3, text: "Another clip", image: false, info: "" }
    ]
    readonly property var filtered: entries
    function pick(i) {}
    function remove(i) {}
    function wipe() {}
    function move(d) {}

    function close() {}
    function open() {}
    function toggle() {}
    function clearAllWithAnimation() {}
}
