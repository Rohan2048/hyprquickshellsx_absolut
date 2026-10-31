import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// Bottom-center Applications grid + search, reading icons/.app_cache.tsv.
Rectangle {
    id: root
    property bool expanded: false
    z: 5 // stack above SBSShell's background click-away MouseArea
    readonly property string configDir: Quickshell.env("HOME") + "/.config/quickshell"
    readonly property string iconsDir: configDir + "/icons"
    property var _entries: []
    property string query: ""
    readonly property var filtered: query.length === 0
    ? _entries
    : _entries.filter(e => e.name.toLowerCase().includes(query.toLowerCase()))
    color: "black"; border.color: "white"; border.width: 1; radius: 4
    implicitWidth: expanded ? 340 : pillLabel.implicitWidth + 14
    implicitHeight: expanded ? 230 : pillLabel.implicitHeight + 14

    FileView {
        path: root.configDir + "/icons/.app_cache.tsv"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root._entries = text().split("\n").filter(l => l.trim().length).map(l => {
                const p = l.split("\t")
                const iconPath = p[2] ? root.iconsDir + "/" + p[2] + ".png" : ""
                return { name: p[0] || "", desktopPath: p[1] || "", iconPath }
            }).filter(e => e.name && e.desktopPath)
        }
        onLoadFailed: (error) => { root._entries = [] }
    }

    Text {
        id: pillLabel
        visible: !root.expanded
        anchors.centerIn: parent
        text: "Applications"
        color: "white"; font.pixelSize: 15; font.family: "SF Pro Display"
    }

    // Collapsed: click opens. Expanded: absorbs clicks (margin overrun
    // covers border clicks) so they don't fall to the shell's background
    // click-away handler, and re-grabs search focus (OnDemand needs an
    // interaction to actually apply it, not just a QML focus() call).
    MouseArea {
        anchors.fill: parent
        anchors.margins: root.expanded ? -2 : 0
        onClicked: root.expanded ? searchInput.forceActiveFocus() : (root.expanded = true)
    }
    onExpandedChanged: expanded ? searchInput.forceActiveFocus() : (searchInput.focus = false)
    ColumnLayout {
        visible: root.expanded
        anchors.fill: parent
        anchors.margins: 3
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            height: 26
            color: "black"; border.color: "white"; border.width: 1; radius: 3

            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.margins: 6
                color: "white"; font.pixelSize: 15; font.family: "SF Pro Display"
                focus: true
                onTextChanged: root.query = text

                Text {
                    visible: searchInput.text.length === 0
                    text: "Search..."
                    color: "#888888"; font.pixelSize: 15; font.family: "SF Pro Display"
                }
            }
        }

        Flickable {
            id: appsFlick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: rowsColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            readonly property int columns: Math.max(1, Math.floor((root.width - 20) / 74))
            readonly property var rows: {
                const chunks = []
                for (let i = 0; i < root.filtered.length; i += columns)
                    chunks.push(root.filtered.slice(i, i + columns))
                    return chunks
            }

            ColumnLayout {
                id: rowsColumn
                width: appsFlick.width
                spacing: 15

                Repeater {
                    model: appsFlick.rows
                    delegate: RowLayout {
                        id: appRow
                        required property var modelData
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 8

                        Repeater {
                            model: appRow.modelData
                            delegate: Rectangle {
                                required property var modelData
                                width: 66; height: 66
                                color: "black"; border.color: "white"; border.width: 1; radius: 4

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 2
                                    width: parent.width - 8

                                    Image {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: !!modelData.iconPath
                                        width: 28; height: 28
                                        source: modelData.iconPath ? "file://" + modelData.iconPath : ""
                                        smooth: true; asynchronous: true
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.name.length > 10 ? modelData.name.substring(0, 9) + "\u2026" : modelData.name
                                        color: "white"; font.pixelSize: 9; font.family: "SF Pro Display"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Quickshell.execDetached(["bash", root.configDir + "/scripts/sbs-app-launch.sh", modelData.desktopPath])
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    function collapse() { root.expanded = false }
}
