import QtQuick
import QtQuick.Shapes
import "../Theme"
import "../Widgets"

// One decorative shape of a lock screen preset (Settings > Lock screen > Shapes).
//   rect       a rectangle; `spec.radius` rounds its corners (0 = square)
//   ellipse    an ellipse / circle
//   arrow      one-way or two-way, any of four directions; `shaft` and `head` set its proportions
//   star       `points` tips, `inner` = how deep the notches go
//   polygon    `sides` sides, inscribed in the box
// Filled: painted by the shape's theme fill (solid colour, gradient or pattern, see ThemeFill; arrows, stars and
// polygons draw solid and gradient fills, a pattern uses its average colour).
// Hollow: an outline `spec.stroke` px wide, in the fill's colour (a gradient / pattern outline uses the
// average colour of the fill).
// The size comes from the parent (width / height); `spec` is a layout shape object (LockPresets).
Item {
    id: root

    property var spec: ({})

    readonly property bool filled: root.spec.filled !== false
    readonly property var fill: Theme.resolveFill(root.spec.fill, Theme.effectiveDark, true)
    readonly property string kind: root.spec.kind || "rect"
    readonly property bool boxy: root.kind === "rect" || root.kind === "ellipse"
    readonly property real corner: root.kind === "ellipse" ? Math.min(width, height) / 2
    : Math.min(root.spec.radius || 0, Math.min(width, height) / 2)

    // ---- rectangle / ellipse ----
    Rectangle {
        visible: root.boxy
        anchors.fill: parent
        radius: root.corner
        color: (root.filled && root.fill.kind === "solid") ? root.fill.color : "transparent"
        border.width: root.filled ? 0 : Math.max(1, root.spec.stroke || 3)
        border.color: root.fill.avg

        ThemeFill {
            anchors.fill: parent
            visible: root.filled && root.boxy
            fill: root.fill
            radius: root.corner
        }
    }

    // ---- arrow / star / polygon: the outline as a list of points in the box ----
    function _poly(w, h) {
        const s = root.spec
        const P = function (x, y) { return Qt.point(x * w, y * h) }
        const out = []
        if (root.kind === "polygon") {
            const n = Math.max(3, Math.min(12, s.sides || 6))
            for (let i = 0; i < n; i++) {
                const a = -Math.PI / 2 + i * 2 * Math.PI / n
                out.push(P(0.5 + 0.5 * Math.cos(a), 0.5 + 0.5 * Math.sin(a)))
            }
        } else if (root.kind === "star") {
            const n = Math.max(3, Math.min(12, s.points || 5))
            const k = Math.max(0.2, Math.min(0.9, (s.inner || 45) / 100))
            for (let i = 0; i < n * 2; i++) {
                const a = -Math.PI / 2 + i * Math.PI / n
                const r = (i % 2 === 0) ? 0.5 : 0.5 * k
                out.push(P(0.5 + r * Math.cos(a), 0.5 + r * Math.sin(a)))
            }
        } else {                                  // arrow
            const shaft = Math.max(0.15, Math.min(0.8, (s.shaft || 40) / 100))
            const dir = s.arrowDir || "right"
            const vertical = dir === "up" || dir === "down"
            // drawn pointing right in a box of length L (along the arrow) and thickness T, then turned
            const L = vertical ? h : w, T = vertical ? w : h
            const head = Math.min(0.9, Math.max(0.15, (s.head || 35) / 100)) * Math.min(L, T * 2) / L
            const y0 = 0.5 - shaft / 2, y1 = 0.5 + shaft / 2
            let pts
            if (s.arrowDouble === true) {
                pts = [[head, 0], [0, 0.5], [head, 1], [head, y1], [1 - head, y1], [1 - head, 1], [1, 0.5], [1 - head, 0], [1 - head, y0], [head, y0]]
            } else {
                pts = [[0, y0], [1 - head, y0], [1 - head, 0], [1, 0.5], [1 - head, 1], [1 - head, y1], [0, y1]]
            }
            for (let i = 0; i < pts.length; i++) {
                let u = pts[i][0], v = pts[i][1]
                if (dir === "left") u = 1 - u
                    if (dir === "down") { const t = u; u = v; v = t }
                    else if (dir === "up") { const t = u; u = v; v = 1 - t }
                    out.push(P(u, v))
            }
        }
        out.push(out[0])                           // close it
        return out
    }
    readonly property var points: root.boxy ? [] : root._poly(root.width, root.height)

    function _gc(i) {
        const c = root.fill.colors
        if (!c || c.length === 0) return "transparent"
            const k = c[Math.min(i, c.length - 1)]
            return Qt.rgba(k.r, k.g, k.b, root.fill.opacity)
    }
    function _gp(i) {
        const n = root.fill.colors ? root.fill.colors.length : 0
        return n <= 1 ? (i === 0 ? 0 : 1) : (i < n ? i / (n - 1) : 1)
    }

    Shape {
        visible: !root.boxy
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: (root.filled && root.fill.kind === "solid") ? root.fill.color
            : ((root.filled && root.fill.kind === "pattern") ? root.fill.avg : "transparent")
            fillGradient: (root.filled && root.fill.kind === "gradient") ? lin : null
            strokeColor: root.filled ? "transparent" : root.fill.avg
            strokeWidth: root.filled ? -1 : Math.max(1, root.spec.stroke || 3)
            joinStyle: ShapePath.RoundJoin
            capStyle: ShapePath.RoundCap
            PathPolyline { path: root.points }
        }

        LinearGradient {
            id: lin
            x1: 0; y1: 0
            x2: root.fill.horizontal ? root.width : 0
            y2: root.fill.horizontal ? 0 : root.height
            GradientStop { position: root._gp(0); color: root._gc(0) }
            GradientStop { position: root._gp(1); color: root._gc(1) }
            GradientStop { position: root._gp(2); color: root._gc(2) }
            GradientStop { position: root._gp(3); color: root._gc(3) }
            GradientStop { position: root._gp(4); color: root._gc(4) }
            GradientStop { position: root._gp(5); color: root._gc(5) }
        }
    }
}
