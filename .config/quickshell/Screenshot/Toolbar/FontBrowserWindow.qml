pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../Services"
import "../../Theme"

PanelWindow {
    id: root

    required property var screenshotWindow

    property bool active: false
    property string currentPath: Quickshell.env("HOME")
    property var entries: []

    signal fontChosen(string path)

    screen: screenshotWindow ? screenshotWindow.targetScreen : null
    visible: active && screen !== null
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:screenshot-fontbrowser"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }

    function open() {
        if (root.screenshotWindow)
            root.screenshotWindow.WlrLayershell.keyboardFocus = WlrKeyboardFocus.None;
        root.currentPath = Quickshell.env("HOME");
        root.active = true;
        dirLister.list(root.currentPath);
    }

    function close() {
        root.active = false;
        if (root.screenshotWindow) {
            root.screenshotWindow.WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive;
            root.screenshotWindow.restoreFocus();
        }
    }

    function removeFont(family) {
        const wasActive = ScreenshotSession.annotationFontFamily === family;
        ScreenshotSession.removeCustomFont(family);
        if (wasActive) ScreenshotSession.setAnnotationFontFamily("sans-serif");
    }

    Item {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) {
                root.close();
                event.accepted = true;
            }
        }
    }

    Process {
        id: dirLister
        function list(path) {
            const escaped = path.replace(/'/g, "'\\''");
            dirLister.command = ["bash", "-c",
            "find '" + escaped + "' -maxdepth 1 -mindepth 1 " +
            "\\( -type d -o -iname '*.ttf' -o -iname '*.otf' \\) " +
            "-printf '%y\\t%f\\n' | sort"];
            dirLister.running = true;
        }
        stdout: StdioCollector {
            id: dirListerOut
            onStreamFinished: {
                const lines = dirListerOut.text.split("\n").filter(l => l.length > 0);
                root.entries = lines.map(l => {
                    const parts = l.split("\t");
                    return { isDir: parts[0] === "d", name: parts[1] || "" };
                });
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.close()
    }

    Rectangle {
        anchors.centerIn: parent
        width: 380
        height: 500
        radius: Theme.radiusMd
        color: Qt.rgba(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, 0.75)
        border.width: 1
        border.color: Theme.borderMuted

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            Column {
                id: customFontsSection
                width: parent.width
                spacing: 4
                visible: ScreenshotSession.customFonts.length > 0

                Text {
                    text: "Installed Fonts (click × to remove)"
                    color: Theme.foreground
                    opacity: 0.6
                    font.pixelSize: Theme.fs(11)
                }

                Rectangle {
                    width: parent.width
                    height: 44
                    color: "transparent"
                    clip: true

                    Flickable {
                        anchors.fill: parent
                        contentWidth: chipFlow.width
                        contentHeight: height
                        clip: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsBehavior: Flickable.StopAtBounds

                        Flow {
                            id: chipFlow
                            height: parent.height
                            spacing: 6

                            Repeater {
                                model: ScreenshotSession.customFonts
                                delegate: Rectangle {
                                    id: chip
                                    required property var modelData
                                    height: 26
                                    radius: Theme.radiusMd
                                    color: Theme.hoverBgStrong
                                    width: chipRow.width + 16

                                    Row {
                                        id: chipRow
                                        anchors.centerIn: parent
                                        spacing: 6

                                        Text {
                                            text: chip.modelData.family
                                            color: Theme.foreground
                                            font.pixelSize: Theme.fs(12)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: "×"
                                            color: "#cc3333"
                                            font.pixelSize: Theme.fs(13)
                                            font.bold: true
                                            anchors.verticalCenter: parent.verticalCenter

                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -6
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.removeFont(chip.modelData.family)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.borderMuted }
            }

            Row {
                width: parent.width
                spacing: 8

                ToolButton {
                    label: "↑ Up"
                    onClicked: {
                        const parts = root.currentPath.split("/");
                        if (parts.length > 2) {
                            parts.pop();
                            root.currentPath = parts.join("/");
                            dirLister.list(root.currentPath);
                        }
                    }
                }

                Text {
                    text: root.currentPath
                    color: Theme.foreground
                    elide: Text.ElideMiddle
                    width: parent.width - 90
                    font.pixelSize: Theme.fs(12)
                    verticalAlignment: Text.AlignVCenter
                    height: 36
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.borderMuted }

            ListView {
                width: parent.width
                height: parent.height - 130 - (customFontsSection.visible ? customFontsSection.height + 8 : 0)
                clip: true
                model: root.entries
                delegate: Rectangle {
                    id: entryDelegate
                    required property var modelData

                    width: ListView.view.width
                    height: 32
                    radius: Theme.radiusMd
                    color: entryMouse.containsMouse ? Theme.hoverBgStrong : "transparent"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        text: (entryDelegate.modelData.isDir ? "▸  " : "     ") + entryDelegate.modelData.name
                        color: entryDelegate.modelData.isDir ? Theme.color3 : Theme.foreground
                        font.pixelSize: Theme.fs(13)
                        font.bold: entryDelegate.modelData.isDir
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const full = root.currentPath + "/" + entryDelegate.modelData.name;
                            if (entryDelegate.modelData.isDir) {
                                root.currentPath = full;
                                dirLister.list(full);
                            } else {
                                root.fontChosen(full);
                                root.close();
                            }
                        }
                    }
                }
            }

            ToolButton {
                label: "Cancel"
                onClicked: root.close()
            }
        }
    }
}
