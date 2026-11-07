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

    // The + button. Style comes from Settings > Popups > Shortcuts palette.
    property bool pickerOpen: false

    function openAddPicker() {
        if (atLimit) {
            Quickshell.execDetached(["notify-send", "Shortcuts", "Maximum " + maxShortcuts + " shortcuts reached"])
            return
        }
        if (PopupSettings.shortcutsStyle === "quickshell") root.pickerOpen = true
        else Quickshell.execDetached(["bash", scriptsDir + "/shortcuts-add.sh"])
    }

    // Quickshell-style picker: store a DesktopEntry from the standard app list.
    // `desktopId` lets launching go through the entry itself (field codes, terminal apps),
    // `icon` is the entry's icon name or absolute path (ShortcutButton resolves either).
    function addFromEntry(entry) {
        if (atLimit) { root.openAddPicker(); return false }
        const list = Array.isArray(root.shortcuts) ? root.shortcuts.slice() : []
        for (let i = 0; i < list.length; i++) {
            if (list[i].desktopId && list[i].desktopId === entry.id) {
                Quickshell.execDetached(["notify-send", "Shortcuts", entry.name + " is already a shortcut"])
                return false
            }
        }
        list.push({
            id: String(Date.now()) + String(Math.floor(Math.random() * 1000)),
            name: entry.name,
            exec: String(entry.execString || "").replace(/\s%[a-zA-Z%]/g, "").trim(),
            icon: entry.icon || "",
            desktopId: entry.id
        })
        root.shortcuts = list
        fileView.setText(JSON.stringify(list, null, 2))
        Quickshell.execDetached(["notify-send", "Shortcuts", "Added: " + entry.name])
        return true
    }

    // Launch a stored shortcut: through its desktop entry when it has one, else its command.
    function launchShortcut(sc) {
        if (sc.desktopId) {
            const e = DesktopEntries.byId(sc.desktopId)
            if (e) { e.execute(); return }
        }
        root.launch(sc.exec)
    }
}
