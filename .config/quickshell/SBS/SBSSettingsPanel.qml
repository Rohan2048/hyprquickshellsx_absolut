import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Services"
import "./Widgets"

// SettingsPanel -- opened from the gear icon in SBSShell. Started out as
// just the Wifi/Bluetooth/Airplane radios row; now also hosts Timer,
// Stopwatch, and minimal Wifi/Bluetooth device lists in the same space.
// currentView picks which content the panel shows; every non-"radios"
// view gets a "Back" row that returns to the radios row. Panel always
// reopens on the radios view.
//
// Wifi/Bluetooth cells: the icon's own MouseArea still just toggles the
// radio on/off (unchanged). The label under it ("Wifi"/"Bluetooth") is
// now its own click target that navigates into that radio's minimal view
// -- so tapping the icon flips the radio, tapping the word takes you in.
Rectangle {
    id: root
    color: "black"
    border.color: "white"
    border.width: 1
    radius: 6

    readonly property string iconDir: Quickshell.env("HOME") + "/.config/icons"
    property bool airplaneMode: false
    property Process rfkillProc: Process { }

    // Hide/reveal toggle -- driven by SBSShell, which owns the actual
    // uiHidden state and hides the rest of the shell. This panel only
    // displays hiddenState and asks the shell to flip it.
    property bool hiddenState: false
    signal hideToggleRequested()

    // "radios" | "timer" | "stopwatch" | "wifi" | "bluetooth"
    property string currentView: "radios"

    onVisibleChanged: if (!visible) currentView = "radios"

    implicitWidth: col.implicitWidth + 24
    implicitHeight: col.implicitHeight + 20

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: 12

        // ---- Back row: shown for every non-"radios" view ----
        Item {
            Layout.alignment: Qt.AlignLeft
            visible: root.currentView !== "radios"
            implicitWidth: backLabel.implicitWidth
            implicitHeight: backLabel.implicitHeight

            Text {
                id: backLabel
                text: "\u2190 Back"
                color: "white"
                font.pixelSize: 11
                font.family: "SF Pro Display"
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                onClicked: root.currentView = "radios"
            }
        }

        // ---- Radios grid: Wifi / Bluetooth / Airplane / Timer / Stopwatch / Hide -- 3 per row ----
        GridLayout {
            id: row
            visible: root.currentView === "radios"
            Layout.alignment: Qt.AlignHCenter
            columns: 3
            columnSpacing: 24
            rowSpacing: 16

            ColumnLayout {
                spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 46; height: 32
                    color: "black"
                    border.color: "white"; border.width: 1
                    radius: 4
                    Image {
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: "file://" + root.iconDir + (Wifi.radioOn ? "/wifion.svg" : "/wifi-off.svg")
                        smooth: true
                    }
                    MouseArea { anchors.fill: parent; onClicked: Wifi.toggleRadio() }
                }
                Text {
                    id: wifiLabel
                    Layout.alignment: Qt.AlignHCenter
                    text: "Wifi"
                    color: "white"; font.pixelSize: 10
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        onClicked: root.currentView = "wifi"
                    }
                }
            }

            ColumnLayout {
                spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 46; height: 32
                    color: "black"
                    border.color: "white"; border.width: 1
                    radius: 4
                    Image {
                        anchors.centerIn: parent
                        width: 20; height: 20
                        source: "file://" + root.iconDir + (Bluetooth.radioOn ? "/bluetooth-icon.svg" : "/bluetooth-off.svg")
                        smooth: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: Quickshell.execDetached(["bash", "-c",
                                                           "if rfkill list bluetooth | grep -q 'Soft blocked: no'; then rfkill block bluetooth; else rfkill unblock bluetooth; fi"])
                    }
                }
                Text {
                    id: btLabel
                    Layout.alignment: Qt.AlignHCenter
                    text: "Bluetooth"
                    color: "white"; font.pixelSize: 10
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        onClicked: root.currentView = "bluetooth"
                    }
                }
            }

            ColumnLayout {
                spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 46; height: 32
                    color: "black"
                    border.color: "white"; border.width: 1
                    radius: 4
                    Image {
                        anchors.centerIn: parent
                        width: 18; height: 18
                        source: "file://" + root.iconDir + "/airplane.svg"
                        smooth: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.airplaneMode = !root.airplaneMode
                            root.rfkillProc.command = ["bash", "-c", root.airplaneMode ? "rfkill block all" : "rfkill unblock all"]
                            root.rfkillProc.running = true
                        }
                    }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.airplaneMode ? "ON" : "OFF"
                    color: "white"; font.pixelSize: 10
                }
            }

            ColumnLayout {
                spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 46; height: 32
                    color: "black"
                    border.color: "white"; border.width: 1
                    radius: 4
                    Text {
                        anchors.centerIn: parent
                        text: "\u23F2"
                        color: "white"
                        font.pixelSize: 16
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.currentView = "timer" }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Timer"
                    color: "white"; font.pixelSize: 10
                }
            }

            ColumnLayout {
                spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 46; height: 32
                    color: "black"
                    border.color: "white"; border.width: 1
                    radius: 4
                    Text {
                        anchors.centerIn: parent
                        text: "\u23F1"
                        color: "white"
                        font.pixelSize: 16
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.currentView = "stopwatch" }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Stopwatch"
                    color: "white"; font.pixelSize: 10
                }
            }

            ColumnLayout {
                spacing: 4
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 46; height: 32
                    color: "black"
                    border.color: "white"; border.width: 1
                    radius: 4
                    Text {
                        anchors.centerIn: parent
                        text: root.hiddenState ? "\u25CB" : "\u25C9"
                        color: "white"
                        font.pixelSize: 16
                    }
                    MouseArea { anchors.fill: parent; onClicked: root.hideToggleRequested() }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.hiddenState ? "SHOW" : "HIDE"
                    color: "white"; font.pixelSize: 10
                }
            }
        }

        // ---- Timer / Stopwatch / Wifi / Bluetooth views: same space, swapped by currentView ----
        SBSTimer {
            Layout.alignment: Qt.AlignHCenter
            visible: root.currentView === "timer"
        }

        SBSStopwatch {
            Layout.alignment: Qt.AlignHCenter
            visible: root.currentView === "stopwatch"
        }

        SBSWifi {
            Layout.alignment: Qt.AlignHCenter
            visible: root.currentView === "wifi"
        }

        SBSBluetooth {
            Layout.alignment: Qt.AlignHCenter
            visible: root.currentView === "bluetooth"
        }
    }
}
