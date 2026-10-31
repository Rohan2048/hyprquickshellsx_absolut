pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * SBSQuickApps.qml — the same pinned-app-shortcut pattern as
 * Services/Shortcuts.qml, but capped at 4 entries and backed by its own
 * state file so the normal 10-slot Quick Apps list and the Super Battery
 * Saver 4-slot list are completely independent.
 *
 * Reuses scripts/shortcuts-add.sh and scripts/shortcuts-remove.sh (now
 * parametrized to accept a target file / max count / notify label) rather
 * than duplicating the app-scan + rofi-picker logic.
 */
Singleton {
    id: root

    readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell"
    readonly property string scriptsDir: configDir + "/scripts"
    readonly property string quickAppsFile: configDir + "/state/sbs-quickapps.json"
    property var apps: []
    readonly property int maxApps: 4
    readonly property bool atLimit: apps.length >= maxApps

    FileView {
        id: fileView
        path: root.quickAppsFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseContent(text())
        onLoadFailed: (error) => {
            console.warn("SBSQuickApps: failed to load", root.quickAppsFile, error)
            root.apps = []
        }
    }

    function parseContent(text) {
        try {
            const data = JSON.parse(text)
            apps = Array.isArray(data) ? data : []
        } catch (e) {
            console.warn("SBSQuickApps: bad JSON in", quickAppsFile, e)
            apps = []
        }
    }

    function launch(execCmd) {
        Quickshell.execDetached(["bash", scriptsDir + "/shortcuts-launch.sh", execCmd])
    }

    function remove(id) {
        Quickshell.execDetached(["bash", scriptsDir + "/shortcuts-remove.sh", id, root.quickAppsFile])
    }

    function openAddPicker() {
        if (atLimit) {
            Quickshell.execDetached(["notify-send", "Quick Apps", "Maximum 4 quick apps reached"])
            return
        }
        Quickshell.execDetached(["bash", scriptsDir + "/shortcuts-add.sh", root.quickAppsFile, String(maxApps), "Quick Apps"])
    }
}
