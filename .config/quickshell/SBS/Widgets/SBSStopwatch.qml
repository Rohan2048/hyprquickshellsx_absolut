import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

// Stopwatch view for the SettingsPanel's Stopwatch page. Pure UI now --
// all state and logic (start/pause/reset/lap, live time updates) lives
// in SBSState, so this view and the stopwatch pill in SBSShell.qml are
// just two windows onto the same running stopwatch.
Item {
    id: root
    implicitWidth: 240
    implicitHeight: content.implicitHeight

    readonly property int lapRowHeight: 18
    readonly property int lapSpacing: 4
    readonly property int maxVisibleLaps: 5

    function lapsHeight(count) {
        const n = Math.min(count, root.maxVisibleLaps)
        return n <= 0 ? 0 : n * root.lapRowHeight + (n - 1) * root.lapSpacing
    }

    ColumnLayout {
        id: content
        width: parent.width
        spacing: 6

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: SBSState.swTimeText
            font.pixelSize: 22
            font.bold: true
            font.family: "SF Pro Display"
            color: "white"
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 16

            Rectangle {
                width: 64; height: 28
                color: "black"; border.color: "white"; border.width: 1; radius: 4
                Text {
                    anchors.centerIn: parent
                    text: SBSState.swRunning ? "Pause" : "Start"
                    font.pixelSize: 11; font.family: "SF Pro Display"; color: "white"
                }
                MouseArea { anchors.fill: parent; onClicked: SBSState.swRunning ? SBSState.swPause() : SBSState.swStart() }
            }
            Rectangle {
                width: 64; height: 28
                color: "black"; border.color: "#555555"; border.width: 1; radius: 4
                Text {
                    anchors.centerIn: parent
                    text: SBSState.swRunning ? "Lap" : "Reset"
                    font.pixelSize: 11; font.family: "SF Pro Display"; color: "white"
                }
                MouseArea { anchors.fill: parent; onClicked: SBSState.swRunning ? SBSState.swLap() : SBSState.swReset() }
            }
        }

        // Laps box -- height tracks lap count: 0 when empty, grows one
        // row at a time up to maxVisibleLaps (5), then holds there and
        // the ListView scrolls for anything beyond that instead of
        // growing further.
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 220
            Layout.preferredHeight: root.lapsHeight(SBSState.swLapModel.count)
            Layout.topMargin: SBSState.swLapModel.count > 0 ? 2 : 0
            clip: true
            visible: SBSState.swLapModel.count > 0

            ListView {
                id: lapListView
                anchors.fill: parent
                model: SBSState.swLapModel
                spacing: root.lapSpacing
                clip: true
                interactive: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                delegate: RowLayout {
                    width: lapListView.width
                    height: root.lapRowHeight

                    Text {
                        text: "Lap " + (SBSState.swLapModel.count - index)
                        font.pixelSize: 10
                        font.family: "SF Pro Display"
                        color: "#aaaaaa"
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: SBSState.swFmt(model.time)
                        font.pixelSize: 10
                        font.family: "SF Pro Display"
                        color: "white"
                    }
                }
            }
        }
    }
}
