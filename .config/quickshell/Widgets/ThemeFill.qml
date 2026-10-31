import QtQuick
import QtQuick.Effects
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
            source: (root.fill && root.fill.image && root.fill.image !== "") ? "file://" + root.fill.image : ""
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
