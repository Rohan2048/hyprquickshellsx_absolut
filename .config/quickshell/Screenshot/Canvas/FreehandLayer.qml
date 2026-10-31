pragma ComponentBehavior: Bound
import QtQuick
import "../../Services"

Item {
    id: root
    anchors.fill: parent
    required property Item annotationStack
    readonly property bool selectionActive: ScreenshotSession.currentTool === "none"
    readonly property var _selItem: ScreenshotSession.annotations.itemsArray().find(a => a.id === ScreenshotSession.selectedAnnotationId)

    function distToSegment(px, py, ax, ay, bx, by) {
        const dx = bx - ax, dy = by - ay;
        const len2 = dx * dx + dy * dy;
        let t = len2 === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
        t = Math.max(0, Math.min(1, t));
        const cx = ax + t * dx, cy = ay + t * dy;
        return Math.hypot(px - cx, py - cy);
    }

    function minDistToStroke(pts, px, py) {
        let best = Infinity;
        for (let i = 0; i < pts.length - 1; i++) {
            const d = root.distToSegment(px, py, pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y);
            if (d < best) best = d;
        }
        return best;
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.selectionActive
        propagateComposedEvents: true
        onPressed: (mouse) => {
            const hitId = root.annotationStack.hitTestAll(mouse.x, mouse.y);
            const item = hitId !== -1 ? ScreenshotSession.annotations.itemsArray().find(a => a.id === hitId) : null;
            if (item && item.type === "freehand") {
                ScreenshotSession.selectAnnotation(hitId);
                mouse.accepted = true;
            } else {
                const sel = root._selItem;
                if (!sel || sel.type === "freehand") {
                    ScreenshotSession.clearAnnotationSelection();
                }
                mouse.accepted = false;
            }
        }
    }
}
