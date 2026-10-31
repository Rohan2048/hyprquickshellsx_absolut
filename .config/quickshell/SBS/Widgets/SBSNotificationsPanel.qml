import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../Services"
Rectangle {
    id: root
    property bool expanded: false
    readonly property int maxVisible: 3
    color: "black"; border.color: "white"; border.width: 1; radius: 4
    implicitWidth: expanded ? 260 : pillLabel.implicitWidth + 24
    implicitHeight: expanded
    ? Math.min(col.implicitHeight, maxContentHeight) + 44 + dndExtra
    : pillLabel.implicitHeight + 14
    // Extra height the DND banner adds when visible (its height + the row spacing it introduces).
    readonly property real dndExtra: Notifications.dndEnabled ? (dndBanner.implicitHeight + 6) : 0
    // Fixed budget for maxVisible collapsed cards, measured from a hidden reference card so it
    // never depends on live/scrolling repeater state. +6px slack so the last card's border and
    // the Flickable's clip edge don't shave a sliver off the bottom row.
    readonly property real maxContentHeight: root.maxVisible * sizeSample.implicitHeight
    + (root.maxVisible - 1) * col.spacing + 6
    Text {
        id: pillLabel
        visible: !root.expanded
        anchors.centerIn: parent
        text: "Notifications" + (Notifications.notificationCount > 0 ? " (" + Notifications.notificationCount + ")" : "")
        color: "white"; font.pixelSize: 12; font.family: "SF Pro Display"
    }
    MouseArea { anchors.fill: parent; enabled: !root.expanded; onClicked: root.expanded = true }
    // Hidden reference card mirroring one collapsed delegate, used only to measure its height.
    Rectangle {
        id: sizeSample
        visible: false
        width: col.width
        color: "transparent"; border.width: 1
        implicitHeight: sampleColumn.implicitHeight
        ColumnLayout {
            id: sampleColumn
            width: parent.width; spacing: 0
            RowLayout {
                Layout.fillWidth: true; Layout.margins: 8; spacing: 6
                Text { Layout.fillWidth: true; text: "Sample"; font.pixelSize: 11; font.family: "SF Pro Display" }
                Rectangle {
                    implicitWidth: sampleCopyLabel.implicitWidth + 10
                    implicitHeight: sampleCopyLabel.implicitHeight + 6
                    color: "transparent"; border.width: 1
                    Text { id: sampleCopyLabel; anchors.centerIn: parent; text: "Copy"; font.pixelSize: 9; font.family: "SF Pro Display" }
                }
            }
        }
    }
    ColumnLayout {
        visible: root.expanded
        anchors.fill: parent; anchors.margins: 10; spacing: 6
        RowLayout {
            Layout.fillWidth: true; spacing: 6
            // Sized like Clear All (label + fixed padding) so the two line up at any font/DPI.
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: dndIcon.width + 10; implicitHeight: dndIcon.height + 6
                color: "transparent"
                border.color: Notifications.dndEnabled ? "white" : Qt.rgba(1, 1, 1, 0.4); border.width: 1; radius: 3
                Image {
                    id: dndIcon
                    anchors.centerIn: parent; width: 12; height: 12
                    source: "file://" + Quickshell.env("HOME") + "/.config/icons/DND.svg"
                    fillMode: Image.PreserveAspectFit
                }
                MouseArea { anchors.fill: parent; onClicked: Notifications.toggleDnd() }
            }
            Text {
                Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter
                text: "Notifications"; color: "white"; font.pixelSize: 12; font.family: "SF Pro Display"
            }
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: clearLabel.implicitWidth + 10; implicitHeight: clearLabel.implicitHeight + 6
                color: "transparent"; border.color: "white"; border.width: 1; radius: 3
                Text { id: clearLabel; anchors.centerIn: parent; text: "Clear All"; color: "white"; font.pixelSize: 10; font.family: "SF Pro Display" }
                MouseArea { anchors.fill: parent; onClicked: Notifications.clearAll() }
            }
        }
        Text {
            id: dndBanner
            visible: Notifications.dndEnabled
            Layout.fillWidth: true
            text: "Do Not Disturb is enabled."
            color: "white"; font.pixelSize: 9; font.family: "SF Pro Display"
            horizontalAlignment: Text.AlignHCenter
        }
        Flickable {
            id: flick
            Layout.fillWidth: true; Layout.fillHeight: true
            contentWidth: width; contentHeight: col.implicitHeight + 4
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // Scrolls whenever real content exceeds the fixed cap, not tied to notification count.
            interactive: col.implicitHeight > root.maxContentHeight
            Column {
                id: col
                x: 1; width: parent.width - 2; spacing: 4; bottomPadding: 2
                Repeater {
                    id: repeater
                    model: Notifications.list
                    // Border wraps header + body together, instead of the body hanging outside it.
                    delegate: Rectangle {
                        id: notifItem
                        required property string title
                        required property string body
                        required property string hash
                        readonly property bool isEmpty: hash === ""
                        readonly property bool isExpanded: Notifications.expandedHash === hash
                        visible: !isEmpty
                        width: col.width; height: cardColumn.implicitHeight
                        color: "transparent"; border.color: "white"; border.width: 1; radius: 3
                        ColumnLayout {
                            id: cardColumn
                            width: parent.width; spacing: 0
                            RowLayout {
                                Layout.fillWidth: true; Layout.margins: 8; spacing: 6
                                Text {
                                    id: summaryLabel
                                    Layout.fillWidth: true
                                    text: (notifItem.isExpanded ? "\u25bd " : "\u25b7 ") + notifItem.title
                                    color: "white"; font.pixelSize: 11; font.family: "SF Pro Display"
                                    elide: notifItem.isExpanded ? Text.ElideNone : Text.ElideRight
                                    wrapMode: notifItem.isExpanded ? Text.Wrap : Text.NoWrap
                                }
                                Rectangle {
                                    id: copyButton
                                    implicitWidth: copyLabel.implicitWidth + 10; implicitHeight: copyLabel.implicitHeight + 6
                                    color: "transparent"; border.color: "white"; border.width: 1; radius: 3
                                    Text { id: copyLabel; anchors.centerIn: parent; text: "Copy"; color: "white"; font.pixelSize: 9; font.family: "SF Pro Display" }
                                    MouseArea { anchors.fill: parent; onClicked: Notifications.copy(notifItem.hash) }
                                }
                            }
                            Text {
                                id: bodyLabel
                                visible: notifItem.isExpanded
                                Layout.fillWidth: true
                                Layout.leftMargin: 14; Layout.rightMargin: 8; Layout.bottomMargin: 8
                                text: notifItem.body
                                color: "white"; font.pixelSize: 10; font.family: "SF Pro Display"
                                wrapMode: Text.Wrap
                            }
                        }
                        // Sits under everything (z: -1) so it never steals clicks meant for Copy.
                        MouseArea { anchors.fill: parent; z: -1; onClicked: Notifications.toggleExpand(notifItem.hash) }
                    }
                }
            }
        }
    }
    function collapse() { root.expanded = false }
}
