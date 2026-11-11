import QtQuick
import Qt5Compat.GraphicalEffects
import "../Services"
import "../Theme"

// One customisable icon (see Services/IconSettings.qml), drawn the way the bar draws it:
// the chosen file for `iconId` (else the built-in), Monochromized or tinted with the
// theme's icon colour. Used by the bar's battery and by the Icons settings page so both
// look identical.
//
// Crisp rendering (same recipe as ControlIcon): the SVG is rasterised at the real pixel size
// (never below 2x), and the colour layer gets a texture of that size too. Without
// layer.textureSize the tint layer is only item-sized and gets stretched = pixelated.
Item {
    id: root

    property string iconId: ""
    property real size: 20
    // Built-in file; empty = the slot's default from IconSettings.
    property url fallback: ""
    // Draw as if the shell were in dark / light mode (the Icons page preview).
    property bool dark: Theme.effectiveDark
    property bool asynchronous: false

    readonly property url builtin: root.fallback.toString() !== "" ? root.fallback : IconSettings.defaultUrl(root.iconId)
    readonly property url src: IconSettings.source(root.iconId, root.builtin)
    readonly property bool custom: IconSettings.customPath(root.iconId) !== ""
    readonly property bool mono: IconSettings.isMono(root.iconId)
    // Text colour of the active theme in the previewed mode (only used when `dark` is not the real mode).
    readonly property color otherTint: {
        const t = Theme.customActive
            ? Theme.resolveText(Theme.activeTheme.text, root.dark, Theme.activeTheme.adapt !== false) : null
        return t !== null ? t : (root.dark ? Theme.palette.foreground : "#1a1625")
    }
    readonly property real px: Math.round(root.size * Math.max(2, Screen.devicePixelRatio))

    implicitWidth: root.size
    implicitHeight: root.size
    width: root.size
    height: root.size

    Image {
        anchors.fill: parent
        visible: root.src.toString().length > 0
        source: root.src
        sourceSize: Qt.size(root.px, root.px)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: root.asynchronous

        // Monochromize: flat white (dark) / black (light). Otherwise a built-in icon is tinted
        // with the theme's icon colour, and a custom image keeps its own colours.
        layer.enabled: visible && (root.mono || !root.custom)
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: Qt.size(root.px, root.px)
        layer.effect: ColorOverlay {
            color: root.mono ? (root.dark ? "#ffffff" : "#000000")
                 : (root.dark === Theme.effectiveDark ? Theme.iconColor : root.otherTint)
        }
    }
}
