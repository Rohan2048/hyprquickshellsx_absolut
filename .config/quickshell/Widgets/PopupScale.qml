import QtQuick
import "../Services"

// Scales everything inside it (panel, text, icons, buttons) by the popup's scale from
// Settings > Popups > General. Put a popup's visual children in here and give the popup
// window implicitWidth / implicitHeight multiplied by the same scale:
//
//     PanelWindow {
//         readonly property real uiScale: PopupSettings.scaleOf("volume")
//         implicitWidth: 260 * uiScale
//         implicitHeight: 220 * uiScale
//         PopupScale { anchors.fill: parent; popupId: "volume"; GlassPanel { ... } }
//     }
//
// The children lay out at their normal ("base") size inside `inner`, which is then scaled
// from its top-left corner, so existing anchors / widths keep meaning what they meant.
Item {
    id: root

    property string popupId: ""
    readonly property real s: PopupSettings.scaleOf(root.popupId)
    default property alias data: inner.data

    Item {
        id: inner
        width: root.width / root.s
        height: root.height / root.s
        scale: root.s
        transformOrigin: Item.TopLeft
    }
}
