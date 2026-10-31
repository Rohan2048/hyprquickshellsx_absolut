import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "./Widgets"
import "../Services"
import "../SBS"

// SBSShell.qml — Super Battery Saver minimal desktop.
//
// One PanelWindow per screen (same Variants-over-screens pattern as
// Wallpaper/Bar), fully replacing the normal wallpaper + bar + popup
// stack while active. Flat black background, plain white line-art
// widgets, no blur/MultiEffect/Behavior/NumberAnimation anywhere in
// this tree -- built minimal from scratch rather than relying on
// Animations.qml's kill-switch (that's for the *normal* shell's
// Lock/Screenshot/WorkspaceOverview trees, which stay mounted here).
//
// uiHidden lives on SBSState (shared across every screen's
// PanelWindow) and is reachable via `qs ipc call sbs toggleHide`
// (CTRL+H) as well as the gear icon's radios panel. Clock, settings
// gear, and battery corner ignore it, so they're the only things left
// on screen when hidden -- timerPill/stopwatchPill and their expanded
// panels are also exempt, showing SBSState.timerActive/stopwatchActive
// regardless, since a running countdown/stopwatch should stay visible.
//
// Each pill is collapsed by default (icon + compact time, left of
// Exit) and expands into a control panel below itself on click. State
// and every action (start/pause/reset/lap/adjust) live on SBSState, so
// the pill drives the same stopwatch/timer as the SettingsPanel's
// Stopwatch/Timer views; resetting either clears the active flag,
// which is what makes the pill vanish.
//
// Buttons/labels/panels lean on the shared SBSBtn/SBSText/SBSPanel
// components for the repeated styling; layout, anchoring, and every
// binding below are unchanged from the original per-Rectangle version.
PanelWindow {
    id: root
    required property var modelData
    screen: modelData

    WlrLayershell.namespace: "quickshell:sbs"
    WlrLayershell.layer: WlrLayer.Background
    // OnDemand (not None): None blocks the compositor from ever routing
    // keyboard events here (broke the Applications search box). OnDemand
    // grabs focus only while something inside has active focus and
    // releases it otherwise, so gear/exit/radios clicks stay unaffected.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusiveZone: 0
    color: "black"
    anchors { top: true; bottom: true; left: true; right: true }
    visible: true

    // Collapse any expanded panel when clicking empty background space.
    MouseArea {
        anchors.fill: parent
        onClicked: {
            notifications.collapse(); commands.collapse(); quickApps.collapse()
            applications.collapse(); volume.collapse()
            timerExpanded.visible = false; stopwatchExpanded.visible = false
        }
    }

    // ---- Top row: Notifications (left) / Settings gear (center) / Exit + pills (right) ----
    SBSNotificationsPanel {
        id: notifications
        visible: !SBSState.uiHidden
        anchors { top: parent.top; left: parent.left; margins: 16 }
    }
    SBSPanel {
        id: settingsGear
        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 16 }
        width: 32; height: 32; z: 2
        SBSText { anchors.centerIn: parent; text: "\u2699"; size: 16 }
        MouseArea { anchors.fill: parent; onClicked: radios.visible = !radios.visible }
    }
    SBSSettingsPanel {
        id: radios
        visible: false
        hiddenState: SBSState.uiHidden
        onHideToggleRequested: SBSState.toggleHide()
        anchors { top: settingsGear.bottom; horizontalCenter: parent.horizontalCenter; topMargin: 10 }
    }
    SBSBtn {
        id: exitButton
        visible: !SBSState.uiHidden
        anchors { top: parent.top; right: parent.right; margins: 16 }
        size: 12; text: "Exit"
        onClicked: SBSState.disable()
    }

    // Collapsed timer pill: red square (a plain Rectangle, not an emoji
    // glyph -- color-emoji font fallback isn't guaranteed here) +
    // remaining time. Not gated on uiHidden.
    SBSPanel {
        id: timerPill
        visible: SBSState.timerActive
        anchors.top: parent.top; anchors.topMargin: 16
        anchors.right: SBSState.uiHidden ? parent.right : exitButton.left
        anchors.rightMargin: SBSState.uiHidden ? 16 : 8
        width: timerPillRow.implicitWidth + 20; height: 32; z: 3
        RowLayout {
            id: timerPillRow
            anchors.centerIn: parent; spacing: 6
            Rectangle { width: 10; height: 10; radius: 2; color: "#e53935"; Layout.alignment: Qt.AlignVCenter }
            SBSText { text: SBSState.fmtShort(SBSState.remainingMs); size: 12; font.bold: true }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: { timerExpanded.visible = !timerExpanded.visible; stopwatchExpanded.visible = false }
        }
    }

    // Timer's expanded control panel -- countdown view / time's-up view, same split as SBSTimer.qml.
    SBSPanel {
        id: timerExpanded
        visible: false
        anchors { top: timerPill.bottom; right: timerPill.right; topMargin: 6 }
        width: 200; height: timerExpandedContent.implicitHeight + 20; z: 3
        ColumnLayout {
            id: timerExpandedContent
            anchors.centerIn: parent; spacing: 8
            visible: !SBSState.timesUp
            SBSText { Layout.alignment: Qt.AlignHCenter; text: SBSState.tTimeText; size: 18; font.bold: true }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 8
                visible: !SBSState.tRunning && SBSState.remainingMs === SBSState.durationMs
                SBSBtn { width: 34; height: 24; size: 9; bc: "#555555"; text: "-1h"; onClicked: SBSState.tAdjust(-3600000) }
                SBSBtn { width: 34; height: 24; size: 9; bc: "#555555"; text: "-1m"; onClicked: SBSState.tAdjust(-60000) }
                SBSBtn { width: 34; height: 24; size: 9; bc: "#555555"; text: "+1m"; onClicked: SBSState.tAdjust(60000) }
                SBSBtn { width: 34; height: 24; size: 9; bc: "#555555"; text: "+1h"; onClicked: SBSState.tAdjust(3600000) }
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 12
                SBSBtn {
                    width: 56; height: 26; size: 10; text: SBSState.tRunning ? "Stop" : "Start"
                    onClicked: SBSState.tRunning ? SBSState.tPause() : SBSState.tStart()
                }
                SBSBtn {
                    width: 56; height: 26; size: 10; bc: "#555555"; text: "Reset"
                    onClicked: { SBSState.tReset(); timerExpanded.visible = false }
                }
            }
        }
        ColumnLayout {
            anchors.centerIn: parent; spacing: 8
            visible: SBSState.timesUp
            SBSText { Layout.alignment: Qt.AlignHCenter; text: "Time's Up!"; size: 14; font.bold: true }
            SBSBtn {
                Layout.alignment: Qt.AlignHCenter; width: 50; height: 26; size: 10; text: "OK"
                onClicked: { SBSState.tReset(); timerExpanded.visible = false }
            }
        }
    }

    // Collapsed stopwatch pill: ⏱ + elapsed time. Slots left of timerPill
    // when both are active, else takes its spot next to Exit. Not gated on uiHidden.
    SBSPanel {
        id: stopwatchPill
        visible: SBSState.stopwatchActive
        anchors.top: parent.top; anchors.topMargin: 16
        anchors.right: timerPill.visible ? timerPill.left : (SBSState.uiHidden ? parent.right : exitButton.left)
        anchors.rightMargin: timerPill.visible ? 8 : (SBSState.uiHidden ? 16 : 8)
        width: swPillRow.implicitWidth + 20; height: 32; z: 3
        RowLayout {
            id: swPillRow
            anchors.centerIn: parent; spacing: 6
            SBSText { text: "\u23F1" /* ⏱ */; size: 12 }
            SBSText { text: SBSState.fmtShort(SBSState.swLiveMs); size: 12; font.bold: true }
        }
        MouseArea {
            anchors.fill: parent
            onClicked: { stopwatchExpanded.visible = !stopwatchExpanded.visible; timerExpanded.visible = false }
        }
    }

    // Stopwatch's expanded control panel -- precise time, Start/Pause + Lap/Reset, and the lap list, same as SBSStopwatch.qml.
    SBSPanel {
        id: stopwatchExpanded
        visible: false
        anchors { top: stopwatchPill.bottom; right: stopwatchPill.right; topMargin: 6 }
        width: 200; height: swExpandedContent.implicitHeight + 20; z: 3
        ColumnLayout {
            id: swExpandedContent
            anchors.centerIn: parent; spacing: 8
            SBSText { Layout.alignment: Qt.AlignHCenter; text: SBSState.swTimeText; size: 18; font.bold: true }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 12
                SBSBtn {
                    width: 56; height: 26; size: 10; text: SBSState.swRunning ? "Pause" : "Start"
                    onClicked: SBSState.swRunning ? SBSState.swPause() : SBSState.swStart()
                }
                SBSBtn {
                    width: 56; height: 26; size: 10; bc: "#555555"; text: SBSState.swRunning ? "Lap" : "Reset"
                    onClicked: SBSState.swRunning ? SBSState.swLap() : (SBSState.swReset(), stopwatchExpanded.visible = false)
                }
            }
            Item {
                Layout.preferredWidth: 180; Layout.preferredHeight: 60; clip: true
                visible: SBSState.swLapModel.count > 0
                ListView {
                    id: pillLapListView
                    anchors.fill: parent
                    model: SBSState.swLapModel; spacing: 4; clip: true; interactive: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    delegate: RowLayout {
                        width: pillLapListView.width; height: 18
                        SBSText { text: "Lap " + (SBSState.swLapModel.count - index); size: 9; color: "#aaaaaa" }
                        Item { Layout.fillWidth: true }
                        SBSText { text: SBSState.swFmt(model.time); size: 9 }
                    }
                }
            }
        }
    }

    // ---- Middle row: Commands (left) / Clock (center) / Quick Apps (right) ----
    SBSCommandsPanel {
        id: commands
        visible: !SBSState.uiHidden
        anchors { left: parent.left; verticalCenter: parent.verticalCenter; margins: 16 }
    }
    SBSClock { anchors.centerIn: parent }
    SBSQuickAppsPanel {
        id: quickApps
        visible: !SBSState.uiHidden
        anchors { right: parent.right; verticalCenter: parent.verticalCenter; margins: 16 }
    }

    // ---- Bottom row: Volume (left) / Applications (center) / Battery (right) ----
    SBSVolumePanel {
        id: volume
        visible: !SBSState.uiHidden
        anchors { bottom: parent.bottom; left: parent.left; margins: 16 }
    }
    SBSApplicationsPanel {
        id: applications
        visible: !SBSState.uiHidden
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 16 }
    }
    SBSBatteryCorner { anchors { bottom: parent.bottom; right: parent.right; margins: 16 } }

    SBSOSD {}
}
