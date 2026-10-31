import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Popups > Clipboard history: what the clipboard history keybind (SUPER + P by default) opens.
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

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "Style" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Row {
                        spacing: 6
                        GlassButton {
                            text: "Rofi"
                            active: PopupSettings.clipboardStyle === "rofi"
                            onClicked: PopupSettings.put("clipboard", "style", null)
                        }
                        GlassButton {
                            text: "Quickshell"
                            active: PopupSettings.clipboardStyle === "quickshell"
                            onClicked: PopupSettings.put("clipboard", "style", "quickshell")
                        }
                    }
                    Hint { text: "What the Clipboard history keybind opens (Settings > Keybindings). Rofi: the rofi list as before. Quickshell: the same list drawn by the shell, following the shell theme and the border settings. Both read the history kept by cliphist. If the shell does not answer, the keybind falls back to rofi." }
                    GlassButton { text: "Try the Quickshell clipboard history"; onClicked: PopupSettings.clipboardOpen = true }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "Using it" }
                Hint { text: "Type to search. Up / Down (or Tab) to move, Enter copies the entry and closes, Esc closes. Ctrl + Delete, or the x on a row, removes one entry. Images are listed with their size." }
            }

            RowLayout {
                Layout.fillWidth: true
                GlassButton { text: "Reset clipboard history"; onClicked: PopupSettings.resetSection("clipboard") }
            }

            Item { Layout.preferredHeight: 4 }
        }
    }
}
