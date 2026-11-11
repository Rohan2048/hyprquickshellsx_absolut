import QtQuick
import Quickshell
import "../Services"

// One per screen: creates a Bar window for every bar of the active preset (or the single
// classic bar). Bars are keyed by id, so editing a preset does not recreate their windows.
Item {
    id: host
    required property var modelData          // the screen (from shell.qml's Variants)
    readonly property var screenRef: modelData

    Variants {
        model: BarPresets.barIds
        Bar {
            id: barInst
            required property var modelData
            screenRef: host.screenRef
            cfg: BarConfig { cid: barInst.modelData }
        }
    }
}
