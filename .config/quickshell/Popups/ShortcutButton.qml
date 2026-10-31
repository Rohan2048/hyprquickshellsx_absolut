import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../Theme"

Rectangle {
    id: btn

    required property string appName
    required property string appExec
    required property string appIcon
    required property string appId
    // which side of the button the tooltip opens on: "right" | "left" (column on the screen's
    // left / right edge) or "below" | "above" (row along the top / bottom edge)
    property string tooltipSide: "right"

    signal launchRequested()
    signal removeRequested()

    Layout.preferredWidth: 44
    Layout.preferredHeight: 44
    Layout.alignment: Qt.AlignCenter

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
        // absolute path (cached PNG from the rofi flow), a full url, or an icon theme name
        source: {
            const i = btn.appIcon
            if (i === "") return ""
            if (i.startsWith("/")) return "file://" + i
            if (i.indexOf("://") > 0) return i
            return Quickshell.iconPath(i, "application-x-executable")
        }
        sourceSize: Qt.size(72, 72)
        mipmap: true
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
            x: btn.tooltipSide === "left" ? -width - 10
               : (btn.tooltipSide === "right" ? mouseArea.width + 10 : (mouseArea.width - width) / 2)
            y: btn.tooltipSide === "below" ? mouseArea.height + 10
               : (btn.tooltipSide === "above" ? -height - 10 : (mouseArea.height - height) / 2)
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
                color: Theme.popupBg
                radius: 6
                border.width: 1
                border.color: Theme.borderMuted
            }

            Text {
                id: tooltipText
                anchors.centerIn: parent
                text: btn.appName
                color: Theme.foreground
                font.pixelSize: Theme.fs(12)
                font.family:Theme.fontFamily
                wrapMode: Text.NoWrap
                antialiasing: true
                renderType: Text.NativeRendering
            }
        }
    }
}
