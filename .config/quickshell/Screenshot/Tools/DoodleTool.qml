pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    required property var annotationModel
    property color strokeColor: "#ff4d4d"
    property real strokeWidth: 4
    property bool highlighter: false
    property bool dotted: false

    property var currentPoints: []
    property bool drawing: false

    function smoothedSegments(pts) {
        const segs = [];
        for (let i = 0; i < pts.length - 1; i++) {
            const p0 = pts[i === 0 ? 0 : i - 1];
            const p1 = pts[i];
            const p2 = pts[i + 1];
            const p3 = pts[i + 2 < pts.length ? i + 2 : i + 1];
            const c1 = { x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6 };
            const c2 = { x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6 };
            segs.push({ c1, c2, end: p2 });
        }
        return segs;
    }

    Canvas {
        id: previewCanvas
        anchors.fill: parent
        visible: root.drawing
        renderStrategy: Canvas.Immediate

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const pts = root.currentPoints;
            if (pts.length < 2) return;

            ctx.lineCap = "round";
            ctx.lineJoin = "round";
            ctx.strokeStyle = root.strokeColor;
            ctx.lineWidth = root.highlighter ? root.strokeWidth * 3 : root.strokeWidth;
            ctx.globalAlpha = root.highlighter ? 0.4 : 1.0;
            if (root.dotted) ctx.setLineDash([2, 6]);
            else ctx.setLineDash([]);

            ctx.beginPath();
            ctx.moveTo(pts[0].x, pts[0].y);
            if (pts.length === 2) {
                ctx.lineTo(pts[1].x, pts[1].y);
            } else {
                const segs = root.smoothedSegments(pts);
                for (const seg of segs)
                    ctx.bezierCurveTo(seg.c1.x, seg.c1.y, seg.c2.x, seg.c2.y, seg.end.x, seg.end.y);
            }
            ctx.stroke();
        }
    }

    onCurrentPointsChanged: previewCanvas.requestPaint()

    // Fires one paint cycle after commit — guarantees the newly-added
    // delegate in FreehandLayer has actually painted before this preview
    // is torn down, avoiding the one-frame flash.
    Timer {
        id: clearTimer
        interval: 32
        repeat: false
        onTriggered: {
            root.drawing = false;
            root.currentPoints = [];
        }
    }

    MouseArea {
        anchors.fill: parent
        onPressed: (mouse) => {
            root.drawing = true
            root.currentPoints = [{ x: mouse.x, y: mouse.y }]
        }
        onPositionChanged: (mouse) => {
            if (!root.drawing) return
                root.currentPoints = root.currentPoints.concat([{ x: mouse.x, y: mouse.y }])
        }
        onReleased: {
            if (!root.drawing) return
                const pts = root.currentPoints;
            if (pts.length < 2) {
                root.drawing = false;
                root.currentPoints = [];
                return;
            }
            const c = root.strokeColor;
            root.annotationModel.add({
                type: "freehand",
                points: pts,
                color: Qt.rgba(c.r, c.g, c.b, c.a),
                                     strokeWidth: root.strokeWidth,
                                     highlighter: root.highlighter,
                                     dotted: root.dotted
            });
            clearTimer.start();
        }
    }
}
