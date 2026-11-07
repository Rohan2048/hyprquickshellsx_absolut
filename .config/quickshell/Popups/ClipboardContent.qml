import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// Everything inside the clipboard popup's panel. Used by ClipboardPopup.qml and, unchanged, by the live preview in
// Settings > Popups > Popup styles, so what you arrange there is exactly what the popup shows.
// `host` is the popup window (a stand-in in the preview). Widgets/PopupArrange makes the pieces movable.
Item {
    id: root

    property var host: null
    readonly property real baseWidth: 672
    // this popup has no PopupScale around it, so say which popup these pieces belong to
    property string popupId: "clipboard"
    property alias list: list
    property alias search: search

    implicitWidth: 672
    implicitHeight: 540

    ColumnLayout {
        id: arrangeCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // ---- search ----
        TextField {
            id: search
            Layout.fillWidth: true
            implicitHeight: 34
            selectByMouse: true
            placeholderText: "Search clipboard..."
            color: Theme.foreground
            placeholderTextColor: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            // border follows Settings > Theme > Border
            background: FieldBorder { radius: Theme.radiusSm; focused: search.activeFocus }
            onTextChanged: { host.query = text; host.cur = 0 }
            Keys.onPressed: (event) => {
                const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                switch (event.key) {
                    case Qt.Key_Escape: host.close(); event.accepted = true; break
                    case Qt.Key_Return:
                    case Qt.Key_Enter: host.pick(host.filtered[host.cur]); event.accepted = true; break
                    case Qt.Key_Down: host.move(1); event.accepted = true; break
                    case Qt.Key_Up: host.move(-1); event.accepted = true; break
                    case Qt.Key_Tab: host.move(1); event.accepted = true; break
                    case Qt.Key_Backtab: host.move(-1); event.accepted = true; break
                    case Qt.Key_PageDown: host.move(6); event.accepted = true; break
                    case Qt.Key_PageUp: host.move(-6); event.accepted = true; break
                    case Qt.Key_Delete:
                        if (ctrl) { host.remove(host.filtered[host.cur]); event.accepted = true }
                        break
                }
            }
        }

        // ---- the list ----
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            model: host.filtered
            currentIndex: host.cur

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property bool selected: index === host.cur
                readonly property bool hot: rowMouse.containsMouse || delMouse.containsMouse

                width: ListView.view.width
                height: 38
                radius: Theme.radiusSm
                color: selected ? Theme.hoverBgStrong : (hot ? Theme.hoverBg : "transparent")
                Behavior on color { ColorAnimation { duration: 120 } }

                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: host.cur = row.index
                    onClicked: host.pick(row.modelData)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 8
                    spacing: 8

                    // images are listed with their size
                    Rectangle {
                        visible: row.modelData.image
                        implicitWidth: tag.implicitWidth + 12
                        implicitHeight: tag.implicitHeight + 4
                        radius: height / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.textDim
                        Text {
                            id: tag
                            anchors.centerIn: parent
                            text: "Image"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.bold: true
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: row.modelData.image ? row.modelData.info : row.modelData.text
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                    // remove this one entry
                    Item {
                        implicitWidth: 22
                        implicitHeight: 22
                        opacity: row.hot || row.selected ? 0.8 : 0
                        Behavior on opacity { NumberAnimation { duration: 100 } }
                        Text {
                            anchors.centerIn: parent
                            text: "\u00d7"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 4
                        }
                        MouseArea {
                            id: delMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: host.remove(row.modelData)
                        }
                    }
                }
            }

            // nothing to show
            Text {
                anchors.centerIn: parent
                visible: host.filtered.length === 0
                horizontalAlignment: Text.AlignHCenter
                text: !host.loaded ? "" : (host.query.trim() !== "" ? "Nothing matches" : "The clipboard history is empty.\nCopy something, or check that cliphist is running.")
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }

        // ---- footer ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "Enter copy   Esc close   Ctrl+Del remove"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeXs
            }
            GlassButton {
                visible: host.entries.length > 0
                text: host.wipeArmed ? "Really clear all?" : "Clear all"
                implicitHeight: 26
                onClicked: { if (host.wipeArmed) host.wipe(); else host.wipeArmed = true }
            }
        }
    }

    PopupArrange { containers: [arrangeCol] }
}
