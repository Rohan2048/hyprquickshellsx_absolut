pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../Services"
import "../Theme"
import "../Popups"
import "../Widgets"
QtObject {
    id: root
    property var apps: []
    property bool loading: false

    readonly property string scriptPath: Quickshell.shellDir + "/scripts/list-apps.py"

    function refresh(force) {
        root.loading = true
        proc.command = force ? ["python3", root.scriptPath, "--force"] : ["python3", root.scriptPath]
        proc.running = true
    }

    property Process proc: Process {
        stdout: SplitParser {
            onRead: (line) => {
                try {
                    root.apps = JSON.parse(line)
                } catch (e) {
                    console.warn("AppList: failed to parse app list JSON", e)
                }
                root.loading = false
            }
        }
        stderr: SplitParser {
            onRead: (line) => console.warn("AppList stderr:", line)
        }
        onExited: (exitCode, exitStatus) => {
            console.warn("AppList: process exited", exitCode, exitStatus)
        }

    }

    Component.onCompleted: {
        console.log("AppList scriptPath:", root.scriptPath)
        refresh(false)
    }
}
