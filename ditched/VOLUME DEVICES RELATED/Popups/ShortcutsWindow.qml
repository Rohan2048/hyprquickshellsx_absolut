import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../Services"
import "../Theme"

PanelWindow {
    id: shortcutsWindow

    property bool menuOpen: false
    property real openProgress: 0
    visible: menuOpen || openProgress > 0

    screen: Quickshell.screens[0]

    onMenuOpenChanged: {
        if (menuOpen) {
            closeAnim.stop()
            openAnim.restart()
        } else {
            openAnim.stop()
            closeAnim.restart()
        }
    }

    NumberAnimation {
        id: openAnim
        target: shortcutsWindow; property: "openProgress"
        to: 1
        duration: Animations.slideBlurDuration*1.2
        easing.type: Animations.slideBlurEasingOut
    }
    NumberAnimation {
        id: closeAnim
        target: shortcutsWindow; property: "openProgress"
        to: 0
        duration: Animations.scaleDuration(50)
        easing.type: Animations.slideBlurEasingIn
    }
    IpcHandler {
        target: "shortcuts"
        function toggle(): void { shortcutsWindow.menuOpen = !shortcutsWindow.menuOpen }
        function open(): void { shortcutsWindow.menuOpen = true }
        function close(): void { shortcutsWindow.menuOpen = false }
    }
    ClickAwayCloser {
        targetWindows: [shortcutsWindow]
        active: shortcutsWindow.menuOpen
        onDismissed: shortcutsWindow.menuOpen = false
    }

    WlrLayershell.namespace: "shortcuts-window"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusiveZone: -1

    anchors {
        top: true
        bottom: true
        left: true
    }

    // Surface is much wider than the visible dock so both the hover-scaled
    // icons AND the tooltip text (which sits to the right of the dock) have
    // room to render without hitting the Wayland surface edge. Popups from
    // a layer-shell surface can't escape past its bounds, so the surface
    // itself has to be sized for the widest thing we'll ever draw in it.
    implicitWidth: 260
    color: "transparent"

    // Without this, the whole 260px-wide surface — including the transparent
    // padding added for tooltip/hover-scale room — captures pointer input,
    // blocking clicks to anything underneath it even where nothing is drawn.
    // This restricts actual input handling to just the visible dock.
    mask: Region { item: dock }

    Rectangle {
        id: dock
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        width: 60
        height: content.implicitHeight + 16

        x: (1 - shortcutsWindow.openProgress*0.2) * -(width + 20)

        property real blurAmount: Animations.blurEnvelope(shortcutsWindow.openProgress) * Animations.slideBlurHorizontalLength * 1

        // Was "true" — permanently allocated FBO + shader pass every frame
        // for the popup's entire visible lifetime, same as glassPanel/content
        // in the other popups, and the same reason app icons/tooltip text
        // here would sit through a barely-nonzero blur pass indefinitely.
        // Now only layered while blurAmount is actually large enough to see.
        layer.enabled: dock.blurAmount > 0.05
        layer.effect: DirectionalBlur {
            angle: Animations.slideBlurHorizontalAngle
            length: dock.blurAmount
            samples: Animations.slideBlurSamples
            transparentBorder: true
        }

        color: Theme.barBg
        border.width: 1
        border.color: Theme.borderMuted

        topRightRadius: Theme.radiusMd
        bottomRightRadius: Theme.radiusMd
        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: 8
            spacing: 8

            Repeater {
                model: Shortcuts.shortcuts

                delegate: ShortcutButton {
                    required property var modelData

                    appName: modelData.name
                    appExec: modelData.exec
                    appIcon: modelData.icon
                    appId: modelData.id

                    onLaunchRequested: {
                        Shortcuts.launch(appExec)
                        shortcutsWindow.menuOpen = false
                    }
                    onRemoveRequested: Shortcuts.remove(appId)
                }
            }

            Rectangle {
                visible: !Shortcuts.atLimit
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                Layout.alignment: Qt.AlignHCenter

                radius: 10
                color: addArea.containsMouse ? Theme.hoverBgSoft : "transparent"
                border.width: addArea.containsMouse ? 1 : 0
                border.color: Theme.accentHover

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.width { NumberAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.pixelSize: 22
                    color: Theme.textDim
                }

                MouseArea {
                    id: addArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Shortcuts.openAddPicker()

                }
            }
        }
    }
}
