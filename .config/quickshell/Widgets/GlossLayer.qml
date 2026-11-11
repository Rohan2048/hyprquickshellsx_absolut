import QtQuick
import QtQuick.Shapes
import "../Theme"

// GlossLayer -- the "Glossy" type of Settings > Theme > Type (liquid glass).
//
// Drawn by GlassPanel on top of the panel's fill, under the border. It never touches the fill or its
// opacity: the translucency (and so the compositor blur behind the panel) stays exactly as it was, this
// only adds the optics of a thick pane of glass lit from the top-left:
//
//   rim        a thin bright edge, brightest at the lit corner (top-left) and at the opposite
//              corner where the light leaves the pane, dim in between
//   bevel      a soft band just inside the rim: the glass thickening toward its edge, where a lens
//              bends the light the most
//   dispersion two 1px fringes just inside the rim, warm on the lit side and cool on the far side:
//              the colour split a real refracting edge shows
//   sheen      a specular reflection over the top of the pane
//   caustic    light gathering along the bottom edge
//
// Pure vector drawing (rounded rectangles and one Shape): no shaders, no textures, no offscreen layers.
// A shell panel is a separate layer-shell surface and QML cannot sample the wallpaper behind it, so the
// refraction here is the edge optics of the glass itself, not a distortion of what lies behind it.
Item {
    id: g

    // the panel's four corner radii (a popup merged into the bar has two square corners)
    property real tl: 12
    property real tr: 12
    property real bl: 12
    property real br: 12

    readonly property bool dark: Theme.effectiveDark
    // white light is hard to see on a light panel: lift it a little there
    readonly property real k: g.dark ? 1.0 : 1.25
    readonly property real w: g.width
    readonly property real h: g.height

    anchors.fill: parent

    function _white(a) { return Qt.rgba(1, 1, 1, Math.min(1, a * g.k)) }
    function _m(r, inset) { return Math.max(0, Math.min(r - inset, (Math.min(g.w, g.h) - 2 * inset) / 2)) }

    function rr(x, y, w, h, a, c, d, e) {   // a tl, c tr, d br, e bl
        return "M " + (x + a) + " " + y + " H " + (x + w - c)
        + " A " + c + " " + c + " 0 0 1 " + (x + w) + " " + (y + c)
        + " V " + (y + h - d) + " A " + d + " " + d + " 0 0 1 " + (x + w - d) + " " + (y + h)
        + " H " + (x + e) + " A " + e + " " + e + " 0 0 1 " + x + " " + (y + h - e)
        + " V " + (y + a) + " A " + a + " " + a + " 0 0 1 " + (x + a) + " " + y + " Z "
    }
    // a ring `t` thick whose outer edge sits `inset` inside the panel
    function ring(inset, t) {
        const i2 = inset + t
        if (g.w < 2 * i2 + 1 || g.h < 2 * i2 + 1) return ""
            return g.rr(inset, inset, g.w - 2 * inset, g.h - 2 * inset, g._m(g.tl, inset), g._m(g.tr, inset), g._m(g.br, inset), g._m(g.bl, inset))
            + g.rr(i2, i2, g.w - 2 * i2, g.h - 2 * i2, g._m(g.tl, i2), g._m(g.tr, i2), g._m(g.br, i2), g._m(g.bl, i2))
    }

    // ---- sheen: the specular reflection across the top of the pane ----
    Rectangle {
        x: 1.5; y: 1.5
        width: g.w - 3
        height: Math.min(g.h * 0.5, 90)
        topLeftRadius: Math.max(0, g.tl - 1.5)
        topRightRadius: Math.max(0, g.tr - 1.5)
        bottomLeftRadius: 0
        bottomRightRadius: 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: g._white(0.24) }
            GradientStop { position: 0.45; color: g._white(0.07) }
            GradientStop { position: 1.0; color: g._white(0.0) }
        }
    }

    // ---- caustic: light collecting along the bottom edge ----
    Rectangle {
        x: 1.5
        width: g.w - 3
        height: Math.min(g.h * 0.3, 40)
        y: g.h - height - 1.5
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: Math.max(0, g.bl - 1.5)
        bottomRightRadius: Math.max(0, g.br - 1.5)
        gradient: Gradient {
            GradientStop { position: 0.0; color: g._white(0.0) }
            GradientStop { position: 1.0; color: g._white(0.10) }
        }
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        asynchronous: true

        // bevel: the glass thickening toward its edge
        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: g.w; y2: g.h
                GradientStop { position: 0.0; color: g._white(0.16) }
                GradientStop { position: 0.5; color: g._white(0.03) }
                GradientStop { position: 1.0; color: g._white(0.12) }
            }
            PathSvg { path: g.ring(3.5, 5) }
        }

        // inner shadow line: gives the pane its thickness
        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillColor: g.dark ? Qt.rgba(0, 0, 0, 0.14) : Qt.rgba(0, 0, 0, 0.07)
            PathSvg { path: g.ring(8.5, 1.5) }
        }

        // dispersion: warm fringe on the lit side ...
        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: g.w; y2: g.h
                GradientStop { position: 0.0; color: Qt.rgba(1.0, 0.72, 0.45, 0.34) }
                GradientStop { position: 0.45; color: Qt.rgba(1.0, 0.72, 0.45, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(1.0, 0.72, 0.45, 0.0) }
            }
            PathSvg { path: g.ring(1.5, 1) }
        }
        // ... cool fringe on the far side
        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: g.w; y2: g.h
                GradientStop { position: 0.0; color: Qt.rgba(0.45, 0.75, 1.0, 0.0) }
                GradientStop { position: 0.55; color: Qt.rgba(0.45, 0.75, 1.0, 0.0) }
                GradientStop { position: 1.0; color: Qt.rgba(0.45, 0.75, 1.0, 0.34) }
            }
            PathSvg { path: g.ring(2.5, 1) }
        }

        // rim: the bright edge, brightest where the light enters and leaves
        ShapePath {
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            fillGradient: LinearGradient {
                x1: 0; y1: 0; x2: g.w; y2: g.h
                GradientStop { position: 0.0; color: g._white(0.85) }
                GradientStop { position: 0.28; color: g._white(0.30) }
                GradientStop { position: 0.55; color: g._white(0.08) }
                GradientStop { position: 0.8; color: g._white(0.30) }
                GradientStop { position: 1.0; color: g._white(0.65) }
            }
            PathSvg { path: g.ring(0, 1.5) }
        }
    }
}
