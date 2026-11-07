import QtQuick
import "../Theme"
import "../Services"

// The settings of ONE bar window. Every bar module reads its geometry from the bar's config
// instead of the BarSettings singleton, so several bars can run side by side:
//   cid "default"  -> mirrors BarSettings (the classic single bar, unchanged behaviour)
//   other ids      -> the mini bar with that id in the active (or previewed) preset
// Properties are bound to the live data, so editing a preset updates the open window in place.
QtObject {
    id: cfg

    property string cid: "default"
    readonly property var d: cfg.cid === "default" ? null : BarPresets.barData(cfg.cid)
    readonly property bool legacy: cfg.d === null || cfg.d === undefined

    readonly property string edge: legacy ? BarSettings.edge : d.edge
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property bool autohide: legacy ? BarSettings.autohide : d.autohide
    // "fill" = edge to edge. The classic bar is always edge to edge while docked.
    readonly property string sizeMode: legacy ? ((BarSettings.fillScreen || !BarSettings.autohide) ? "fill" : "fit") : d.sizeMode
    readonly property real lengthPx: legacy ? 0 : d.lengthPx
    readonly property string align: legacy ? "center" : d.align
    readonly property real offset: legacy ? 0 : d.offset
    readonly property int scalePct: legacy ? BarSettings.scalePct : d.scalePct
    readonly property real scale: scalePct / 100
    readonly property int roundnessPct: legacy ? BarSettings.roundnessPct : d.roundnessPct
    readonly property string bg: legacy ? "theme" : d.bg
    readonly property string popupMode: legacy ? "float" : d.popupMode
    readonly property var order: legacy ? BarSettings.order : d.modules
    // free layout (px per module from the content start), or null when the icons flow
    readonly property var places: legacy ? null : (d.places === undefined ? null : d.places)
    // Cross-axis size at 100% (same numbers as BarSettings.thickness)
    readonly property real thickness: vertical ? 48 : Theme.barHeight
    // does this bar reserve screen space (docked) or is it the one that reserves on its edge?
    readonly property bool reserves: legacy ? !autohide : (!autohide && BarPresets.reserverId(edge) === cid)
    // group reveal only matters when there are several bars
    readonly property bool grouped: !legacy
}
