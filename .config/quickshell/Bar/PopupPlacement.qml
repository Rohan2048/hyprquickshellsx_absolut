import QtQuick

// Computes the anchor margins for one popup window so it opens next to the
// bar (on whichever edge the bar is on), centred on `anchorItem`.
QtObject {
    id: place

    required property var tracking
    required property var popup           // the PanelWindow
    property var anchorItem: null         // bar item to hang off (null = bar centre)
    property real centerOverride: -1      // >=0 pins the centre (used by locked thumbnails/menus)
    property real overhang: tracking.mergeOn ? 0 : 5   // max px past the bar's ends
    property real gap: tracking.mergeOn ? 0 : 3        // px between bar and popup (0 = merged)
    property bool clampToBar: true
    property bool smooth: false           // false = follow the anchor synchronously without trailing lag

    readonly property bool vertical: tracking.vertical
    readonly property real size: vertical ? popup.implicitHeight : popup.implicitWidth

    readonly property real iconCenter: {
        if (centerOverride >= 0) return centerOverride
            if (anchorItem) return tracking.mergeOn ? tracking.centerAlongFinal(anchorItem) : tracking.centerAlong(anchorItem)
                return (tracking.barStart + tracking.barEnd) / 2
    }

    readonly property real along: {
        var screenLen = vertical ? tracking.screenH : tracking.screenW
        var d = iconCenter - size / 2
        if (clampToBar) {
            var a = tracking.barStart - overhang
            var b = tracking.barEnd + overhang - size
            d = Math.min(Math.max(Math.min(a, b), d), Math.max(a, b))
        }
        return Math.max(0, Math.min(d, Math.max(0, screenLen - size)))
    }

    property real smoothedAlong: along
    Behavior on smoothedAlong { enabled: place.smooth; NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
    readonly property real pos: smooth ? smoothedAlong : along

    readonly property real offset: tracking.barInnerOffset + gap

    readonly property real marginTop: tracking.edge === "top" ? offset : (vertical ? pos : 0)
    readonly property real marginBottom: tracking.edge === "bottom" ? offset : 0
    readonly property real marginLeft: tracking.edge === "left" ? offset : (vertical ? 0 : pos)
    readonly property real marginRight: tracking.edge === "right" ? offset : 0
}
