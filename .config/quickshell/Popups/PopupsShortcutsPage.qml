import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Popups > Shortcuts palette: placement, scale, what opens it (keybind / hover
// zone / both) and the style of the + button's app picker.
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

    // dock length in virtual screen pixels (about 52 per shortcut + the + button + padding)
    readonly property real dockLen: Math.max(110, 16 + 52 * Math.min(10, Shortcuts.shortcuts.length + (Shortcuts.atLimit ? 0 : 1)) - 8)
    // rows along the top / bottom edge, columns on the left / right edge
    readonly property bool horizontal: PopupSettings.shortcutsPlacement.split("-")[0] !== "center"

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
                        value: PopupSettings.shortcutsPlacement
                        options: PopupSettings.commandsPlacements
                        cardW: (page.horizontal ? page.dockLen : 60) * PopupSettings.scaleOf("shortcuts")
                        cardH: (page.horizontal ? 60 : page.dockLen) * PopupSettings.scaleOf("shortcuts")
                        gap: PopupSettings.shortcutsPlacement === "center-left" || PopupSettings.shortcutsPlacement === "center-right" ? 0 : 12
                        onPicked: (v) => PopupSettings.put("shortcuts", "placement", v === "center-left" ? null : v)
                    }
                    Hint { text: "Where the shortcuts dock sits. Middle left and middle right give a vertical column; anything at the top or bottom gives a horizontal row. Middle left is the original spot, flush with the screen edge; the others float with a small gap." }
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
                    ScaleRow { popupId: "shortcuts"; label: ""; labelWidth: 0 }
                    Hint { text: "Scales the whole dock: icons, padding and tooltips. The same slider as Popups > General." }
                }
            }

            // ---- trigger ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "Trigger" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Row {
                        spacing: 6
                        GlassButton {
                            text: "Keybind"
                            active: PopupSettings.shortcutsTrigger === "keybind"
                            onClicked: PopupSettings.put("shortcuts", "trigger", null)
                        }
                        GlassButton {
                            text: "Hover zone"
                            active: PopupSettings.shortcutsTrigger === "hover"
                            onClicked: PopupSettings.put("shortcuts", "trigger", "hover")
                        }
                        GlassButton {
                            text: "Both"
                            active: PopupSettings.shortcutsTrigger === "both"
                            onClicked: PopupSettings.put("shortcuts", "trigger", "both")
                        }
                    }
                    Hint { text: "Keybind: the Shortcuts keybind (Settings > Keybindings) opens it. Hover zone: a thin invisible strip on the screen edge next to the dock, as long as the dock, reveals it when the pointer touches it, and it hides again when the pointer leaves; the keybind is ignored. Both: either opens it. A dock opened by the keybind stays until you toggle it, launch something or click away; only a hover-opened dock hides by itself." }
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
                            active: PopupSettings.shortcutsStyle === "rofi"
                            onClicked: PopupSettings.put("shortcuts", "style", null)
                        }
                        GlassButton {
                            text: "Quickshell"
                            active: PopupSettings.shortcutsStyle === "quickshell"
                            onClicked: PopupSettings.put("shortcuts", "style", "quickshell")
                        }
                    }
                    Hint { text: "What the + button opens to pick an app. Rofi: the rofi list. Quickshell: the in-shell picker (grid by default, a button at the top right switches to a list with descriptions), listing apps the standard desktop way and following the shell theme." }
                    GlassButton { text: "Try the add menu"; onClicked: Shortcuts.openAddPicker() }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                GlassButton { text: "Reset shortcuts palette"; onClicked: { PopupSettings.resetSection("shortcuts"); PopupSettings.setScalePct("shortcuts", 100) } }
            }

            Item { Layout.preferredHeight: 4 }
        }
    }
}
