import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Services"

// SBSLockSettingsPanel.qml — quick-settings panel for the SBS lock
// screen.
//
// Mirrors LockSettingsPanel.qml's feature set — Wifi, Bluetooth,
// Airplane, Volume, Brightness — as flat black/white monospace rows
// with no GlassPanel slide/shake/blur entrance. The light/dark Theme
// toggle from the main lock screen is dropped: this stack is fixed
// monochrome, so there's no theme to toggle.
//
// Wifi/Bluetooth detail views are SBSWifi.qml / SBSBluetooth.qml
// themselves (same directory, already minimal/monochrome/monospace)
// rather than a re-implementation — same pattern SBSSettingsPanel.qml
// uses for the main SBS shell.
Rectangle {
    id: root
    color: "black"
    border.color: "white"
    border.width: 1
    radius: 6

    readonly property string iconDir: "file://" + Quickshell.env("HOME") + "/.config/icons/"
    property bool airplaneMode: false
    property Process rfkillProc: Process {}

    // "root" | "wifi" | "bluetooth"
    property string currentView: "root"
    onVisibleChanged: if (!visible) currentView = "root"

    implicitWidth: 220
    implicitHeight: col.implicitHeight + 24

    ColumnLayout {
        id: col
        anchors.centerIn: parent
        spacing: 12
        width: 196

        // ---- Back row: shown for wifi/bluetooth ----
        Item {
            Layout.alignment: Qt.AlignLeft
            visible: root.currentView !== "root"
            implicitWidth: backLabel.implicitWidth
            implicitHeight: backLabel.implicitHeight

            Text {
                id: backLabel
                text: "\u2190 BACK"
                color: "white"
                font.pixelSize: 11
                font.family: "monospace"
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                onClicked: root.currentView = "root"
            }
        }

        // ---- Wifi / Bluetooth / Airplane row ----
        RowLayout {
            visible: root.currentView === "root"
            Layout.alignment: Qt.AlignHCenter
            spacing: 20

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
                        source: root.iconDir + (Wifi.radioOn ? "wifion.svg" : "wifi-off.svg")
                        smooth: true
                    }
                    MouseArea { anchors.fill: parent; onClicked: Wifi.toggleRadio() }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "WIFI"
                    color: "white"; font.pixelSize: 10; font.family: "monospace"
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
                        source: root.iconDir + (Bluetooth.radioOn ? "bluetooth-icon.svg" : "bluetooth-off.svg")
                        smooth: true
                    }
                    MouseArea { anchors.fill: parent; onClicked: Bluetooth.toggleRadio() }
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "BT"
                    color: "white"; font.pixelSize: 10; font.family: "monospace"
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
                        source: root.iconDir + "airplane.svg"
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
                    color: "white"; font.pixelSize: 10; font.family: "monospace"
                }
            }
        }

        // ---- Volume / Brightness ----
        ColumnLayout {
            visible: root.currentView === "root"
            Layout.fillWidth: true
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "VOL"; color: "white"; font.family: "monospace"; font.pixelSize: 10 }

                Item {
                    id: volTrack
                    Layout.fillWidth: true
                    implicitHeight: 16

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 4
                        color: "black"
                        border.color: "white"; border.width: 1
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, Math.min(parent.width, (Volume.volume / 100) * parent.width))
                        height: 4
                        color: "white"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: (mouse) => Volume.setVolume(Math.round(Math.max(0, Math.min(100, (mouse.x / width) * 100))))
                        onPositionChanged: (mouse) => { if (pressed) Volume.setVolume(Math.round(Math.max(0, Math.min(100, (mouse.x / width) * 100)))) }
                    }
                }

                Text {
                    text: Volume.volume + "%" + (Volume.muted ? " (M)" : "")
                    color: "white"; font.family: "monospace"; font.pixelSize: 10
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text { text: "BRT"; color: "white"; font.family: "monospace"; font.pixelSize: 10 }

                Item {
                    id: brtTrack
                    Layout.fillWidth: true
                    implicitHeight: 16

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width; height: 4
                        color: "black"
                        border.color: "white"; border.width: 1
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(0, Math.min(parent.width, (Brightness.brightness / 100) * parent.width))
                        height: 4
                        color: "white"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: (mouse) => Brightness.setBrightness(Math.round(Math.max(0, Math.min(100, (mouse.x / width) * 100))))
                        onPositionChanged: (mouse) => { if (pressed) Brightness.setBrightness(Math.round(Math.max(0, Math.min(100, (mouse.x / width) * 100)))) }
                    }
                }

                Text {
                    text: Brightness.brightness + "%"
                    color: "white"; font.family: "monospace"; font.pixelSize: 10
                }
            }
        }

        // ---- Wifi / Bluetooth detail views (reused from SBS/) ----
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
