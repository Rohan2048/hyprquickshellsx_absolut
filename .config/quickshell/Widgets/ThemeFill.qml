import QtQuick
import QtQuick.Effects
import Quickshell
import "../Theme"

// Paints a resolved theme fill (Theme.resolveFill / Theme.popupFill) on top of
// whatever it sits in: a gradient (up to 6 colours) or a user image. A solid
// fill paints nothing here (the parent Rectangle draws solids itself), so this
// item is hidden for it.
//
// Used by GlassPanel, and directly by the few popups that draw their own
// Rectangle: give that Rectangle `color: Theme.popupPaintBg` and add
//     ThemeFill { anchors.fill: parent; fill: Theme.popupFill; radius: parent.radius }
Item {
    id: root

    property var fill: null
    property real radius: 0
    // -1 = use `radius`
    property real topLeftRadius: -1
    property real topRightRadius: -1
    property real bottomLeftRadius: -1
    property real bottomRightRadius: -1

    readonly property string kind: (fill && fill.kind) ? fill.kind : "solid"
    // longest side, in device pixels, of the biggest screen (decode cap for the image fill below)
    readonly property int _capPx: {
        let m = 1920
        const sc = Quickshell.screens
        for (let i = 0; i < sc.length; i++)
            m = Math.max(m, sc[i].width * sc[i].devicePixelRatio, sc[i].height * sc[i].devicePixelRatio)
            return Math.ceil(m)
    }
    visible: kind !== "solid"

    // Gradient stops: a fixed pool of 6. Stop i of n sits at i/(n-1); unused
    // stops pile up at 1.0 with the last colour, which is visually identical.
    function _n() { return (fill && fill.colors) ? fill.colors.length : 0 }
    function _c(i) {
        const n = root._n()
        return n === 0 ? "transparent" : fill.colors[Math.min(i, n - 1)]
    }
    function _p(i) {
        const n = root._n()
        return (n <= 1) ? (i === 0 ? 0 : 1) : (i < n ? i / (n - 1) : 1)
    }

    function _r(corner) { return corner >= 0 ? corner : root.radius }

    // ---------------- gradient ----------------
    Rectangle {
        anchors.fill: parent
        visible: root.kind === "gradient"
        opacity: root.fill ? root.fill.opacity : 1
        radius: root.radius
        topLeftRadius: root.topLeftRadius >= 0 ? root.topLeftRadius : root.radius
        topRightRadius: root.topRightRadius >= 0 ? root.topRightRadius : root.radius
        bottomLeftRadius: root.bottomLeftRadius >= 0 ? root.bottomLeftRadius : root.radius
        bottomRightRadius: root.bottomRightRadius >= 0 ? root.bottomRightRadius : root.radius

        gradient: Gradient {
            orientation: (root.fill && root.fill.horizontal) ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: root._p(0); color: root._c(0) }
            GradientStop { position: root._p(1); color: root._c(1) }
            GradientStop { position: root._p(2); color: root._c(2) }
            GradientStop { position: root._p(3); color: root._c(3) }
            GradientStop { position: root._p(4); color: root._c(4) }
            GradientStop { position: root._p(5); color: root._c(5) }
        }
    }

    // ---------------- pattern (image) ----------------
    // The image, its colour tint and the brightness shade live in one item that
    // is rendered to a texture and cut to the rounded shape by the mask below.
    Item {
        id: pattern
        anchors.fill: parent
        visible: root.kind === "pattern"
        opacity: root.fill ? root.fill.opacity : 1
        layer.enabled: root.kind === "pattern" && width > 0 && height > 0
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: patternMask
            // keep the mask's own anti-aliased edge (a hard 0.5 threshold made the corners jagged)
            maskThresholdMin: 0.0
            maskSpreadAtMin: 0.0
        }

        // Shown while the image loads, or if the file is gone / unreadable.
        Rectangle {
            anchors.fill: parent
            visible: img.status !== Image.Ready
            color: root.fill && root.fill.avg ? Qt.rgba(root.fill.avg.r, root.fill.avg.g, root.fill.avg.b, 1) : "transparent"
        }

        Image {
            id: img
            anchors.fill: parent
            // Only decoded while this fill really is an image: a saved theme keeps its image path when it is
            // switched to a gradient / solid, and the hidden image used to be decoded at full size anyway.
            // The decode is capped at the biggest screen's pixel size (never upscaled, so a smaller image is
            // untouched; a tiled image keeps its natural size), which is as sharp as it can ever be drawn.
            source: (root.kind === "pattern" && root.fill && root.fill.image && root.fill.image !== "") ? "file://" + root.fill.image : ""
            sourceSize: (root.fill && root.fill.tile) ? Qt.size(0, 0) : Qt.size(root._capPx, root._capPx)
            fillMode: (root.fill && root.fill.tile) ? Image.Tile : Image.PreserveAspectCrop
            horizontalAlignment: Image.AlignHCenter
            verticalAlignment: Image.AlignVCenter
            asynchronous: true
            smooth: true
            cache: true
        }

        // colour tint
        Rectangle {
            anchors.fill: parent
            visible: !!(root.fill && root.fill.tintAmt > 0)
            color: root.fill && root.fill.tint
            ? Qt.rgba(root.fill.tint.r, root.fill.tint.g, root.fill.tint.b, root.fill.tintAmt)
            : "transparent"
        }

        // brightness: black (darker) or white (lighter) laid over the image
        Rectangle {
            anchors.fill: parent
            visible: !!(root.fill && root.fill.shade && root.fill.shade.a > 0)
            color: root.fill && root.fill.shade ? root.fill.shade : "transparent"
        }
    }

    Item {
        id: patternMask
        anchors.fill: parent
        visible: false
        layer.enabled: root.kind === "pattern"
        layer.smooth: true
        layer.samples: 4          // multisampled once, so the rounded corners are smooth (static: not redrawn while scrolling)

        Rectangle {
            anchors.fill: parent
            antialiasing: true
            color: "black"
            radius: root.radius
            topLeftRadius: root.topLeftRadius >= 0 ? root.topLeftRadius : root.radius
            topRightRadius: root.topRightRadius >= 0 ? root.topRightRadius : root.radius
            bottomLeftRadius: root.bottomLeftRadius >= 0 ? root.bottomLeftRadius : root.radius
            bottomRightRadius: root.bottomRightRadius >= 0 ? root.bottomRightRadius : root.radius
        }
    }
}
