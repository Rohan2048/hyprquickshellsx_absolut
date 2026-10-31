pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property int workspaceCount: 10
    property var slots: []

    function hyprIdForSlot(slot) {
        return slot === 0 ? 10 : slot
    }

    // Kick off a refresh. Hyprland.refreshToplevels()/refreshWorkspaces()
    // are async — lastIpcObject on each toplevel/workspace updates some
    // time later when the IPC response comes back. Rebuilding slots in
    // the same tick reads stale/undefined data for anything except the
    // just-focused window. So: request the refresh, then rebuild after
    // a short debounce instead of immediately.
    function refresh() {
        // Only issue the IPC refresh once per burst of events (when the
        // debounce window isn't already counting down), not on every
        // single raw event. rebuildSlots() still fires 80ms after the
        // burst settles, same as before, giving the async
        // refreshToplevels()/refreshWorkspaces() responses the same
        // landing-time gap they always had before this change.
        if (!rebuildTimer.running) {
            Hyprland.refreshToplevels()
            Hyprland.refreshWorkspaces()
        }
        rebuildTimer.restart()
    }

    function rebuildSlots() {
        const next = []
        for (let i = 0; i < workspaceCount; i++) {
            const hid = hyprIdForSlot(i)
            const ws = Hyprland.workspaces.values.find(w => w.id === hid)
            const monitor = ws ? ws.monitor : null
            const mIpc = monitor ? monitor.lastIpcObject : null
            const reserved = mIpc && mIpc.reserved ? mIpc.reserved : [0, 0, 0, 0]
            // Hyprland reports monitor width/height in physical pixels but
            // client "at"/"size" in logical (scale-divided) coordinates.
            // Without dividing by scale, usable area is too large relative
            // to window coordinates, making every preview render shrunk.
            const scale = mIpc && mIpc.scale ? mIpc.scale : 1
            const monX = monitor ? monitor.x : 0
            const monY = monitor ? monitor.y : 0
            const monW = monitor ? monitor.width / scale : 1920
            const monH = monitor ? monitor.height / scale : 1080

            next.push({
                slot: i,
                id: hid,
                label: String(i),
                      occupied: !!ws,
                      active: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id === hid : false,
                      windowCount: ws && ws.lastIpcObject ? (ws.lastIpcObject.windows ?? 0) : 0,
                      toplevels: ws && ws.toplevels ? ws.toplevels.values : [],
                      usableX: monX + reserved[0],
                      usableY: monY + reserved[1],
                      usableWidth: monW - reserved[0] - reserved[2],
                      usableHeight: monH - reserved[1] - reserved[3]
            })
        }
        slots = next
    }

    function switchTo(slot) {
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + hyprIdForSlot(slot) + " })")
    }

    Timer {
        id: rebuildTimer
        interval: 80
        repeat: false
        onTriggered: root.rebuildSlots()
    }

    Component.onCompleted: rebuildSlots()

    Connections {
        target: Hyprland
        function onRawEvent(event) { root.refresh() }
    }
}
