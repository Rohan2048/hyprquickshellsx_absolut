import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Popups > General: scale each popup on its own.
// A popup is scaled as a whole: panel, text, icons and every button inside it.
Item {
    id: page

    component SectionLabel: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        Layout.fillWidth: true
        Layout.topMargin: 2
    }
    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: -14; anchors.rightMargin: -14   // horizontal gutter only (hover-scaled buttons); top/bottom clip at the real edge
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: 14; y: 4
            width: flick.width - 28
            spacing: 12

            Hint { text: "Scale each popup on its own. A popup is scaled as a whole: its panel, text, icons and every button inside it. Bar popups still open next to their bar icon; the palettes keep their own placement. Changes apply immediately: open the popup to see it." }

            SectionLabel { text: "Bar popups" }
            Repeater {
                model: PopupSettings.popups.filter(function (p) { return p.group === "bar" })
                delegate: ScaleRow {
                    required property var modelData
                    popupId: modelData.id
                    label: modelData.label
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

            SectionLabel { text: "Palettes" }
            Repeater {
                model: PopupSettings.popups.filter(function (p) { return p.group === "palette" })
                delegate: ScaleRow {
                    required property var modelData
                    popupId: modelData.id
                    label: modelData.label
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

            SectionLabel { text: "Power & display menus (Quickshell style)" }
            Repeater {
                model: PopupSettings.popups.filter(function (p) { return p.group === "power" })
                delegate: ScaleRow {
                    required property var modelData
                    popupId: modelData.id
                    label: modelData.label
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

            SectionLabel { text: "Pickers (Quickshell style)" }
            Repeater {
                model: PopupSettings.popups.filter(function (p) { return p.group === "pickers" })
                delegate: ScaleRow {
                    required property var modelData
                    popupId: modelData.id
                    label: modelData.label
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

            SectionLabel { text: "This Settings window" }
            Hint { text: "Scales the Settings window itself. It resizes about half a second after you let go of the slider, stays open while it does, and never grows past your screen." }
            Repeater {
                model: PopupSettings.popups.filter(function (p) { return p.group === "settings" })
                delegate: ScaleRow {
                    required property var modelData
                    popupId: modelData.id
                    label: modelData.label
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                GlassButton { text: "Reset all scales"; onClicked: PopupSettings.resetScales() }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

            SectionLabel { text: "Corner radius" }
            Hint { text: "How round the corners of each popup are, in pixels. 0 = square. Open the popup to see it." }
            Repeater {
                model: PopupSettings.radiusItems
                delegate: RadiusRow {
                    required property var modelData
                    popupId: modelData.id
                    label: modelData.label
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                GlassButton { text: "Reset all corner radii"; onClicked: PopupSettings.resetRadii() }
            }

            Item { Layout.preferredHeight: 4 }
        }
    }
}
