pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

Item {
    id: root
    property color strokeColor: "red"
    property real strokeWidth: 3
    property bool filled: false
    property bool dotted: false
    property var erasedHoles: []

    function ellipsePath(w, h) {
        const rx = w / 2, ry = h / 2;
        return "M 0," + ry +
        " A " + rx + "," + ry + " 0 1,0 " + w + "," + ry +
        " A " + rx + "," + ry + " 0 1,0 0," + ry + " Z";
    }

    function _traceEllipse(ctx, w, h) {
        const rx = w / 2, ry = h / 2;
        ctx.beginPath();
        ctx.ellipse(0, 0, w, h);
        ctx.closePath();
    }

    Shape {
        anchors.fill: parent
        visible: !root.filled
        ShapePath {
            strokeColor: root.strokeColor
            strokeWidth: root.strokeWidth
            fillColor: "transparent"
            strokeStyle: root.dotted ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: root.dotted ? [2, 3] : []
            PathSvg { path: root.ellipsePath(root.width, root.height) }
        }
    }

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
            root._traceEllipse(ctx, root.width, root.height);
            ctx.fill();

            if (root.strokeWidth > 0) {
                ctx.lineWidth = root.strokeWidth;
                ctx.strokeStyle = root.strokeColor;
                if (root.dotted) ctx.setLineDash([2, 3]); else ctx.setLineDash([]);
                root._traceEllipse(ctx, root.width, root.height);
                ctx.stroke();
            }

            // Same merge as RectShape: one path, one fill() for every hole.
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
    onErasedHolesChanged: if (root.filled) filledCanvas.requestPaint()
    onFilledChanged: filledCanvas.requestPaint()
    Component.onCompleted: if (root.filled) filledCanvas.requestPaint()
}
