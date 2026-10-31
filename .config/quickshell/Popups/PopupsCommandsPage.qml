import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Popups > Commands palette: where it opens, how big it is, and which style
// the + button's "add command" flow uses.
Item {
    id: page

    component SectionLabel: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        Layout.preferredWidth: 130
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 6
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
            spacing: 16

            // ---- placement ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "Placement" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    PlacementPicker {
                        Layout.alignment: Qt.AlignLeft
                        value: PopupSettings.commandsPlacement
                        options: PopupSettings.commandsPlacements
                        cardW: 220 * PopupSettings.scaleOf("commands")
                        cardH: 280 * PopupSettings.scaleOf("commands")
                        gap: PopupSettings.commandsPlacement === "center-right" ? 0 : 12
                        onPicked: (v) => PopupSettings.put("commands", "placement", v === "center-right" ? null : v)
                    }
                    Hint { text: "Where the Commands palette opens on the screen. Middle right is the original spot." }
                }
            }

            // ---- scale ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "Scale" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    ScaleRow { popupId: "commands"; label: ""; labelWidth: 0 }
                    Hint { text: "Scales the whole palette: panel, text and buttons. The same slider as Popups > General." }
                }
            }

            // ---- style of the + (add) flow ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "Add style" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Row {
                        spacing: 6
                        GlassButton {
                            text: "Rofi"
                            active: PopupSettings.commandsStyle === "rofi"
                            onClicked: PopupSettings.put("commands", "style", null)
                        }
                        GlassButton {
                            text: "Quickshell"
                            active: PopupSettings.commandsStyle === "quickshell"
                            onClicked: PopupSettings.put("commands", "style", "quickshell")
                        }
                    }
                    Hint { text: "What the + button opens. Rofi: the three rofi menus (group, command, how to launch) with your rofi theme. Quickshell: one in-shell dialog that follows the shell theme (blur, opaque or a custom theme), so it matches the palette." }
                    GlassButton { text: "Try the add menu"; onClicked: Commands.addNew() }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                GlassButton { text: "Reset commands palette"; onClicked: { PopupSettings.resetSection("commands"); PopupSettings.setScalePct("commands", 100) } }
            }

            Item { Layout.preferredHeight: 4 }
        }
    }
}
