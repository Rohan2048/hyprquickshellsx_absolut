import QtQuick
import Quickshell
import Quickshell.Hyprland

// Drop this into any popup's root and point it at that popup's window(s).
// It grabs input focus so the popup keeps working normally, and closes
// itself the moment you click/touch anywhere outside it. Wayland doesn't
// allow forwarding that same click to whatever's underneath (no client
// can synthesize input into another client's surface) - so the outside
// click only dismisses the popup; a second click is needed to interact
// with the window/workspace behind it. This matches how GTK popovers,
// Qt popups, and Hyprland's own context menus behave.
Item {
    id: root

    property var targetWindows: []
    property bool active: false

    signal dismissed()

    readonly property var _windowList: Array.isArray(targetWindows) ? targetWindows : [targetWindows]

    HyprlandFocusGrab {
        id: grab
        windows: root._windowList
        onCleared: root.dismissed()
    }

    onActiveChanged: {
        if (active && !grab.active) grab.active = true;
        else if (!active && grab.active) grab.active = false;
    }

    Connections {
        target: grab
        function onActiveChanged() {
            if (!grab.active && root.active) {
                // grab died on its own (outside click) - dismissed() already
                // fired via onCleared; parent sets active=false in response
            }
        }
    }
}
