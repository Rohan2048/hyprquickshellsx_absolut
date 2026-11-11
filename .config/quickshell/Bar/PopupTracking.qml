import QtQuick
import "../Services"

// Geometry of the bar in absolute screen coordinates, for any bar edge.
// Popups hang off it through PopupPlacement.
QtObject {
    id: tracking

    required property var bar
    required property var barClip
    property var content: null              // the bar's scaled content box (centred in the pill)

    readonly property string edge: bar.cfg.edge
    readonly property bool vertical: bar.cfg.vertical

    // popup mode "Merge & expand": popups sit flush against the bar and square their joined corners
    readonly property bool mergeOn: bar.cfg.popupMode === "merge"
    readonly property string joinSide: edge       // the popup side that touches the bar

    readonly property real screenW: bar.screen ? bar.screen.width : 0
    readonly property real screenH: bar.screen ? bar.screen.height : 0

    // Which window edges a popup must anchor to so it opens on the bar's side.
    // Horizontal bar: bar edge + left (x via left margin).
    // Vertical bar:   bar edge + top  (y via top margin).
    readonly property bool anchorTop: edge === "top" || vertical
    readonly property bool anchorBottom: edge === "bottom"
    readonly property bool anchorLeft: edge === "left" || !vertical
    readonly property bool anchorRight: edge === "right"

    // Direction (away from the bar) popups should slide from, for custom slide effects.
    readonly property real slideDirX: edge === "left" ? -1 : (edge === "right" ? 1 : 0)
    readonly property real slideDirY: edge === "top" ? -1 : (edge === "bottom" ? 1 : 0)

    // Distance from the screen edge to the bar's inner edge (its window's cross size).
    readonly property real barInnerOffset: bar.crossSize

    // Bar's visible glass panel along its main axis, absolute screen coords.
    // Merge & expand: the FINAL pill (where it is heading). Popups hang off a fixed reference, so their
    // window never moves while the pill eases. Otherwise the live pill, exactly as before.
    readonly property real barStart: mergeOn ? bar.windowMainStart + bar.mainPosFor(bar.targetVisualLength)
                                             : bar.windowMainStart + barClip.mainPos
    readonly property real barEnd: mergeOn ? barStart + bar.targetVisualLength
                                           : barStart + (vertical ? barClip.height : barClip.width)

    // Centre of `item` along the bar's main axis (x for horizontal, y for
    // vertical), absolute screen coords. Walks the parent chain reading x/y so
    // bindings stay live while the bar animates / scrolls / reorders. Each
    // ancestor's `scale` (the bar content is scaled about its centre) is
    // applied on the way up.
    // Merge & expand version of centerAlong(): where the item's centre will be once the pill has
    // finished growing. The content box is centred in the pill and scaled about its centre, so the item
    // is (its offset from the content's centre) x scale away from the FINAL pill centre. Nothing in it
    // changes while the pill eases.
    function centerAlongFinal(item) {
        if (!item || !content)
            return 0
        var c = (vertical ? item.height : item.width) / 2
        for (var it = item; it && it !== content; it = it.parent) {
            var o = (vertical ? it.height : it.width) / 2
            c = (vertical ? it.y : it.x) + o + (c - o) * it.scale
        }
        if (it !== content)                 // not inside the bar's content: fall back to the live centre
            return centerAlong(item)
        var half = (vertical ? content.height : content.width) / 2
        return barStart + bar.targetVisualLength / 2 + (c - half) * bar.sc
    }

    function centerAlong(item) {
        if (!item || !bar.contentItem)
            return 0
            var c = (vertical ? item.height : item.width) / 2
            for (var it = item; it && it !== bar.contentItem; it = it.parent) {
                var o = (vertical ? it.height : it.width) / 2
                c = (vertical ? it.y : it.x) + o + (c - o) * it.scale
            }
            return bar.windowMainStart + c
    }
}
