import QtQuick
import Quickshell

// A bar button that runs one action (open the launcher, lock, settings, ...).
// One file for all of them: `action` picks the entry of `defs` below.
// To add your own: add an entry here, add its id to BarPresets.moduleIds / moduleNames and
// give it a BarSlot in Bar.qml (copy the "launcher" one).
//   label  text shown (text-only button) when there is no icon
//   icon   file in ~/.config/icons (optional)
//   cmd    command to run
ControlIcon {
    id: root

    property string action: ""
    readonly property string home: Quickshell.env("HOME")
    readonly property var defs: ({
        "launcher":  { label: "Apps",     cmd: ["bash", root.home + "/.config/quickshell/scripts/launcher.sh"] },
        "settings":  { label: "",         icon: "settings.svg", cmd: ["qs", "ipc", "call", "settings", "toggle"] },
        "lock":      { label: "Lock",     cmd: ["qs", "ipc", "call", "lock", "lock"] },
        "commands":  { label: "Commands", cmd: ["qs", "ipc", "call", "commands", "toggle"] },
        "shortcuts": { label: "Shortcuts", cmd: ["qs", "ipc", "call", "shortcuts", "toggle"] },
        "overview":  { label: "Overview", cmd: ["qs", "ipc", "call", "workspaceOverview", "toggle"] },
        "display":   { label: "Display",  cmd: ["bash", root.home + "/.config/hypr/hdmi.sh"] },
        "schedule":  { label: "Schedule", cmd: ["bash", root.home + "/.config/hypr/schedule_action.sh"] }
    })
    readonly property var def: root.defs[root.action] || ({ label: root.action, cmd: [] })

    text: root.def.label
    iconSource: root.def.icon ? "file://" + root.home + "/.config/icons/" + root.def.icon : ""

    onActivated: { if (root.def.cmd.length > 0) Quickshell.execDetached(root.def.cmd) }
}
