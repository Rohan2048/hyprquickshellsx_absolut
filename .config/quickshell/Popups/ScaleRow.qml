import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// One "label ---slider--- 100% [Reset]" row for a popup's scale (PopupSettings.scales).
RowLayout {
    id: sr

    property string popupId: ""
    property string label: ""
    property real labelWidth: 150

    Layout.fillWidth: true
    spacing: 10

    Text {
        text: sr.label
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Layout.preferredWidth: sr.labelWidth
        elide: Text.ElideRight
    }
    GlassSlider {
        id: slider
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        min: PopupSettings.minPct
        max: PopupSettings.maxPct
        value: PopupSettings.scalePct(sr.popupId)
        onValueCommitted: (v) => PopupSettings.setScalePct(sr.popupId, v)
        // lets the Settings window wait until the slider is released before it resizes
        onPressedChanged: PopupSettings.scaleDragging = slider.pressed
        Component.onDestruction: if (slider.pressed) PopupSettings.scaleDragging = false
    }
    Text {
        text: PopupSettings.scalePct(sr.popupId) + "%"
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        Layout.preferredWidth: 44
        horizontalAlignment: Text.AlignRight
    }
    GlassButton {
        text: "Reset"
        implicitHeight: 26
        opacity: PopupSettings.scalePct(sr.popupId) !== 100 ? 1 : 0
        disabled: PopupSettings.scalePct(sr.popupId) === 100
        onClicked: PopupSettings.setScalePct(sr.popupId, 100)
    }
}
