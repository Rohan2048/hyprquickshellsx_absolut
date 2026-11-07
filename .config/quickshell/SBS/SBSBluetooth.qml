import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../Services"

// SBSBluetooth.qml — minimal SBS Bluetooth view.
//
// Scanning is opt-in: Bluetooth._scanProc only runs while
// Bluetooth.liveMode is true (see Services/Bluetooth.qml). The gear
// button here is the only thing that sets it, and leaving the page
// forces it off, so scanning can't keep running once you've navigated
// away.
//
// Both device lists (paired + live scan) use SBSScrollList, capped at
// 5 rows worth of height, same as SBSWifi.qml / SBSStopwatch's laps box.
ColumnLayout {
    id: root
    spacing: 8
    property var newDevices: Bluetooth.scanList.filter(d => d && d.name && !Bluetooth.history.some(h => h.name === d.name))

    onVisibleChanged: { Bluetooth.popupOpen = visible; if (!visible) Bluetooth.liveMode = false }

    RowLayout {
        Layout.fillWidth: true; Layout.preferredWidth: 200
        SBSText { Layout.fillWidth: true; text: "Bluetooth"; size: 13; font.bold: true }
        SBSBtn {
            width: 24; height: 24; size: 12; text: "\u2699"
            color: Bluetooth.liveMode ? "white" : "black"; fg: Bluetooth.liveMode ? "black" : "white"
            onClicked: Bluetooth.toggleLiveMode()
        }
    }

    // ---- Pairing prompts: confirm passkey / enter PIN / error ----
    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 200; spacing: 4
        visible: Bluetooth.pendingConfirm !== null || Bluetooth.pendingPin !== null || Bluetooth.pairError !== ""

        ColumnLayout {
            Layout.fillWidth: true; spacing: 2
            visible: Bluetooth.pendingConfirm !== null
            SBSText { text: "Confirm code on " + Bluetooth.pairingName + ":"; size: 9 }
            SBSText {
                Layout.alignment: Qt.AlignHCenter; size: 15; font.bold: true
                text: Bluetooth.pendingConfirm ? Bluetooth.pendingConfirm.code : ""
            }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: 8
                SBSBtn { width: 64; height: 24; size: 9; text: "Confirm"; onClicked: Bluetooth.confirmYes() }
                SBSBtn { width: 64; height: 24; size: 9; text: "Reject"; bc: "#ff8080"; fg: "#ff8080"; onClicked: Bluetooth.confirmNo() }
            }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: 4
            visible: Bluetooth.pendingPin !== null
            onVisibleChanged: if (visible) { pinField.text = ""; pinField.forceActiveFocus() }
            TextField {
                id: pinField
                Layout.fillWidth: true; implicitHeight: 24
                placeholderText: "PIN for " + Bluetooth.pairingName
                color: "white"; font.family: "SFPro Display"; font.pixelSize: 10
                background: Rectangle { color: "black"; border.color: "white"; border.width: 1; radius: 3 }
                onAccepted: Bluetooth.submitPin(text)
            }
            SBSBtn { width: 56; height: 24; size: 9; text: "Submit"; onClicked: Bluetooth.submitPin(pinField.text) }
        }

        RowLayout {
            Layout.fillWidth: true; spacing: 4
            visible: Bluetooth.pairError !== ""
            SBSText { Layout.fillWidth: true; text: Bluetooth.pairError; color: "#ff8080"; wrapMode: Text.Wrap; size: 9 }
            SBSBtn { width: 20; height: 20; size: 10; text: "\u2715"; onClicked: Bluetooth.dismissError() }
        }
    }

    // ---- Paired devices (default view) -- capped at 5 rows, scrolls past that ----
    SBSText {
        Layout.alignment: Qt.AlignHCenter; size: 10; text: "No paired devices"
        visible: !Bluetooth.liveMode && Bluetooth.history.length === 0
    }
    SBSScrollList {
        Layout.alignment: Qt.AlignHCenter
        visible: !Bluetooth.liveMode && Bluetooth.history.length > 0
        model: Bluetooth.history
        delegate: SBSPanel {
            id: entry
            required property var modelData
            width: ListView.view.width; height: 28
            SBSText {
                anchors.centerIn: parent
                text: (entry.modelData.name === Bluetooth.device ? "\u25cf " : "\u25cb ") + entry.modelData.name
            }
            MouseArea {
                anchors.fill: parent
                onClicked: entry.modelData.name === Bluetooth.device ? Bluetooth.disconnect(entry.modelData.name) : Bluetooth.connectTo(entry.modelData.name)
            }
        }
    }

    // ---- Live scan: new/unknown devices (only while gear is on) -- same cap ----
    ColumnLayout {
        Layout.alignment: Qt.AlignHCenter; Layout.preferredWidth: 200; spacing: 4
        visible: Bluetooth.liveMode

        SBSText {
            Layout.alignment: Qt.AlignHCenter; size: 10
            visible: root.newDevices.length === 0
            text: Bluetooth.scanList.length === 0 ? "Scanning\u2026" : "No new devices nearby"
        }

        SBSScrollList {
            Layout.alignment: Qt.AlignHCenter
            visible: root.newDevices.length > 0
            model: root.newDevices
            delegate: SBSPanel {
                id: entry
                required property var modelData
                width: ListView.view.width; height: 28
                SBSText { anchors.centerIn: parent; text: entry.modelData.name }
                MouseArea { anchors.fill: parent; onClicked: Bluetooth.startPair(entry.modelData.mac, entry.modelData.name) }
            }
        }
    }
}
