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

    function addNew() {
        addProc.running = true
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
