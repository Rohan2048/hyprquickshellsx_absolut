pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * IconSettings.qml -- custom bar icons and Monochromize (main shell only).
 *
 * Stored in ~/.config/quickshell/state/icon-settings.json:
 *   monoAll   true -> every icon is Monochromized unless it says otherwise
 *   icons     { "<id>": { path: "/abs/file.svg" | "", mono: "inherit" | "on" | "off" } }
 *
 * Monochromize = a flat white icon in dark mode, a flat black icon in light mode,
 * whatever the text colour is. Without it a built-in icon keeps its old look (tinted
 * with the text colour) and a custom image keeps its own colours.
 *
 * ControlIcon asks source() / isMono() by id; ids are listed in `slots`.
 */
Singleton {
    id: root

    // `file` is the built-in icon in ~/.config/icons/ that the slot shows by default.
    readonly property var slots: [
        { id: "power", label: "Power", file: "power-btn.svg" },
        { id: "music", label: "Music (vertical bar)", file: "music-placeholder.png" },
        { id: "wifi", label: "Wi-Fi on", file: "wifion.svg" },
        { id: "wifi-off", label: "Wi-Fi off", file: "wifi-off.svg" },
        { id: "bluetooth", label: "Bluetooth on", file: "bluetooth-icon.svg" },
        { id: "bluetooth-off", label: "Bluetooth off", file: "bluetooth-off.svg" },
        { id: "volume", label: "Volume", file: "sound.svg" },
        { id: "volume-mute", label: "Volume muted", file: "sound-mute.svg" },
        { id: "plug", label: "Plugged in (no battery)", file: "plug.svg" },
        { id: "bell", label: "Notifications", file: "bell.svg" },
        // Battery levels: same thresholds as scripts/battery-listener.sh (Battery.icon).
        // The charging variants of every level share these icons + the bolt below.
        { id: "battery-full", label: "Battery (full)", file: "full-battery.svg" },
        { id: "battery-above85", label: "Battery (85% and above)", file: "above85.svg" },
        { id: "battery-high", label: "Battery (70% - 84%)", file: "high-battery.svg" },
        { id: "battery-med", label: "Battery (50% - 69%)", file: "med-battery.svg" },
        { id: "battery-half", label: "Battery (40% - 49%)", file: "half-battery.svg" },
        { id: "battery-below-half", label: "Battery (20% - 39%)", file: "below-half-battery.svg" },
        { id: "battery-low", label: "Battery (10% - 19%)", file: "low-battery.svg" },
        { id: "battery-very-low", label: "Battery (below 10%)", file: "very-low-battery.svg" },
        { id: "battery-charging", label: "Charging (bolt)", file: "bolt.svg" },
        // Lock screen (Settings > Lock screen > Icons). The battery levels and the bolt above
        // are shared with the bar.
        { id: "lock-suspend", label: "Lock: Suspend", file: "suspend.svg", group: "lock" },
        { id: "lock-restart", label: "Lock: Restart", file: "restart.svg", group: "lock" },
        { id: "lock-poweroff", label: "Lock: Power off", file: "power-off.svg", group: "lock" },
        { id: "lock-settings", label: "Lock: Settings button", file: "settings.svg", group: "lock" },
        { id: "lock-wifi", label: "Lock: Wi-Fi", file: "wifion.svg", group: "lock" },
        { id: "lock-bluetooth", label: "Lock: Bluetooth", file: "bluetooth-icon.svg", group: "lock" },
        { id: "lock-theme", label: "Lock: Light / Dark mode", file: "light-dark.svg", group: "lock" },
        { id: "lock-airplane", label: "Lock: Airplane mode", file: "airplane.svg", group: "lock" }
    ]

    // The slots one Icons page lists: "bar" = everything but the lock-only icons,
    // "lock" = the lock-only icons plus the battery levels / bolt it shares with the bar.
    function slotsFor(group) {
        return root.slots.filter(function (s) {
            return group === "lock" ? (s.group === "lock" || s.id.indexOf("battery-") === 0) : s.group !== "lock"
        })
    }

    // Battery.icon ("HIGH", "HIGH_CHG", ...) -> slot id. Charging variants use the same slot.
    function batteryId(key) {
        switch (String(key).replace(/_CHG$/, "")) {
            case "FULL": return "battery-full"
            case "ABOVE85": return "battery-above85"
            case "HIGH": return "battery-high"
            case "MED": return "battery-med"
            case "HALF": return "battery-half"
            case "BELOW_HALF": return "battery-below-half"
            case "LOW": return "battery-low"
        }
        return "battery-very-low"
    }

    readonly property string iconDir: "file://" + Quickshell.env("HOME") + "/.config/icons/"

    readonly property bool monoAll: store.monoAll
    readonly property var entries: store.icons ? store.icons : ({})

    function customPath(id) {
        const e = root.entries[id]
        return (e && typeof e.path === "string") ? e.path : ""
    }
    function modeOf(id) {
        const e = root.entries[id]
        return (e && (e.mono === "on" || e.mono === "off")) ? e.mono : "inherit"
    }
    function isMono(id) {
        const m = root.modeOf(id)
        return m === "on" ? true : (m === "off" ? false : root.monoAll)
    }
    function defaultUrl(id) {
        for (let i = 0; i < root.slots.length; i++)
            if (root.slots[i].id === id) return root.iconDir + root.slots[i].file
                return ""
    }
    // the file to show for `id`: the chosen one, else `fallback` (the built-in)
    function source(id, fallback) {
        const p = root.customPath(id)
        return p !== "" ? "file://" + p : fallback
    }

    function _patch(id, patch) {
        const all = Object.assign({}, root.entries)
        const e = Object.assign({ path: "", mono: "inherit" }, all[id] ? all[id] : {}, patch)
        if (e.path === "" && e.mono === "inherit") delete all[id]
            else all[id] = e
                store.icons = all
    }
    function setPath(id, path) { root._patch(id, { path: String(path) }) }
    function clearPath(id) { root._patch(id, { path: "" }) }
    function setMode(id, mode) { root._patch(id, { mono: (mode === "on" || mode === "off") ? mode : "inherit" }) }
    function setAll(on) { store.monoAll = !!on }
    function resetAll() { store.monoAll = false; store.icons = ({}) }

    FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/state/icon-settings.json"
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: (err) => writeAdapter()   // first run: create the file
        adapter: JsonAdapter {
            id: store
            property bool monoAll: false
            property var icons: ({})
        }
    }
}
