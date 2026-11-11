import QtQuick
import Quickshell
import Quickshell.Hyprland

Item {
    id: root

    property var targetWindows: []
    property bool active: false
    // set true while the popup needs typing: uses the focus grab (gives keyboard focus) instead of passthrough
    property bool needsKeyboard: false

    signal dismissed()

    readonly property var _windowList: Array.isArray(targetWindows) ? targetWindows : [targetWindows]
    readonly property bool _pass: ClickAway.passthrough && !root.needsKeyboard

    property var _trackers: []
    function _track() {
        var t = []
        for (var i = 0; i < root._windowList.length; i++) {
            var w = root._windowList[i]
            if (!w || !w.contentItem) continue
                var h = w.contentItem.__caHover
                if (!h) {
                    h = Qt.createQmlObject('import QtQuick; HoverHandler { }', w.contentItem, "ClickAwayHover")
                    w.contentItem.__caHover = h
                }
                t.push(h)
        }
        root._trackers = t
    }

    function checkPress() {
        if (!root.active || !root._pass) return
            for (var i = 0; i < root._trackers.length; i++)
                if (root._trackers[i].hovered) return
                    root.dismissed()
    }

    HyprlandFocusGrab {
        id: grab
        windows: root._windowList
        onCleared: root.dismissed()
    }

    function _sync() {
        if (root.active && root._pass) {
            root._track()
            ClickAway.register(root)
            if (grab.active) grab.active = false
        } else {
            ClickAway.unregister(root)
            var want = root.active && !root._pass
            if (grab.active !== want) grab.active = want
        }
    }
    onActiveChanged: _sync()
    on_PassChanged: _sync()
    Component.onCompleted: _sync()
    Component.onDestruction: ClickAway.unregister(root)
}
