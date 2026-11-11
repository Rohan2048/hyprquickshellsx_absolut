pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * ToastSettings.qml — persisted notification-toast configuration.
 *
 * Stored in ~/.config/quickshell/state/toast-settings.json, so it survives
 * reboot / re-login. The file is watched, so hand-edits apply live.
 *
 *   placement  "top-left" | "top-center" | "top-right" |
 *              "bottom-left" | "bottom-center" | "bottom-right"
 *
 * Live control:
 *   qs ipc call toast placement top-right
 *   qs ipc call toast test
 *   qs ipc call toast reset
 *   qs ipc call toast status
 */
Singleton {
    id: root

    readonly property string stateFile: Quickshell.env("HOME") + "/.config/quickshell/state/toast-settings.json"
    readonly property var validPlacements: [
        "top-left", "top-center", "top-right",
        "bottom-left", "bottom-center", "bottom-right"
    ]

    property string placement: "top-center"

    readonly property string vEdge: placement.split("-")[0]
    readonly property string hAlign: placement.split("-")[1]
    readonly property bool atBottom: vEdge === "bottom"
    readonly property bool atLeft: hAlign === "left"
    readonly property bool atRight: hAlign === "right"
    readonly property bool atCenter: hAlign === "center"

    property bool _ready: false

    function _apply(raw) {
        var d
        try { d = JSON.parse(raw) } catch (e) { _ready = true; return }
        if (!d || typeof d !== "object") { _ready = true; return }
        if (validPlacements.indexOf(d.placement) >= 0 && d.placement !== placement) placement = d.placement
            _ready = true
    }

    function _save() {
        if (!_ready) return
            file.setText(JSON.stringify({ placement: placement }, null, 2))
    }

    FileView {
        id: file
        path: root.stateFile
        blockLoading: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._apply(text())
        onLoadFailed: (error) => { root._ready = true }
    }

    Component.onCompleted: {
        try { _apply(file.text()) } catch (e) { _ready = true }
    }

    function setPlacement(p) {
        p = String(p).toLowerCase().trim()
        if (validPlacements.indexOf(p) < 0) return false
            placement = p
            _save()
            return true
    }
    function reset() { placement = "top-center"; _save() }

    function sendTest() {
        Quickshell.execDetached(["notify-send", "-a", "Settings", "Toast preview", "This is where notifications will appear."])
    }

    IpcHandler {
        target: "toast"

        function placement(p: string): string {
            return root.setPlacement(p) ? "ok" : "invalid, use: " + root.validPlacements.join(", ")
        }
        function test(): void { root.sendTest() }
        function reset(): void { root.reset() }
        function status(): string { return JSON.stringify({ placement: root.placement }) }
    }
}
