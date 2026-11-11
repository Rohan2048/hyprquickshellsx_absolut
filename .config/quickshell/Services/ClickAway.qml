pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Click-away with click passthrough.
// hyprland.lua has a NON-consuming mouse bind that runs `qs ipc call clickaway press`: Hyprland tells us a button was
// pressed and still delivers that click to whatever is under the cursor. Every active ClickAwayCloser registers here,
// and on a press the ones whose window is not under the pointer dismiss themselves.
// If that bind is not installed (checked once at start: a non-consuming exec bind on mouse:272 must exist in `hyprctl binds`), ClickAwayCloser falls back to the old
// HyprlandFocusGrab, so popups can never become impossible to close.
Singleton {
    id: root

    property bool passthrough: false
    property var closers: []

    function register(c) { if (closers.indexOf(c) < 0) closers = closers.concat([c]) }
    function unregister(c) { closers = closers.filter(x => x !== c) }

    Process {
        id: probe
        command: ["sh", "-c", "hyprctl binds 2>/dev/null | awk -v RS= '/non_consuming/ && /key: mouse:272/ && /exec_cmd/ {f=1} END{exit !f}'"]
        running: true
        onExited: (code) => root.passthrough = (code === 0)
    }

    IpcHandler {
        target: "clickaway"
        function press(): void {
            var list = root.closers.slice()
            for (var i = 0; i < list.length; i++) list[i].checkPress()
        }
    }
}
