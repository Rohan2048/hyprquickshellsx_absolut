import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Theme"

Rectangle {
    id: btn

    required property string appName
    required property string appExec
    required property string appIcon
    required property string appId

    signal launchRequested()
    signal removeRequested()

    Layout.preferredWidth: 44
    Layout.preferredHeight: 44
    Layout.alignment: Qt.AlignHCenter

    scale: mouseArea.containsMouse ? 1.25 : 1.0
    z: mouseArea.containsMouse ? 1 : 0

    Behavior on scale {
        NumberAnimation {
            duration: 160
            easing.type: Easing.OutBack
            easing.overshoot: 4
        }
    }

    radius: 10
    color: "transparent"
    border.width: 0

    Image {
        anchors.centerIn: parent
        width: 36
        height: 36
        source: "file://" + btn.appIcon
        smooth: true
        asynchronous: true
        fillMode: Image.PreserveAspectFit
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor

        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton)
                btn.launchRequested()
                else if (mouse.button === Qt.MiddleButton)
                    btn.removeRequested()
        }

        Timer {
            id: tooltipDelay
            interval: 400
            onTriggered: tooltipRoot.shown = true
        }

        onContainsMouseChanged: {
            if (mouseArea.containsMouse) {
                tooltipDelay.restart()
            } else {
                tooltipDelay.stop()
                tooltipRoot.shown = false
            }
        }

        Item {
            id: tooltipRoot
            property bool shown: false

            parent: mouseArea
            x: mouseArea.width + 10
            y: (mouseArea.height - height) / 2
            width: tooltipText.implicitWidth + 12
            height: tooltipText.implicitHeight + 12
            visible: opacity > 0
            opacity: shown ? 1 : 0
            z: 100

            // Cancel out btn's hover scale so this stays crisp and
            // normal-sized regardless of the icon growing.
            scale: 1 / btn.scale
            transformOrigin: Item.TopLeft

            Behavior on opacity {
                NumberAnimation { duration: 120 }
            }

            Rectangle {
                anchors.fill: parent
                readonly property real bgLuminance: 0.299 * Theme.background.r + 0.587 * Theme.background.g + 0.114 * Theme.background.b
                readonly property bool isDark: bgLuminance < 0.5
                color: isDark ? Qt.rgba(0, 0, 0, 0.75) : Qt.rgba(1, 1, 1, 0.75)
                radius: 6
                border.width: 1
                border.color: Theme.borderMuted
            }

            Text {
                id: tooltipText
                anchors.centerIn: parent
                text: btn.appName
                color: Theme.foreground
                font.pixelSize: 12
                font.family:Theme.fontFamily
                wrapMode: Text.NoWrap
                antialiasing: true
                renderType: Text.NativeRendering
            }
        }
    }
}
