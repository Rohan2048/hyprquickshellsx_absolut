import QtQuick

// SBSLockClock.qml — plain SF Pro Display time/date readout.
//
// No minute-change shake animation, no DirectionalBlur layer: just a
// value that updates once a second.
Column {
    id: root
    spacing: 4
    property date now: new Date()

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        font.family: "SF Pro Display"
        font.pixelSize: 150
        text: Qt.formatTime(root.now, "HH:mm")
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        color: "white"
        font.family: "SF Pro Display"
        font.pixelSize: 20
        text: Qt.formatDate(root.now, "dd MMMM, yyyy")
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }
}
