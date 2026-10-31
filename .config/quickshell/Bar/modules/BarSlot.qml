import QtQuick
import "../../Services"

// Wraps one bar item and positions it according to BarSettings.order.
// `owner` is the bar window (provides slotOffset(), vertical, baseThickness).
// The slot is always "visible": a collapsed item has zero size, so there is
// nothing to draw, and nothing gets created/destroyed when it expands.
Item {
    id: slot

    required property var owner
    property string slotId: ""
    default property alias content: holder.data

        readonly property Item child: holder.children.length > 0 ? holder.children[0] : null

        // only modules that are in this bar's list take part; the rest are collapsed and hidden
        readonly property bool inBar: owner.cfg.order.indexOf(slotId) >= 0
        visible: inBar

        implicitWidth: child ? child.width : 0
        implicitHeight: child ? child.height : 0

        // Position follows live widths with NO easing (so reveal animations of
        // neighbours stay in sync). Easing only runs briefly after a reorder.
        property bool reordering: false
        Connections {
            target: slot.owner.cfg
            function onOrderChanged() { slot.reordering = true; reorderTimer.restart() }
        }
        Timer { id: reorderTimer; interval: 300; onTriggered: slot.reordering = false }
        property bool ready: false
        Timer { interval: 200; running: true; onTriggered: slot.ready = true }
        readonly property bool animated: ready && reordering

        readonly property real _main: owner.slotOffset(slotId)
        x: owner.vertical ? Math.round((owner.baseThickness - width) / 2) : _main
        y: owner.vertical ? _main : Math.round((owner.baseThickness - height) / 2)

        Behavior on x { enabled: slot.animated; NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
        Behavior on y { enabled: slot.animated; NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }

        Item { id: holder }
}
