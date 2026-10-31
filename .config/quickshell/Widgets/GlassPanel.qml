import QtQuick
import "../Theme"
import "../Services"
// GlassPanel — direct port of .popup-box:
//   background-color: rgba(0,0,0,0.35); border: 1px solid $color8; border-radius: 12px;
// (the border itself is Widgets/PanelBorder.qml, controlled by Services/BorderSettings)
// The actual frosted blur is compositor-side (Hyprland/niri layerrule on this
// surface's namespace) — same as your eww setup, this just draws the fill/border.
//
// The fill comes from the active theme: the built-in Transparent blur / Opaque
// colour, or a custom theme's solid colour, gradient or image (Settings > Theme).
Rectangle {
    id: panel

    // "popup" (default) or "bar": a custom theme has a separate fill for each.
    property string role: "popup"
    // A resolved fill (Theme.resolveFill) to draw instead of the active theme's.
    // Used by the theme preview.
    property var themeFill: null
    // -1 = the fill's own alpha. 0..1 replaces the alpha of a SOLID fill
    // (notification cards); gradients / images keep their own opacity.
    property real alphaOverride: -1
    // true = draw nothing of its own (no fill, no border): a transparent bar
    property bool bare: false
    // false = draw no border of Settings > Theme > Border at all (the Theme tiles: a wall of animated borders
    // is noisy, and the flashing effects would be hard on the eyes)
    property bool showBorder: true
    // false = no anime streaks on this panel's border (a hidden autohide bar)
    property bool animeAllowed: true

    readonly property var fill: panel.themeFill !== null
    ? panel.themeFill
    : (panel.role === "bar" ? Theme.barPanelFill : Theme.popupFill)

    // --- Bar preset popup mode "Merge & expand" ---
    // A bar popup passes its `tracking` (Bar/PopupTracking.qml). When the bar it hangs off is set to
    // Merge & expand, the two corners on the side that touches the bar are squared, so popup and
    // bar read as one shape. Anything that does not pass `tracking` is left alone.
    property var tracking: null
    readonly property string joinSide: (panel.role === "popup" && panel.tracking && panel.tracking.mergeOn)
    ? panel.tracking.joinSide : ""
    // Settings > Theme > Border can give every panel the same corner radius
    readonly property real cornerR: BorderSettings.radiusFor(radius)
    topLeftRadius: (joinSide === "top" || joinSide === "left") ? 0 : cornerR
    topRightRadius: (joinSide === "top" || joinSide === "right") ? 0 : cornerR
    bottomLeftRadius: (joinSide === "bottom" || joinSide === "left") ? 0 : cornerR
    bottomRightRadius: (joinSide === "bottom" || joinSide === "right") ? 0 : cornerR

    radius: Theme.radiusMd
    color: panel.bare || panel.fill.kind !== "solid"
    ? "transparent"
    : (panel.alphaOverride >= 0
    ? Qt.rgba(panel.fill.color.r, panel.fill.color.g, panel.fill.color.b, panel.alphaOverride)
    : panel.fill.color)
    // the border is drawn by PanelBorder below (Settings > Theme > Border: on / off, thickness, colour, effects)

    ThemeFill {
        anchors.fill: parent
        visible: !panel.bare
        fill: panel.fill
        radius: panel.radius
        topLeftRadius: panel.topLeftRadius
        topRightRadius: panel.topRightRadius
        bottomLeftRadius: panel.bottomLeftRadius
        bottomRightRadius: panel.bottomRightRadius
    }

    PanelBorder {
        shown: !panel.bare && panel.showBorder
        animeAllowed: panel.animeAllowed
        tl: panel.topLeftRadius
        tr: panel.topRightRadius
        bl: panel.bottomLeftRadius
        br: panel.bottomRightRadius
    }
}
