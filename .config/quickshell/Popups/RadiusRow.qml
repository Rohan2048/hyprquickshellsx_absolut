import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// One "label ---slider--- 12 px [Reset]" row for a popup's corner radius (PopupSettings.radii).
RowLayout {
    id: rr

    property string popupId: ""
    property string label: ""
    property real labelWidth: 150

    Layout.fillWidth: true
    spacing: 10

    Text {
        text: rr.label
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Layout.preferredWidth: rr.labelWidth
        elide: Text.ElideRight
    }
    GlassSlider {
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        min: 0
        max: PopupSettings.maxRadius
        value: PopupSettings.radiusOf(rr.popupId)
        onValueCommitted: (v) => PopupSettings.setRadius(rr.popupId, v)
    }
    Text {
        text: PopupSettings.radiusOf(rr.popupId) + " px"
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Layout.preferredWidth: 50
        horizontalAlignment: Text.AlignRight
    }
    GlassButton {
        text: "Reset"
        implicitHeight: 26
        opacity: PopupSettings.radiusOf(rr.popupId) !== PopupSettings.defaultRadius(rr.popupId) ? 1 : 0
        disabled: PopupSettings.radiusOf(rr.popupId) === PopupSettings.defaultRadius(rr.popupId)
        onClicked: PopupSettings.setRadius(rr.popupId, PopupSettings.defaultRadius(rr.popupId))
    }
}
