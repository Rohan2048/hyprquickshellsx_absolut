import Quickshell
import Quickshell.Io

LockQuickToggleTile {
    id: root
    property bool airplaneMode: false

    active: root.airplaneMode
    label: "Airplane"
    labelIsButton: false
    sublabel: root.airplaneMode ? "On" : "Off"
    iconId: "lock-airplane"
    iconSource: "file://" + Quickshell.env("HOME") + "/.config/icons/airplane.svg"

    onIconClicked: root.toggle()
    onLabelClicked: root.toggle()

    function toggle() {
        root.airplaneMode = !root.airplaneMode
        proc.command = ["bash", "-c", root.airplaneMode ? "rfkill block all" : "rfkill unblock all"]
        proc.running = true
    }

    Process { id: proc }
}
