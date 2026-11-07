import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

// Countdown timer view for the SettingsPanel's Timer page. Pure UI now
// -- all state and logic (start/pause/reset/adjust, the alarm loop)
// lives in SBSState, so this view and the timer pill in SBSShell.qml
// are just two windows onto the same running timer.
//
// Flat structure (no nested ColumnLayout) -- every centered item is a
// direct child of `content` using Layout.alignment: Qt.AlignHCenter,
// same pattern as SBSStopwatch.qml. An earlier version wrapped the
// countdown/time's-up groups in their own nested ColumnLayouts with
// Layout.fillWidth, which broke centering.
Item {
    id: root
    implicitWidth: 240
    implicitHeight: content.implicitHeight

    property bool adjustVisible: !SBSState.tRunning && SBSState.remainingMs === SBSState.durationMs

    ColumnLayout {
        id: content
        width: parent.width
        spacing: 8

        // ---- Countdown view ----
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: !SBSState.timesUp
            text: SBSState.tTimeText
            font.pixelSize: 22
            font.bold: true
            font.family: "SF Pro Display"
            color: "white"
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: !SBSState.timesUp && root.adjustVisible
            spacing: 12

            Rectangle {
                width: 38; height: 26
                color: "black"; border.color: "#555555"; border.width: 1; radius: 3
                Text { anchors.centerIn: parent; text: "-1h"; font.pixelSize: 10; font.family: "SF Pro Display"; color: "white" }
                MouseArea { anchors.fill: parent; onClicked: SBSState.tAdjust(-3600000) }
            }
            Rectangle {
                width: 38; height: 26
                color: "black"; border.color: "#555555"; border.width: 1; radius: 3
                Text { anchors.centerIn: parent; text: "-1m"; font.pixelSize: 10; font.family: "SF Pro Display"; color: "white" }
                MouseArea { anchors.fill: parent; onClicked: SBSState.tAdjust(-60000) }
            }
            Rectangle {
                width: 38; height: 26
                color: "black"; border.color: "#555555"; border.width: 1; radius: 3
                Text { anchors.centerIn: parent; text: "+1m"; font.pixelSize: 10; font.family: "SF Pro Display"; color: "white" }
                MouseArea { anchors.fill: parent; onClicked: SBSState.tAdjust(60000) }
            }
            Rectangle {
                width: 38; height: 26
                color: "black"; border.color: "#555555"; border.width: 1; radius: 3
                Text { anchors.centerIn: parent; text: "+1h"; font.pixelSize: 10; font.family: "SF Pro Display"; color: "white" }
                MouseArea { anchors.fill: parent; onClicked: SBSState.tAdjust(3600000) }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: !SBSState.timesUp
            spacing: 16

            Rectangle {
                width: 64; height: 28
                color: "black"; border.color: "white"; border.width: 1; radius: 4
                Text {
                    anchors.centerIn: parent
                    text: SBSState.tRunning ? "Pause" : "Start"
                    font.pixelSize: 11; font.family: "SF Pro Display"; color: "white"
                }
                MouseArea { anchors.fill: parent; onClicked: SBSState.tRunning ? SBSState.tPause() : SBSState.tStart() }
            }
            Rectangle {
                width: 64; height: 28
                color: "black"; border.color: "#555555"; border.width: 1; radius: 4
                Text {
                    anchors.centerIn: parent
                    text: "Reset"
                    font.pixelSize: 11; font.family: "SF Pro Display"; color: "white"
                }
                MouseArea { anchors.fill: parent; onClicked: SBSState.tReset() }
            }
        }

        // ---- Time's-up view -- occupies the same space, no overlay ----
        Text {
            Layout.alignment: Qt.AlignHCenter
            visible: SBSState.timesUp
            text: "Time's Up!"
            font.pixelSize: 16
            font.bold: true
            font.family: "SF Pro Display"
            color: "white"
        }

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: SBSState.timesUp
            width: 60; height: 28
            color: "black"; border.color: "white"; border.width: 1; radius: 4
            Text { anchors.centerIn: parent; text: "OK"; font.pixelSize: 11; font.family: "SF Pro Display"; color: "white" }
            MouseArea { anchors.fill: parent; onClicked: SBSState.tReset() }
        }
    }
}
