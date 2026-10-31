import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import "../Theme"
import "../Widgets"

// Profile picture + user name on the lock screen (Settings > Lock screen > User).
// The picture is your own image, or (empty `pfp`) the system's: ~/.face, ~/.face.icon or the
// AccountsService icon. With none of those a round badge with your initial is drawn.
Item {
    id: root

    property bool showPfp: true
    property bool showName: true
    property string pfp: ""             // custom image path, "" = the system's
    property real size: 96
    property var textGrad: null
    property color textColor: Theme.foreground

    readonly property string user: Quickshell.env("USER") || "user"
    readonly property string home: Quickshell.env("HOME")
    // A custom image is used as is. For the system's picture a tiny shell check finds the first file that
    // exists, so nothing tries to open missing files (no warnings, no flicker).
    property string systemPfp: ""
    readonly property string source: root.pfp !== "" ? "file://" + root.pfp
    : (root.systemPfp !== "" ? "file://" + root.systemPfp : "")

    Process {
        running: root.pfp === "" && root.showPfp
        command: ["sh", "-c", "for f in \"$HOME/.face\" \"$HOME/.face.icon\" \"/var/lib/AccountsService/icons/$USER\"; do [ -f \"$f\" ] && { echo \"$f\"; break; }; done"]
        stdout: SplitParser { onRead: (line) => root.systemPfp = line.trim() }
    }

    implicitWidth: Math.max(col.implicitWidth, root.showPfp ? root.size : 0)
    implicitHeight: col.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Column {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10

        Item {
            id: disc
            visible: root.showPfp
            width: root.size
            height: root.size
            anchors.horizontalCenter: parent.horizontalCenter

            Image {
                id: img
                anchors.fill: parent
                visible: false
                source: root.source
                sourceSize: Qt.size(Math.round(root.size * 2), Math.round(root.size * 2))
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
            }
            Rectangle { id: round; anchors.fill: parent; radius: width / 2; visible: false }
            OpacityMask {
                anchors.fill: parent
                source: img
                maskSource: round
                visible: img.status === Image.Ready
            }
            // no picture found: a badge with the initial
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                visible: img.status !== Image.Ready
                color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.15)
                border.width: 1
                border.color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.4)
                Text {
                    anchors.centerIn: parent
                    text: root.user.charAt(0).toUpperCase()
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: root.size * 0.42
                    font.weight: Font.Medium
                }
            }
        }

        GradientText {
            visible: root.showName
            anchors.horizontalCenter: parent.horizontalCenter
            textGrad: root.textGrad
            fallbackColor: root.textColor
            text: root.user
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fs(24)
            font.weight: Font.Medium
        }
    }
}
