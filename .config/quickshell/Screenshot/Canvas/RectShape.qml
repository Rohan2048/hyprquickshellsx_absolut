pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property color strokeColor: "red"
    property real strokeWidth: 3
    property bool filled: false
    property bool dotted: false
    property real cornerRadius: 0
    property var erasedHoles: [] // only used when filled: [{x, y, r}] local coords

    function roundedRectPath(w, h, r) {
        r = Math.max(0, Math.min(r, w / 2, h / 2));
        if (r === 0) return "M 0,0 L " + w + ",0 L " + w + "," + h + " L 0," + h + " Z";
        return "M " + r + ",0 " +
        "L " + (w - r) + ",0 " +
        "Q " + w + ",0 " + w + "," + r + " " +
        "L " + w + "," + (h - r) + " " +
        "Q " + w + "," + h + " " + (w - r) + "," + h + " " +
        "L " + r + "," + h + " " +
        "Q 0," + h + " 0," + (h - r) + " " +
        "L 0," + r + " " +
        "Q 0,0 " + r + ",0 Z";
    }

    function _traceRoundedRect(ctx, w, h, r) {
        r = Math.max(0, Math.min(r, w / 2, h / 2));
        ctx.beginPath();
        if (r === 0) {
            ctx.rect(0, 0, w, h);
        } else {
            ctx.moveTo(r, 0);
            ctx.lineTo(w - r, 0);
            ctx.quadraticCurveTo(w, 0, w, r);
            ctx.lineTo(w, h - r);
            ctx.quadraticCurveTo(w, h, w - r, h);
            ctx.lineTo(r, h);
            ctx.quadraticCurveTo(0, h, 0, h - r);
            ctx.lineTo(0, r);
            ctx.quadraticCurveTo(0, 0, r, 0);
            ctx.closePath();
        }
    }

    // Unfilled (hollow) rectangle — pure vector outline. Erasing this one
    // still works by converting it into "freehand" border fragments; it
    // never carries erasedHoles.
    Shape {
        anchors.fill: parent
        visible: !root.filled
        ShapePath {
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            strokeStyle: root.dotted ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: root.dotted ? [2, 3] : []
            joinStyle: ShapePath.MiterJoin
            PathSvg { path: root.roundedRectPath(root.width, root.height, root.cornerRadius) }
        }
    }

    // Filled rectangle — rendered on a raster Canvas so erased holes are
    // punched with destination-out compositing. This is what keeps
    // overlapping erase strokes from un-erasing each other (the old
    // odd-even path-hole approach flips double-covered overlap regions
    // back to "filled" — that was the smear), and lets one hole cut
    // through fill + border together since it's one paint surface, not
    // two independent shapes glued together.
    Canvas {
        id: filledCanvas
        anchors.fill: parent
        visible: root.filled
        renderStrategy: Canvas.Immediate
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.save();
            ctx.globalCompositeOperation = "source-over";

            ctx.fillStyle = root.strokeColor;
            root._traceRoundedRect(ctx, root.width, root.height, root.cornerRadius);
            ctx.fill();

            if (root.strokeWidth > 0) {
                ctx.lineWidth = root.strokeWidth;
                ctx.strokeStyle = root.strokeColor;
                if (root.dotted) ctx.setLineDash([2, 3]); else ctx.setLineDash([]);
                root._traceRoundedRect(ctx, root.width, root.height, root.cornerRadius);
                ctx.stroke();
            }

            // One path containing every hole as a subpath, punched out with
            // a single fill() call instead of a separate beginPath/arc/fill
            // per hole. This repaint already reruns from scratch on every
            // hole added (see onErasedHolesChanged below), so collapsing N
            // fills into 1 is what actually saves work — not the hole
            // count itself. Same-direction arcs use the nonzero winding
            // rule, so overlapping holes still punch correctly (winding
            // count stays nonzero, never cancels to zero).
            if (root.erasedHoles.length > 0) {
                ctx.globalCompositeOperation = "destination-out";
                ctx.beginPath();
                for (const hole of root.erasedHoles) {
                    ctx.moveTo(hole.x + hole.r, hole.y);
                    ctx.arc(hole.x, hole.y, hole.r, 0, Math.PI * 2);
                }
                ctx.fill();
            }
            ctx.restore();
        }
    }

    onWidthChanged: if (root.filled) filledCanvas.requestPaint()
    onHeightChanged: if (root.filled) filledCanvas.requestPaint()
    onStrokeColorChanged: if (root.filled) filledCanvas.requestPaint()
    onStrokeWidthChanged: if (root.filled) filledCanvas.requestPaint()
    onDottedChanged: if (root.filled) filledCanvas.requestPaint()
    onCornerRadiusChanged: if (root.filled) filledCanvas.requestPaint()
    onErasedHolesChanged: if (root.filled) filledCanvas.requestPaint()
    onFilledChanged: filledCanvas.requestPaint()
    Component.onCompleted: if (root.filled) filledCanvas.requestPaint()
}
