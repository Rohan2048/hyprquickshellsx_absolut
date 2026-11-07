import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../Services"

// SBSWifi.qml — minimal SBS Wi-Fi view.
//
// Scanning is opt-in: Wifi._scanProc only runs while Wifi.liveMode AND
// Wifi.popupOpen are both true (see Services/Wifi.qml), so nothing scans
// in the background just because this page exists. The gear button here
// is the only thing that sets liveMode; popupOpen tracks this page's own
// visible property, and leaving the page forces liveMode off too, so
// scanning can never keep running once you've navigated away.
//
// Both lists (saved networks + live scan) use SBSScrollList, capped at
// 5 rows worth of collapsed-row height -- below that they shrink to fit
// content; past that they scroll instead of growing indefinitely. The
// live-scan list's rows can expand in place (password field), so its
// cap is measured against the *collapsed* row height. Same pattern as
// SBSBluetooth.qml / SBSStopwatch.qml.
ColumnLayout {
    id: root
    spacing: 8
    property string expandedSsid: ""
    property var newNetworks: Wifi.scanList.filter(n => n && n.ssid && !Wifi.history.some(h => h.ssid === n.ssid))

    onVisibleChanged: {
        Wifi.popupOpen = visible
        if (!visible) { Wifi.liveMode = false; expandedSsid = "" }
    }

    RowLayout {
        Layout.fillWidth: true; Layout.preferredWidth: 200
        SBSText { Layout.fillWidth: true; text: "Wi-Fi"; size: 13; font.bold: true }
        SBSBtn {
            width: 24; height: 24; size: 12; text: "\u2699"
            color: Wifi.liveMode ? "white" : "black"; fg: Wifi.liveMode ? "black" : "white"
            onClicked: Wifi.toggleLiveMode()
        }
    }

    // ---- Saved networks (default view) -- capped at 5 rows, scrolls past that ----
    SBSText {
        Layout.alignment: Qt.AlignHCenter; size: 10; text: "No saved networks"
        visible: !Wifi.liveMode && Wifi.history.length === 0
    }
    SBSScrollList {
        Layout.alignment: Qt.AlignHCenter
        visible: !Wifi.liveMode && Wifi.history.length > 0
        model: Wifi.history
        delegate: SBSPanel {
            id: entry
            required property var modelData
            width: ListView.view.width; height: 28
            SBSText {
                anchors.centerIn: parent
                text: (entry.modelData.ssid === Wifi.ssid ? "\u25cf " : "\u25cb ") + entry.modelData.ssid
            }
            MouseArea {
                anchors.fill: parent
                onClicked: entry.modelData.ssid === Wifi.ssid ? Wifi.disconnect(entry.modelData.ssid) : Wifi.forceConnectTo(entry.modelData.ssid)
            }
        }
    }

    // ---- Live scan: new/unknown networks (only while gear is on) -- same cap ----
    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 200; spacing: 4
        visible: Wifi.liveMode

        SBSText {
            Layout.alignment: Qt.AlignHCenter; size: 10
            visible: root.newNetworks.length === 0
            text: Wifi.scanList.length === 0 ? "Scanning\u2026" : "No new networks nearby"
        }

        SBSScrollList {
            Layout.alignment: Qt.AlignHCenter
            visible: root.newNetworks.length > 0
            model: root.newNetworks
            delegate: ColumnLayout {
                id: entry
                required property var modelData
                readonly property bool secured: modelData.security !== "Open" && modelData.security !== "none"
                readonly property bool expanded: root.expandedSsid === modelData.ssid
                width: ListView.view.width
                spacing: 2

                onExpandedChanged: {
                    if (expanded) { pwField.text = ""; pwField.forceActiveFocus() }
                    else Wifi.dismissAuthError()
                }

                SBSPanel {
                    Layout.fillWidth: true; implicitHeight: 28
                    SBSText {
                        anchors.centerIn: parent
                        text: entry.modelData.ssid + " \u00b7 " + entry.modelData.signal + "%" + (entry.secured ? " \ud83d\udd12" : "")
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: entry.secured ? (root.expandedSsid = entry.expanded ? "" : entry.modelData.ssid) : Wifi.connectTo(entry.modelData.ssid)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; Layout.leftMargin: 6; visible: entry.expanded; spacing: 4
                    TextField {
                        id: pwField
                        Layout.fillWidth: true; implicitHeight: 24
                        echoMode: TextInput.Password
                        placeholderText: "Password"
                        color: "white"; font.family: "monospace"; font.pixelSize: 10
                        background: Rectangle { color: "black"; border.color: "white"; border.width: 1; radius: 3 }
                        onTextChanged: Wifi.dismissAuthError()
                        onAccepted: Wifi.connectWithPassword(entry.modelData.ssid, text)
                    }
                    SBSBtn { width: 60; height: 24; size: 9; text: "Connect"; onClicked: Wifi.connectWithPassword(entry.modelData.ssid, pwField.text) }
                }

                SBSText {
                    Layout.fillWidth: true; Layout.leftMargin: 6; size: 9
                    visible: entry.expanded && Wifi.authError !== "" && Wifi.authErrorSsid === entry.modelData.ssid
                    text: Wifi.authError; color: "#ff8080"; wrapMode: Text.Wrap
                }
            }
        }
    }
}
