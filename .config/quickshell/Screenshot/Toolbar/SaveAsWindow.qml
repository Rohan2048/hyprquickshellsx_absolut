pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../Theme"

PanelWindow {
    id: root

    required property var screenshotWindow

    property bool active: false
    property string currentPath: Quickshell.env("HOME") + "/Pictures/Screenshots"
    property string sourcePath: "" // temp composite file to copy from
    property var entries: []

    signal saveRequested(string destDir, string filename)

    screen: screenshotWindow ? screenshotWindow.targetScreen : null
    visible: active && screen !== null
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:screenshot-saveas"
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }

    function open(sourceComposite, defaultName) {
        root.sourcePath = sourceComposite;
        root.currentPath = Quickshell.env("HOME") + "/Pictures/Screenshots";
        filenameInput.text = defaultName;
        root.active = true;
        dirLister.list(root.currentPath);
        if (root.screenshotWindow)
            root.screenshotWindow.WlrLayershell.keyboardFocus = WlrKeyboardFocus.None;
        filenameInput.forceActiveFocus();
        filenameInput.selectAll();
    }

    function close() {
        root.active = false;
        if (root.screenshotWindow) {
            root.screenshotWindow.WlrLayershell.keyboardFocus = WlrKeyboardFocus.Exclusive;
            root.screenshotWindow.restoreFocus();
        }
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
            "mkdir -p '" + escaped + "' && find '" + escaped + "' -maxdepth 1 -mindepth 1 -type d -printf '%f\\n' | sort"];
            dirLister.running = true;
        }
        stdout: StdioCollector {
            id: dirListerOut
            onStreamFinished: {
                const lines = dirListerOut.text.split("\n").filter(l => l.length > 0);
                root.entries = lines.map(name => ({ isDir: true, name: name }));
            }
        }
    }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    Rectangle {
        anchors.centerIn: parent
        width: 380
        height: 460
        radius: Theme.radiusMd
        color: Qt.rgba(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, 0.75)
        border.width: 1
        border.color: Theme.borderMuted

        MouseArea { anchors.fill: parent; onClicked: {} }

        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

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
                height: parent.height - 190
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
                        text: "▸  " + entryDelegate.modelData.name
                        color: Theme.color3
                        font.pixelSize: Theme.fs(13)
                        font.bold: true
                    }

                    MouseArea {
                        id: entryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.currentPath = root.currentPath + "/" + entryDelegate.modelData.name;
                            dirLister.list(root.currentPath);
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.borderMuted }

            Rectangle {
                width: parent.width
                height: 36
                radius: Theme.radiusMd
                color: Theme.hoverBgStrong
                border.width: 1
                border.color: Theme.borderMuted

                TextInput {
                    id: filenameInput
                    anchors.fill: parent
                    anchors.margins: 8
                    color: Theme.foreground
                    font.pixelSize: Theme.fs(13)
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    clip: true
                    Keys.onReturnPressed: saveBtn.clicked()
                }
            }

            Row {
                width: parent.width
                spacing: 8

                ToolButton {
                    id: saveBtn
                    label: "Save"
                    onClicked: {
                        if (filenameInput.text.trim().length === 0) return;
                        root.saveRequested(root.currentPath, filenameInput.text.trim());
                        root.close();
                    }
                }
                ToolButton {
                    label: "Cancel"
                    onClicked: root.close()
                }
            }
        }
    }
}
