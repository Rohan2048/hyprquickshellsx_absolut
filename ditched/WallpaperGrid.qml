import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".../Theme"

// Standalone glass-morphism wallpaper picker, launched fresh via keybind
// (same lifecycle as the rofi menu it replaces). Reads the manifest written
// by scripts/wallpaper-thumbs.sh, applies a selection via
// scripts/wallpaper-apply.sh, then quits.
PanelWindow {
    id: root

    WlrLayershell.namespace: "quickshell:wallpaper-grid"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusiveZone: 0
    color: "transparent"

    implicitWidth: 670
    implicitHeight: 410

    property string manifestPath: Quickshell.env("HOME") + "/.cache/wallpaper_manifest.json"
    property string thumbsScript: Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper-thumbs.sh"
    property string applyScript: Quickshell.env("HOME") + "/.config/quickshell/scripts/wallpaper-apply.sh"

    ListModel { id: wallpaperModel }

    Process {
        id: thumbProc
        command: ["bash", root.thumbsScript]
        onExited: manifestFile.reload()
    }

    FileView {
        id: manifestFile
        path: root.manifestPath
        onLoaded: {
            wallpaperModel.clear()
            try {
                const entries = JSON.parse(text())
                for (const e of entries) wallpaperModel.append(e)
            } catch (err) {
                console.warn("WallpaperGrid: failed to parse manifest:", err)
            }
        }
        onLoadFailed: console.warn("WallpaperGrid: manifest not found yet at", root.manifestPath)
    }

    Process {
        id: applyProc
        onExited: Qt.quit()
    }

    function applyWallpaper(path) {
        applyProc.command = ["bash", root.applyScript, path]
        applyProc.running = true
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: Qt.rgba(10 / 255, 10 / 255, 10 / 255, 0.45)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.15)

        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Rectangle {
                width: parent.width
                height: 32
                radius: Theme.radiusSm
                color: Qt.rgba(1, 1, 1, 0.06)

                Text {
                    anchors.centerIn: parent
                    text: "Choose Wallpaper"
                    color: Qt.rgba(1, 1, 1, 0.7)
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }

            GridView {
                id: grid
                width: parent.width
                height: parent.height - 40
                cellWidth: width / 3
                cellHeight: cellWidth + 24
                model: wallpaperModel
                clip: true

                delegate: Item {
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        id: cell
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: Theme.radiusSm
                        color: mouseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                        border.width: mouseArea.containsMouse ? 1 : 0
                        border.color: Qt.rgba(1, 1, 1, 0.25)

                        Column {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4

                            Image {
                                width: parent.width
                                height: parent.width
                                source: "file://" + thumb
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                            }

                            Text {
                                width: parent.width
                                text: name
                                color: Qt.rgba(1, 1, 1, 0.85)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeXs
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.applyWallpaper(path)
                        }
                    }
                }
            }
        }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Qt.quit()
        Component.onCompleted: forceActiveFocus()
    }

    Component.onCompleted: thumbProc.running = true
}
