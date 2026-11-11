pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Shortcuts.qml — service singleton, replaces the eww `deflisten SHORTCUTS`.
 *
 * Instead of a long-running `shortcuts-list.sh` process being polled/streamed,
 * this reads ~/.config/quickshell/shortcuts.json directly and watches it for
 * changes with FileView. The add/remove scripts just write the file — no more
 * `eww update SHORTCUTS=...` calls needed anywhere.
 *
 * Register in shell.qml (or wherever your other singletons live) as:
 *   Shortcuts { id: shortcuts }
 * or via Singleton auto-import if your project uses one (adjust the
 * `import "root:/services"` paths in ShortcutsWindow.qml / ShortcutButton.qml
 * to match however you've wired up Theme.qml elsewhere).
 */
Singleton {
    id: root

    readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell"
    readonly property string scriptsDir: configDir + "/scripts"
    readonly property string shortcutsFile: configDir + "/state/shortcuts.json"
    property var shortcuts: []
    readonly property int maxShortcuts: 10
    readonly property bool atLimit: shortcuts.length >= maxShortcuts

    FileView {
        id: fileView
        path: root.shortcutsFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseContent(text())
        onLoadFailed: (error) => {
            console.warn("Shortcuts: failed to load", root.shortcutsFile, error)
            root.shortcuts = []
        }
    }

    function parseContent(text) {
        try {
            const data = JSON.parse(text)
            shortcuts = Array.isArray(data) ? data : []
        } catch (e) {
            console.warn("Shortcuts: bad JSON in", shortcutsFile, e)
            shortcuts = []
        }
    }

    // --- actions, mirror the old shortcuts-*.sh calls from the yuck buttons ---

    function launch(execCmd) {
        Quickshell.execDetached(["bash", scriptsDir + "/shortcuts-launch.sh", execCmd])
    }

    function remove(id) {
        Quickshell.execDetached(["bash", scriptsDir + "/shortcuts-remove.sh", id])
    }

    function openAddPicker() {
        if (atLimit) {
            Quickshell.execDetached(["notify-send", "Shortcuts", "Maximum 10 shortcuts reached"])
            return
        }
        Quickshell.execDetached(["bash", scriptsDir + "/shortcuts-add.sh"])
    }
}
