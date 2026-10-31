import QtQuick
import Qt5Compat.GraphicalEffects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../Services"
import "../Theme"
import "../Widgets"

// The shortcuts dock. Settings > Popups > Shortcuts palette decides
//   * placement  one of 8 spots (default: left edge, centred, flush: how it always looked).
//                Left / right (middle) = a vertical column; anything at the top or bottom
//                = a horizontal row.
//   * scale      with the other popups (Popups > General)
//   * trigger    keybind (qs ipc call shortcuts toggle) | hover zone | both
//
// Hover zone: a thin strip at the screen edge the dock hugs, as long as the dock, reveals it;
// it hides again shortly after the pointer leaves it (and the dock). A dock opened with the
// keybind in "both" mode stays until toggled, launched from or clicked away -- only a dock
// opened by hovering hides by itself.
PanelWindow {
    id: shortcutsWindow

    readonly property real uiScale: PopupSettings.scaleOf("shortcuts")
    readonly property string trigger: PopupSettings.shortcutsTrigger
    readonly property bool hoverEnabled: trigger !== "keybind"
    readonly property bool keybindEnabled: trigger !== "hover"
    readonly property string placement: PopupSettings.shortcutsPlacement
    readonly property string pV: placement.split("-")[0]     // top | center | bottom
    readonly property string pH: placement.split("-")[1]     // left | center | right
    // Row along the top / bottom edge, or column along the left / right edge.
    readonly property bool horizontal: pV !== "center"

    property bool menuOpen: false
    property bool openedByHover: false
    property real openProgress: 0
    // In hover mode the (transparent, input-masked) surface stays mapped so the zone can see the pointer.
    visible: menuOpen || openProgress > 0 || hoverEnabled

    screen: Quickshell.screens[0]

    // ---- keybind / IPC entry points (ignored while the trigger is "hover" only) ----
    function keybindToggle() {
        if (!keybindEnabled) return
            openedByHover = false
            menuOpen = !menuOpen
    }
    function keybindOpen() {
        if (!keybindEnabled) return
            openedByHover = false
            menuOpen = true
    }
    function keybindClose() { menuOpen = false }

    onMenuOpenChanged: {
        if (menuOpen) {
            closeAnim.stop()
            openAnim.restart()
        } else {
            openedByHover = false
            openAnim.stop()
            closeAnim.restart()
        }
    }
    onHoverEnabledChanged: { if (!hoverEnabled && openedByHover) menuOpen = false }

    // ---- hover reveal / autohide ----
    readonly property bool hovering: dockHover.hovered || zoneHover.hovered
    onHoveringChanged: {
        if (!hoverEnabled) return
            if (hovering) {
                hideTimer.stop()
                if (!menuOpen) { openedByHover = true; menuOpen = true }
            } else if (menuOpen && openedByHover) {
                hideTimer.restart()
            }
    }
    Timer {
        id: hideTimer
        interval: 450
        onTriggered: { if (!shortcutsWindow.hovering && shortcutsWindow.openedByHover) shortcutsWindow.menuOpen = false }
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
        function toggle(): void { shortcutsWindow.keybindToggle() }
        function open(): void { shortcutsWindow.keybindOpen() }
        function close(): void { shortcutsWindow.keybindClose() }
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

    // Full height always (the dock sits anywhere along it). A column on the left / right hugs that
    // side with a 260px-wide surface; a row (top / bottom placements) needs the whole width.
    anchors {
        top: true
        bottom: true
        left: horizontal || pH !== "right"
        right: horizontal || pH !== "left"
    }

    // Surface is much wider than the visible dock so both the hover-scaled
    // icons AND the tooltip text (which sits beside the dock) have
    // room to render without hitting the Wayland surface edge. Popups from
    // a layer-shell surface can't escape past its bounds, so the surface
    // itself has to be sized for the widest thing we'll ever draw in it.
    implicitWidth: 260 * uiScale
    color: "transparent"

    // Only the dock and the trigger zone take pointer input; the rest of the (transparent)
    // surface lets clicks through to whatever is underneath.
    // Plain rectangles in window pixels (the dock lives inside the scaled PopupScale, so its
    // base-size geometry is multiplied by the scale here instead of relying on item mapping).
    mask: Region {
        regions: [
            Region {
                x: dock.x * shortcutsWindow.uiScale
                y: dock.y * shortcutsWindow.uiScale
                width: dock.width * shortcutsWindow.uiScale
                height: dock.height * shortcutsWindow.uiScale
            },
            Region {
                x: zone.x * shortcutsWindow.uiScale
                y: zone.y * shortcutsWindow.uiScale
                width: zone.width * shortcutsWindow.uiScale
                height: zone.height * shortcutsWindow.uiScale
            }
        ]
    }

    PopupScale {
        anchors.fill: parent
        popupId: "shortcuts"

        // ---- trigger zone: a thin strip at the edge the dock hugs, as long as the dock ----
        Item {
            id: zone
            readonly property real thickness: 4
            readonly property bool on: shortcutsWindow.hoverEnabled
            readonly property bool horizontalStrip: shortcutsWindow.horizontal   // strip along the top / bottom edge
            width: !on ? 0 : (horizontalStrip ? dock.width : thickness)
            height: !on ? 0 : (horizontalStrip ? thickness : dock.height)
            x: horizontalStrip ? dock.baseX : (shortcutsWindow.pH === "left" ? 0 : parent.width - width)
            y: horizontalStrip ? (shortcutsWindow.pV === "top" ? 0 : parent.height - height) : dock.baseY

            HoverHandler { id: zoneHover; enabled: zone.on }
        }

        Rectangle {
            id: dock

            readonly property real gap: 12
            // flush against the screen edge only in the original spots (middle left / middle right)
            readonly property bool flushL: shortcutsWindow.placement === "center-left"
            readonly property bool flushR: shortcutsWindow.placement === "center-right"
            readonly property real p: shortcutsWindow.openProgress

            // 60px thick either way: the layout is one column or one row of 44px buttons + padding
            width: content.implicitWidth + 16
            height: content.implicitHeight + 16

            // resting position
            readonly property real baseX: shortcutsWindow.pH === "left" ? (flushL ? 0 : gap)
            : (shortcutsWindow.pH === "right" ? parent.width - width - (flushR ? 0 : gap)
            : (parent.width - width) / 2)
            readonly property real baseY: shortcutsWindow.pV === "top" ? gap
            : (shortcutsWindow.pV === "bottom" ? parent.height - height - gap
            : (parent.height - height) / 2)

            // slides in from the edge it sits on: columns from the side, rows from the top / bottom
            x: baseX + (shortcutsWindow.horizontal ? 0
            : (shortcutsWindow.pH === "left" ? -1 : 1) * (1 - p) * (width + 20))
            y: baseY + (shortcutsWindow.horizontal
            ? (shortcutsWindow.pV === "top" ? -1 : 1) * (1 - p) * (height + 20) : 0)

            property real blurAmount: Animations.blurEnvelope(shortcutsWindow.openProgress)
            * (shortcutsWindow.horizontal ? Animations.slideBlurVerticalLength : Animations.slideBlurHorizontalLength)

            // Only layered while blurAmount is actually large enough to see.
            layer.enabled: dock.blurAmount > 0.05
            layer.effect: DirectionalBlur {
                angle: shortcutsWindow.horizontal ? Animations.slideBlurVerticalAngle : Animations.slideBlurHorizontalAngle
                length: dock.blurAmount
                samples: Animations.slideBlurSamples
                transparentBorder: true
            }

            color: Theme.popupPaintBg
            border.width: 1
            border.color: Theme.borderMuted

            topLeftRadius: flushL ? 0 : PopupSettings.radiusOf("shortcuts")
            bottomLeftRadius: flushL ? 0 : PopupSettings.radiusOf("shortcuts")
            topRightRadius: flushR ? 0 : PopupSettings.radiusOf("shortcuts")
            bottomRightRadius: flushR ? 0 : PopupSettings.radiusOf("shortcuts")

            HoverHandler { id: dockHover; enabled: shortcutsWindow.hoverEnabled }

            // gradient / image of a custom theme (paints nothing for solid fills)
            ThemeFill {
                anchors.fill: parent
                fill: Theme.popupFill
                topLeftRadius: dock.topLeftRadius
                bottomLeftRadius: dock.bottomLeftRadius
                topRightRadius: dock.topRightRadius
                bottomRightRadius: dock.bottomRightRadius
            }
            // One column (columns: 1) or one row (columns > number of buttons).
            GridLayout {
                id: content
                anchors.fill: parent
                anchors.margins: 8
                rowSpacing: 8
                columnSpacing: 8
                columns: shortcutsWindow.horizontal ? 20 : 1

                Repeater {
                    model: Shortcuts.shortcuts

                    delegate: ShortcutButton {
                        required property var modelData

                        appName: modelData.name
                        appExec: modelData.exec
                        appIcon: modelData.icon
                        appId: modelData.id
                        tooltipSide: shortcutsWindow.horizontal
                        ? (shortcutsWindow.pV === "top" ? "below" : "above")
                        : (shortcutsWindow.pH === "right" ? "left" : "right")

                        onLaunchRequested: {
                            Shortcuts.launchShortcut(modelData)
                            shortcutsWindow.menuOpen = false
                        }
                        onRemoveRequested: Shortcuts.remove(appId)
                    }
                }

                Rectangle {
                    visible: !Shortcuts.atLimit
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    Layout.alignment: Qt.AlignCenter

                    radius: 10
                    color: addArea.containsMouse ? Theme.hoverBgSoft : "transparent"
                    border.width: addArea.containsMouse ? 1 : 0
                    border.color: Theme.accentHover

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.width { NumberAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        font.pixelSize: Theme.fs(22)
                        color: Theme.foreground
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
}
