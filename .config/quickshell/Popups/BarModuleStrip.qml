import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import "../Theme"
import "../Services"
import "../Widgets"

// Settings > Bar > Presets: the modules of ONE mini bar as a strip of tiles you drag around.
//
//   modules   ids in bar order
//   arranged(order)   emitted on drop, with the new order
//
// Rules
//   - drag a tile anywhere along the strip. It can go BETWEEN icons or into the free space after
//     the last one, but never on top of one: if it overlaps another icon it turns translucent red
//     (a tint of the same size as the tile) and, when you let go, it is placed at the nearest valid
//     place (the gap it is closest to).
//   - the thin marker shows the gap it will land in.
//   - the "+ Add" chips can be dragged in too (beginExternal / updateExternal / endExternal): dropped
//     over free space or between icons they are inserted there; dropped away from the strip they are
//     cancelled (a plain click on a chip still appends it).
//
// Nothing is reflowed while dragging: the other tiles stay where they are, the dragged one just
// follows the pointer, and the order is only committed on release (one change, no per-move work).
Item {
    id: strip

    property var modules: []
    signal arranged(var order)

    readonly property string dir: "file://" + Quickshell.env("HOME") + "/.config/icons/"

    // ---- geometry (a fixed-size stand-in for the bar, like the Icon order strip) ----
    readonly property real pad: 8
    readonly property real gap: 6
    readonly property int n: strip.modules.length
    readonly property real tile: Math.max(20, Math.min(38, (strip.width - strip.pad * 2 - strip.gap * (strip.n + 1)) / (strip.n + 1)))
    readonly property real pitch: strip.tile + strip.gap
    readonly property real barH: 58

    implicitHeight: strip.barH + 20

    // ---- drag state ----
    property string dragId: ""
    property bool external: false
    property real dragCx: 0            // centre of the dragged tile along the strip
    property real dragY: 0             // pointer y (only used by drags from the Add chips)
    property bool overStrip: true
    property string hoverId: ""

    function _clampCx(cx) { return Math.max(strip.pad + strip.tile / 2, Math.min(strip.width - strip.pad - strip.tile / 2, cx)) }

    // overlap with any OTHER tile (they keep their places while you drag)
    readonly property bool invalid: {
        if (strip.dragId === "" || !strip.overStrip) return false
            var l = strip.dragCx - strip.tile / 2
            var r = strip.dragCx + strip.tile / 2
            for (var k = 0; k < strip.modules.length; k++) {
                if (strip.modules[k] === strip.dragId) continue
                    var tl = strip.pad + k * strip.pitch
                    if (Math.min(r, tl + strip.tile) - Math.max(l, tl) > strip.tile * 0.65) return true
            }
            return false
    }

    // the gap it is nearest to = how many of the other tiles sit left of it
    readonly property int gapIndex: {
        if (strip.dragId === "") return 0
            var c = 0
            for (var k = 0; k < strip.modules.length; k++) {
                if (strip.modules[k] === strip.dragId) continue
                    if (strip.pad + k * strip.pitch + strip.tile / 2 < strip.dragCx) c++
            }
            return c
    }

    // x of the landing marker
    readonly property real markerX: {
        var xs = []
        for (var k = 0; k < strip.modules.length; k++)
            if (strip.modules[k] !== strip.dragId) xs.push(strip.pad + k * strip.pitch)
                var j = strip.gapIndex
                if (xs.length === 0) return strip.pad - strip.gap / 2
                    if (j <= 0) return xs[0] - strip.gap / 2
                        if (j >= xs.length) return xs[xs.length - 1] + strip.tile + strip.gap / 2
                            return (xs[j - 1] + strip.tile + xs[j]) / 2
    }

    function beginInternal(id, cx) {
        strip.external = false
        strip.overStrip = true
        strip.dragId = id
        strip.dragCx = strip._clampCx(cx)
    }
    function moveInternal(cx) { strip.dragCx = strip._clampCx(cx) }

    // drags that start on an "+ Add" chip; `sp` is a scene position
    function beginExternal(id, sp) {
        strip.external = true
        strip.dragId = id
        strip.updateExternal(sp)
    }
    function updateExternal(sp) {
        var p = strip.mapFromItem(null, sp.x, sp.y)
        strip.dragCx = strip._clampCx(p.x)
        strip.dragY = p.y
        strip.overStrip = p.x > -strip.tile && p.x < strip.width + strip.tile && p.y > -strip.tile && p.y < strip.barH + strip.tile
    }
    function endExternal(sp) {
        strip.updateExternal(sp)
        strip.endDrag()
    }

    function endDrag() {
        if (strip.dragId === "") return
            var id = strip.dragId
            var ext = strip.external
            var ok = strip.overStrip
            var j = strip.gapIndex
            strip.dragId = ""
            strip.external = false
            if (ext && !ok) return                          // an Add chip dropped away from the strip
                var base = strip.modules.filter(function (m) { return m !== id })
                base.splice(Math.max(0, Math.min(j, base.length)), 0, id)
                if (JSON.stringify(base) !== JSON.stringify(strip.modules)) strip.arranged(base)
    }

    // ---- what a tile shows ----
    function iconFile(id) {
        switch (id) {
            case "power": return "power-btn.svg"
            case "wifi": return "wifion.svg"
            case "bluetooth": return "bluetooth-icon.svg"
            case "volume": return "sound.svg"
            case "battery": return "high-battery.svg"
            case "bell": return "bell.svg"
            case "settings": return "settings.svg"
        }
        return ""
    }
    function textFor(id) {
        switch (id) {
            case "music": return "♪"
            case "clock": return "12:00"
            case "stopwatch": return "00:00"
            case "timer": return "05:00"
            case "launcher": return "App"
            case "lock": return "Lck"
            case "commands": return "Cmd"
            case "shortcuts": return "Key"
            case "overview": return "Ovw"
            case "display": return "Dsp"
            case "schedule": return "Sch"
            case "workspaces": return "0-9"
        }
        return ""
    }

    component Glyph: Item {
        id: g
        property string tid: ""
        property string iconFile: ""
        property string label: ""
        property string dir: ""
        Image {
            visible: g.iconFile !== ""
            anchors.centerIn: parent
            source: g.iconFile !== "" ? g.dir + g.iconFile : ""
            width: Math.min(18, g.width - 8)
            height: width
            sourceSize.width: Math.round(18 * Screen.devicePixelRatio)
            sourceSize.height: Math.round(18 * Screen.devicePixelRatio)
            smooth: true
            layer.enabled: visible
            layer.smooth: true
            layer.effect: ColorOverlay { color: Theme.iconColor }
        }
        Rectangle {
            visible: g.label !== ""
            anchors.centerIn: parent
            width: Math.min(g.width - 2, lbl.implicitWidth + 8)
            height: lbl.implicitHeight + 6
            radius: height / 2
            color: "transparent"
            border.width: g.tid === "timer" ? 1 : 0
            border.color: Theme.foreground
            Text {
                id: lbl
                anchors.centerIn: parent
                text: g.label
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.bold: true
                font.pixelSize: g.tid === "music" ? Theme.fontSizeLg : 9
            }
        }
        Grid {
            visible: g.tid === "apps"
            anchors.centerIn: parent
            columns: 2
            spacing: 3
            Repeater {
                model: 4
                delegate: Rectangle { width: 8; height: 8; radius: 2; color: Theme.foreground; opacity: 0.6 }
            }
        }
    }

    // ---- the bar stand-in ----
    GlassPanel {
        role: "bar"
        x: 0
        y: 0
        width: parent.width
        height: strip.barH
        radius: height / 2
    }

    // free space after the last icon (shown while something is being dragged)
    Rectangle {
        x: strip.pad + strip.modules.length * strip.pitch
        y: (strip.barH - strip.tile) / 2
        width: Math.max(0, strip.width - strip.pad - x)
        height: strip.tile
        radius: Theme.radiusSm
        color: Theme.hoverBg
        opacity: strip.dragId !== "" ? 0.5 : 0
        visible: width > 8
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Text {
            anchors.centerIn: parent
            visible: parent.width > 70
            text: "free space"
            color: Theme.foreground
            opacity: 0.6
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
        }
    }

    // where it will land
    Rectangle {
        visible: strip.dragId !== "" && strip.overStrip
        x: strip.markerX - width / 2
        y: (strip.barH - height) / 2
        width: 2
        height: strip.tile + 10
        radius: 1
        color: strip.invalid ? Qt.rgba(1, 0.3, 0.3, 0.9) : Theme.accentActive
        z: 5
    }

    // ---- tiles ----
    // the model only changes when a module is added or removed (not when they are reordered), so a
    // reorder just slides the tiles instead of rebuilding them
    property var _ids: []
    onModulesChanged: {
        var s = strip.modules.slice().sort()
        if (JSON.stringify(s) !== JSON.stringify(strip._ids)) strip._ids = s
    }
    Component.onCompleted: strip._ids = strip.modules.slice().sort()

    Repeater {
        model: strip._ids
        delegate: Rectangle {
            id: t
            required property string modelData
            readonly property int slot: strip.modules.indexOf(t.modelData)
            readonly property bool dragging: strip.dragId === t.modelData && !strip.external

            width: strip.tile
            height: strip.tile
            y: (strip.barH - height) / 2
            x: t.dragging ? strip.dragCx - width / 2 : strip.pad + Math.max(0, t.slot) * strip.pitch
            z: t.dragging ? 10 : 1
            radius: Theme.radiusSm
            scale: t.dragging ? 1.08 : 1
            color: t.dragging ? Theme.hoverBgStrong : (strip.hoverId === t.modelData ? Theme.hoverBg : "transparent")
            border.width: t.dragging ? 1 : 0
            border.color: strip.invalid && t.dragging ? Qt.rgba(1, 0.3, 0.3, 0.9) : Theme.accentActive

            Behavior on x { enabled: !t.dragging; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120 } }

            Glyph {
                anchors.fill: parent
                tid: t.modelData
                iconFile: strip.iconFile(t.modelData)
                label: strip.textFor(t.modelData)
                dir: strip.dir
            }

            // invalid: a translucent red tint, the same size as the tile (not a separate layer)
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Qt.rgba(1, 0.15, 0.15, 0.42)
                visible: t.dragging && strip.invalid
            }

            MouseArea {
                anchors.fill: parent
                preventStealing: true
                hoverEnabled: true
                cursorShape: t.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real grab: 0
                onEntered: strip.hoverId = t.modelData
                onExited: { if (strip.hoverId === t.modelData) strip.hoverId = "" }
                onPressed: (m) => {
                    grab = m.x - t.width / 2
                    strip.beginInternal(t.modelData, mapToItem(strip, m.x, m.y).x - grab)
                }
                onPositionChanged: (m) => {
                    if (!pressed || strip.dragId !== t.modelData) return
                        strip.moveInternal(mapToItem(strip, m.x, m.y).x - grab)
                }
                onReleased: strip.endDrag()
                onCanceled: strip.endDrag()
            }
        }
    }

    // a module being dragged in from the "+ Add" chips
    Rectangle {
        id: proxy
        visible: strip.dragId !== "" && strip.external
        width: strip.tile
        height: strip.tile
        x: strip.dragCx - width / 2
        y: strip.overStrip ? (strip.barH - height) / 2 : strip.dragY - height / 2
        z: 20
        radius: Theme.radiusSm
        scale: 1.08
        color: Theme.hoverBgStrong
        border.width: 1
        border.color: strip.invalid ? Qt.rgba(1, 0.3, 0.3, 0.9) : Theme.accentActive
        opacity: strip.overStrip ? 1 : 0.6
        Glyph {
            anchors.fill: parent
            tid: strip.dragId
            iconFile: strip.iconFile(strip.dragId)
            label: strip.textFor(strip.dragId)
            dir: strip.dir
        }
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Qt.rgba(1, 0.15, 0.15, 0.42)
            visible: strip.invalid
        }
    }

    // name of the hovered / dragged module (fixed height so nothing jumps)
    Text {
        x: 4
        y: strip.barH + 4
        width: parent.width - 8
        readonly property string shown: strip.dragId !== "" ? strip.dragId : strip.hoverId
        text: shown === "" ? " " : (BarPresets.moduleNames[shown] || shown)
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        elide: Text.ElideRight
    }
}
