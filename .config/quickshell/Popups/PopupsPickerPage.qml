import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Popups > Wallpaper picker / Animation scale: same options as the power menus.
// Rofi (default, always available) or Quickshell style, with its own scale for the Quickshell
// style. If the shell is not answering when the key is pressed, the keybind falls back to rofi
// (scripts/qs-pick.sh), decided at keypress time; nothing is monitored.
Item {
    id: page

    property string pid: "wallpaper"        // "wallpaper" | "animscale"
    readonly property bool isWall: page.pid === "wallpaper"
    property bool browsing: false

    // Esc steps out of the folder browser first
    function handleKey(event) {
        if (page.browsing && event.key === Qt.Key_Escape) { page.browsing = false; return true }
        return false
    }

    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    Loader {
        anchors.fill: parent
        active: page.browsing
        z: 2
        sourceComponent: FolderBrowser {
            start: PopupSettings.wallpaperDir
            onChosen: (p) => { PopupSettings.setWallpaperDir(p); dirFieldSync(); page.browsing = false }
            onCancelled: page.browsing = false
        }
    }
    function dirFieldSync() { dirField.text = PopupSettings.wallpaperDir }

    Flickable {
        id: flick
        visible: !page.browsing
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

            Text {
                text: page.isWall ? "Wallpaper picker" : "Animation scale"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
            }
            Hint {
                text: page.isWall
                ? "SUPER + SHIFT + W. Rofi shows the thumbnails in its own grid (default). Quickshell shows the same wallpapers as a grid in the shell theme, scaled by the slider, and closes when you click outside it. Picking a wallpaper applies it the same way in both."
                : "ALT + R. Pick how fast animations run (0.75x to 2x, or Auto from the screen's refresh rate). Rofi shows a list (default); Quickshell shows the same list in the shell theme, scaled by the slider."
            }
            Hint { text: "If the shell is not running when you press the key (for example after a crash), the keybind opens the rofi version instead, whatever is chosen here. Nothing is monitored: the check happens when the key is pressed." }

            Row {
                spacing: 6
                GlassButton {
                    text: "Rofi"
                    active: PopupSettings.powerStyle(page.pid) === "rofi"
                    onClicked: PopupSettings.setPowerStyle(page.pid, "rofi")
                }
                GlassButton {
                    text: "Quickshell"
                    active: PopupSettings.powerStyle(page.pid) === "quickshell"
                    onClicked: PopupSettings.setPowerStyle(page.pid, "quickshell")
                }
                GlassButton {
                    text: "Try Quickshell version"
                    onClicked: page.isWall ? PopupSettings.wallpaperRequested() : (PopupSettings.choicePreview = "animscale")
                }
            }

            ScaleRow {
                popupId: page.pid
                label: "Scale (Quickshell)"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: page.isWall
                Text {
                    text: "Folder"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    Layout.preferredWidth: 150
                }
                TextField {
                    id: dirField
                    Layout.fillWidth: true
                    implicitHeight: 32
                    selectByMouse: true
                    text: PopupSettings.wallpaperDir
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    background: Rectangle {
                        radius: Theme.radiusSm
                        color: "transparent"
                        border.width: 1
                        border.color: dirField.activeFocus ? Theme.accentActive : Theme.borderMuted
                    }
                    onEditingFinished: PopupSettings.setWallpaperDir(text)
                }
                GlassButton { text: "Browse"; onClicked: page.browsing = true }
                GlassButton { text: "Default"; onClicked: { PopupSettings.setWallpaperDir(""); dirField.text = PopupSettings.wallpaperDir } }
            }
            Hint {
                visible: page.isWall
                text: "Browse opens a folder picker where you click Choose this directory. This is the folder the Quickshell picker lists. The rofi picker uses the folder set inside wallpaper_switcher.sh (~/Downloads/WALLPAPERS by default)."
            }

            RowLayout {
                Layout.fillWidth: true
                GlassButton {
                    text: "Reset"
                    onClicked: { PopupSettings.setPowerStyle(page.pid, "rofi"); PopupSettings.setScalePct(page.pid, 100); if (page.isWall) PopupSettings.setWallpaperDir("") }
                }
            }
            Item { Layout.preferredHeight: 4 }
        }
    }
}
