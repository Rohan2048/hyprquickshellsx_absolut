import QtQuick
import Quickshell.Hyprland
import "../../Theme"
import "../../Services"

// Workspace switcher for a bar: 1 2 3 4 5 6 7 8 9 0 (0 = workspace 10, like the keybinds).
// The current workspace is highlighted, workspaces with windows are brighter than empty ones.
// Click = go to that workspace.
Item {
    id: root

    property var cfg: BarSettings
    readonly property bool vertical: cfg.vertical
    readonly property int cell: 22
    readonly property int gap: 2
    readonly property int count: 10

    readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
    function occupied(id) {
        const l = Hyprland.workspaces.values
        for (let i = 0; i < l.length; i++) if (l[i].id === id) return true
            return false
    }

    readonly property real mainLen: count * cell + (count - 1) * gap + 10
    implicitWidth: vertical ? cfg.thickness : mainLen
    implicitHeight: vertical ? mainLen : cfg.thickness
    width: implicitWidth
    height: implicitHeight

    Grid {
        anchors.centerIn: parent
        columns: root.vertical ? 1 : root.count
        spacing: root.gap

        Repeater {
            model: root.count
            delegate: Rectangle {
                id: cellItem
                required property int index
                readonly property int wsId: index + 1
                readonly property bool current: root.focusedId === wsId
                width: root.cell; height: root.cell
                radius: Theme.radiusSm
                color: current ? Theme.accentActive : (area.containsMouse ? Theme.hoverBg : "transparent")
                border.width: current ? 0 : 1
                border.color: root.occupied(wsId) ? Theme.borderMuted : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: cellItem.wsId % 10
                    color: Theme.foreground
                    opacity: cellItem.current || root.occupied(cellItem.wsId) ? 1 : 0.55
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    font.bold: cellItem.current
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + cellItem.wsId + " })")
                }
            }
        }
    }
}
