import Quickshell
import "../Services"

LockQuickToggleTile {
    id: root
    signal devicesRequested()

    active: Bluetooth.radioOn
    label: "Bluetooth"
    sublabel: Bluetooth.radioOn ? Bluetooth.device : "Off"
    iconId: "lock-bluetooth"
    iconSource: "file://" + Quickshell.env("HOME") + "/.config/icons/bluetooth-icon.svg"

    onIconClicked: Bluetooth.toggleRadio()
    onLabelClicked: root.devicesRequested()
}
