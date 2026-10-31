import QtQuick
import QtQuick.Layouts

// SBSScrollList.qml — shared capped/scrolling list wrapper, factored
// out of the four near-identical Item{clip}+ListView blocks in
// SBSWifi.qml (saved + scan) and SBSBluetooth.qml (paired + scan).
// Shrinks to fit content under maxVisibleRows worth of rowHeight,
// scrolls past that instead of growing indefinitely -- same
// `listHeight()` math each of those four blocks duplicated.
//
// Delegates should size themselves off `ListView.view.width` (the
// standard QML attached-property pattern) rather than a named id, so
// the same delegate works regardless of which instance it's plugged
// into.
Item {
    id: root
    property alias model: listView.model
    property alias delegate: listView.delegate
    property int rowHeight: 28
    property int rowSpacing: 4
    property int maxVisibleRows: 5
    readonly property int count: model ? model.length : 0

    Layout.alignment: Qt.AlignHCenter
    Layout.preferredWidth: 200
    Layout.preferredHeight: {
        const n = Math.min(count, maxVisibleRows)
        return n <= 0 ? 0 : n * rowHeight + (n - 1) * rowSpacing
    }
    clip: true

    ListView {
        id: listView
        anchors.fill: parent
        spacing: root.rowSpacing
        clip: true
        interactive: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
    }
}
