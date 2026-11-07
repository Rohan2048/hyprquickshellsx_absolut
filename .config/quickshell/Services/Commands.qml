pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell"
    readonly property string dataFile: configDir + "/state/commands.json"
    readonly property string scriptDir: configDir + "/scripts"

    property var groups: []
    property string expandedGroup: ""

    function toggleGroup(group) {
        expandedGroup = expandedGroup === group ? "" : group
    }

    function launch(cmd, terminal) {
        launchProc.command = ["bash", scriptDir + "/commands-launch.sh", cmd, terminal ? "true" : "false"]
        launchProc.running = true
    }

    function remove(group, cmd, terminal) {
        removeProc.command = ["bash", scriptDir + "/commands-remove.sh", group, cmd, terminal ? "true" : "false"]
        removeProc.running = true
    }

    // The + button. Style comes from Settings > Popups > Commands palette.
    property bool addDialogOpen: false
    function addNew() {
        if (PopupSettings.commandsStyle === "quickshell") root.addDialogOpen = true
        else addProc.running = true
    }

    readonly property var groupNames: root.groups.map(function (g) { return g.group })

    // Same result as scripts/commands-add.sh, written straight to commands.json
    // (a command already in the group is not added twice).
    function addEntry(group, cmd, terminal) {
        group = String(group).trim()
        cmd = String(cmd).trim()
        if (group === "" || cmd === "") return false
        const all = JSON.parse(JSON.stringify(root.groups))
        const entry = { cmd: cmd, terminal: !!terminal }
        let g = null
        for (let i = 0; i < all.length; i++) if (all[i].group === group) { g = all[i]; break }
        if (g === null) { all.push({ group: group, commands: [entry] }) }
        else if (!g.commands.some(function (c) { return c.cmd === entry.cmd && !!c.terminal === entry.terminal })) {
            g.commands.push(entry)
        }
        root.groups = all
        file.setText(JSON.stringify(all, null, 2))
        Quickshell.execDetached(["notify-send", "Commands", "Added to group: " + group])
        return true
    }

    FileView {
        id: file
        path: root.dataFile
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.groups = JSON.parse(text())
            } catch (e) {
                console.warn("Commands: failed to parse commands.json", e)
                root.groups = []
            }
        }
    }

    Process { id: launchProc }
    Process { id: removeProc }   // file watcher picks up the edit automatically
    Process {
        id: addProc
        command: ["bash", root.scriptDir + "/commands-add.sh"]
        // also picked up automatically once the script writes the file
    }
}
