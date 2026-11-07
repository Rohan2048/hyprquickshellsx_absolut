import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Popups > Applications: the app launcher (SUPER + R by default).
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
                            active: PopupSettings.appsStyle === "rofi"
                            onClicked: PopupSettings.put("apps", "style", null)
                        }
                        GlassButton {
                            text: "Quickshell"
                            active: PopupSettings.appsStyle === "quickshell"
                            onClicked: PopupSettings.put("apps", "style", "quickshell")
                        }
                    }
                    Hint { text: "What the App launcher keybind opens (Settings > Keybindings). Rofi: the rofi grid as before. Quickshell: the same layout drawn by the shell, following the shell theme. If the shell does not answer, the keybind falls back to rofi." }
                    GlassButton { text: "Try the Quickshell launcher"; onClicked: PopupSettings.appsOpen = true }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "View" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Row {
                        spacing: 6
                        GlassButton {
                            text: "Grid"
                            active: PopupSettings.appsView === "grid"
                            onClicked: PopupSettings.put("apps", "view", null)
                        }
                        GlassButton {
                            text: "List"
                            active: PopupSettings.appsView === "list"
                            onClicked: PopupSettings.put("apps", "view", "list")
                        }
                    }
                    Hint { text: "Grid shows icons with names, like the rofi theme. List shows one row per app with its description. The button at the top right of the launcher switches it too, and the choice is shared with the Shortcuts palette's app picker. (Quickshell style only; rofi keeps its own theme.)" }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "Applications" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        readonly property var raw: DesktopEntries.applications.values
                        text: {
                            let n = 0
                            for (let i = 0; i < raw.length; i++) if (!raw[i].noDisplay) n++
                                return n + " applications found"
                        }
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    Hint { text: "Found the standard desktop way: every applications folder of XDG_DATA_HOME and XDG_DATA_DIRS (system packages, ~/.local, /usr/local source installs, Flatpak and Snap exports). Apps marked hidden by their .desktop file are skipped. If a Flatpak or Snap app is missing, check that its share folder is in XDG_DATA_DIRS for your session." }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                GlassButton { text: "Reset applications"; onClicked: PopupSettings.resetSection("apps") }
            }

            Item { Layout.preferredHeight: 4 }
        }
    }
}
