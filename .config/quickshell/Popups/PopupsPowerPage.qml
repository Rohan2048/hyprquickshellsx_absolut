import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Popups > Power & display: the Power menu (SUPER + Esc), Power schedule
// (SUPER + SHIFT + Esc) and Display toggle (ALT + S). Each one is drawn by rofi (default) or by
// the shell (Popups/ChoicePopup.qml), with its own scale for the Quickshell style.
Item {
    id: page

    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    readonly property var entries: [
        { id: "powermenu", label: "Power menu",     key: "Super + Esc",         what: "Shutdown, reboot, suspend, lock, logout." },
        { id: "schedule",  label: "Power schedule", key: "Super + Shift + Esc", what: "Pick an action, then a time (HH:MM) to run it." },
        { id: "hdmi",      label: "Display toggle", key: "Alt + S",             what: "Laptop only, external only, mirror or extend." }
    ]

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
            spacing: 14

            Hint { text: "Choose how each menu looks. Rofi is the default and always stays available. Quickshell draws the same menu in the shell theme, scaled by the slider, and closes when you click outside it. If the shell is not running when you press the key (for example after a crash), the keybind opens the rofi menu instead, whatever is chosen here. Nothing is monitored: the check happens when the key is pressed." }

            Repeater {
                model: page.entries
                delegate: ColumnLayout {
                    id: entry
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            text: entry.modelData.label
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            Layout.preferredWidth: 150
                        }
                        Text {
                            text: entry.modelData.key + "  -  " + entry.modelData.what
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                    Row {
                        spacing: 6
                        GlassButton {
                            text: "Rofi"
                            active: PopupSettings.powerStyle(entry.modelData.id) === "rofi"
                            onClicked: PopupSettings.setPowerStyle(entry.modelData.id, "rofi")
                        }
                        GlassButton {
                            text: "Quickshell"
                            active: PopupSettings.powerStyle(entry.modelData.id) === "quickshell"
                            onClicked: PopupSettings.setPowerStyle(entry.modelData.id, "quickshell")
                        }
                        GlassButton {
                            text: "Try Quickshell version"
                            onClicked: PopupSettings.choicePreview = entry.modelData.id
                        }
                    }
                    ScaleRow {
                        popupId: entry.modelData.id
                        label: "Scale (Quickshell)"
                    }
                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                GlassButton {
                    text: "Reset power & display"
                    onClicked: {
                        PopupSettings.resetSection("power")
                        for (let i = 0; i < PopupSettings.powerIds.length; i++)
                            PopupSettings.setScalePct(PopupSettings.powerIds[i], 100)
                    }
                }
            }
            Item { Layout.preferredHeight: 4 }
        }
    }
}
