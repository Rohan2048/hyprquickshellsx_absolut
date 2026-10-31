pragma ComponentBehavior: Bound
import QtQuick
import "../../Services"
import "../../Theme"

Item {
    id: root
    anchors.fill: parent
    z: 10
    required property Item annotationStack
    readonly property var shapeTools: ["rectangle", "circle", "line", "arrow"]
    readonly property bool toolActive: root.shapeTools.includes(ScreenshotSession.currentTool)
    readonly property bool selectionActive: ScreenshotSession.currentTool === "none"
    readonly property int minSize: 6

    property bool _drawing: false
    property real _startX: 0
    property real _startY: 0
    property real _curX: 0
    property real _curY: 0
    property string _activeType: ""

    property int _selDragId: -1
    property string _selDragType: ""
    property real _selDragOffsetX: 0
    property real _selDragOffsetY: 0
    property real _selStartMouseX: 0
    property real _selStartMouseY: 0
    property int _resizeId: -1
    property string _resizeHandle: ""
    property real _resizeX: 0
    property real _resizeY: 0
    property real _resizeW: 0
    property real _resizeH: 0
    property real _resizeX1: 0
    property real _resizeY1: 0
    property real _resizeX2: 0
    property real _resizeY2: 0
    property real _resizeLastMouseX: 0
    property real _resizeLastMouseY: 0

    readonly property var _selItem: ScreenshotSession.annotations.itemsArray().find(a => a.id === ScreenshotSession.selectedAnnotationId)
    function snapshotColor(c) {
        return Qt.rgba(c.r, c.g, c.b, c.a);
    }

    function _distToSegment(px, py, ax, ay, bx, by) {
        const dx = bx - ax, dy = by - ay;
        const len2 = dx * dx + dy * dy;
        let t = len2 === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
        t = Math.max(0, Math.min(1, t));
        const cx = ax + t * dx, cy = ay + t * dy;
        return Math.hypot(px - cx, py - cy);
    }

    // Reverse iteration = topmost-drawn shape wins on overlapping clicks.
    // Padding kept generous and simple — precise border-only hit-testing
    // for hollow shapes isn't worth the complexity here.
    function hitTestAt(mx, my) {
        const items = ScreenshotSession.annotations.itemsArray();
        for (let i = items.length - 1; i >= 0; i--) {
            const a = items[i];
            if (a.type === "rectangle") {
                const pad = 4;
                if (mx >= a.x - pad && mx <= a.x + a.width + pad &&
                    my >= a.y - pad && my <= a.y + a.height + pad) return a.id;
            } else if (a.type === "circle") {
                const pad = 4;
                const cx = a.x + a.width / 2, cy = a.y + a.height / 2;
                const rx = a.width / 2 + pad, ry = a.height / 2 + pad;
                const nx = rx === 0 ? 0 : (mx - cx) / rx;
                const ny = ry === 0 ? 0 : (my - cy) / ry;
                if (nx * nx + ny * ny <= 1) return a.id;
            } else if (a.type === "arrow" || a.type === "line") {
                if (root._distToSegment(mx, my, a.x1, a.y1, a.x2, a.y2) <= Math.max(a.strokeWidth / 2, 6) + 4)
                    return a.id;
            }
        }
        return -1;
    }

    function boundsFor(a) {
        if (!a) return null;
        if (a.type === "rectangle" || a.type === "circle")
            return { x: a.x, y: a.y, w: a.width, h: a.height };
        if (a.type === "arrow" || a.type === "line") {
            const minX = Math.min(a.x1, a.x2), maxX = Math.max(a.x1, a.x2);
            const minY = Math.min(a.y1, a.y2), maxY = Math.max(a.y1, a.y2);
            const pad = Math.max(a.strokeWidth, 8);
            return { x: minX - pad, y: minY - pad, w: (maxX - minX) + pad * 2, h: (maxY - minY) + pad * 2 };
        }
        return null;
    }
    function liveItem(a) {
        if (!a || a.id !== root._resizeId) return a;
        if (a.type === "rectangle" || a.type === "circle")
            return Object.assign({}, a, { x: root._resizeX, y: root._resizeY, width: root._resizeW, height: root._resizeH });
        if (a.type === "arrow" || a.type === "line")
            return Object.assign({}, a, { x1: root._resizeX1, y1: root._resizeY1, x2: root._resizeX2, y2: root._resizeY2 });
        return a;
    }
    function _commit() {
        root._drawing = false;
        const type = root._activeType;
        let annotation = null;
        const col = root.snapshotColor(ScreenshotSession.annotationColor);

        if (type === "arrow" || type === "line") {
            const dist = Math.hypot(root._curX - root._startX, root._curY - root._startY);
            if (dist < root.minSize) return;
            annotation = {
                type: type,
                x1: root._startX, y1: root._startY,
                x2: root._curX, y2: root._curY,
                color: col,
                strokeWidth: ScreenshotSession.annotationStrokeWidth,
                dotted: ScreenshotSession.annotationDotted
            };
        } else if (type === "circle") {
            const radius = Math.hypot(root._curX - root._startX, root._curY - root._startY);
            if (radius < root.minSize) return;
            annotation = {
                type: "circle",
                x: root._startX - radius, y: root._startY - radius,
                width: radius * 2, height: radius * 2,
                color: col,
                strokeWidth: ScreenshotSession.annotationStrokeWidth,
                dotted: ScreenshotSession.annotationDotted,
                filled: ScreenshotSession.annotationFilled
            };
        } else if (type === "rectangle") {
            const x = Math.min(root._startX, root._curX);
            const y = Math.min(root._startY, root._curY);
            const w = Math.abs(root._curX - root._startX);
            const h = Math.abs(root._curY - root._startY);
            if (w < root.minSize || h < root.minSize) return;
            annotation = {
                type: "rectangle",
                x: x, y: y, width: w, height: h,
                color: col,
                strokeWidth: ScreenshotSession.annotationStrokeWidth,
                dotted: ScreenshotSession.annotationDotted,
                filled: ScreenshotSession.annotationFilled,
                cornerRadius: ScreenshotSession.annotationCornerRadius
            };
        }

        if (annotation) ScreenshotSession.annotations.add(annotation);
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.toolActive
        onPressed: (mouse) => {
            root._drawing = true;
            root._activeType = ScreenshotSession.currentTool;
            root._startX = mouse.x;
            root._startY = mouse.y;
            root._curX = mouse.x;
            root._curY = mouse.y;
        }
        onPositionChanged: (mouse) => {
            if (!root._drawing) return;
            root._curX = mouse.x;
            root._curY = mouse.y;
        }
        onReleased: root._commit()
    }

    // Final arbiter for selection: real per-shape hit testing. Only
    // clears the current selection on a miss if it's the type this layer
    // actually owns — otherwise it defers to whichever layer owns the
    // currently-selected item's type (TextLayer for text, FreehandLayer
    // for freehand), since a miss against shapes here can still be a hit
    // against e.g. a text resize handle that this layer knows nothing
    // about.
    MouseArea {
        anchors.fill: parent
        enabled: root.selectionActive
        propagateComposedEvents: true
        onPressed: (mouse) => {
            const hitId = root.annotationStack.hitTestAll(mouse.x, mouse.y);
            if (hitId === -1) {
                const sel = root._selItem;
                if (!sel || sel.type === "rectangle" || sel.type === "circle" || sel.type === "arrow" || sel.type === "line") {
                    ScreenshotSession.clearAnnotationSelection();
                }
                mouse.accepted = false;
                return;
            }
            const item = ScreenshotSession.annotations.itemsArray().find(a => a.id === hitId);
            if (!["rectangle", "circle", "arrow", "line"].includes(item.type)) {
                mouse.accepted = false;
                return;
            }
            ScreenshotSession.selectAnnotation(hitId);
            root._selDragId = hitId;
            root._selDragType = item.type;
            root._selStartMouseX = mouse.x;
            root._selStartMouseY = mouse.y;
            root._selDragOffsetX = 0;
            root._selDragOffsetY = 0;
            mouse.accepted = true;
        }
        onPositionChanged: (mouse) => {
            if (root._selDragId === -1) return;
            root._selDragOffsetX = mouse.x - root._selStartMouseX;
            root._selDragOffsetY = mouse.y - root._selStartMouseY;
        }
        onReleased: {
            if (root._selDragId === -1) return;
            if (root._selDragOffsetX !== 0 || root._selDragOffsetY !== 0) {
                const item = ScreenshotSession.annotations.itemsArray().find(a => a.id === root._selDragId);
                if (item) {
                    if (root._selDragType === "rectangle" || root._selDragType === "circle") {
                        ScreenshotSession.annotations.update(item.id, {
                            x: item.x + root._selDragOffsetX,
                            y: item.y + root._selDragOffsetY
                        });
                    } else if (root._selDragType === "arrow" || root._selDragType === "line") {
                        ScreenshotSession.annotations.update(item.id, {
                            x1: item.x1 + root._selDragOffsetX, y1: item.y1 + root._selDragOffsetY,
                            x2: item.x2 + root._selDragOffsetX, y2: item.y2 + root._selDragOffsetY
                        });
                    }
                }
            }
            root._selDragId = -1;
            root._selDragOffsetX = 0;
            root._selDragOffsetY = 0;
        }
    }

    // --- selection outline + delete handle for whichever shape is selected ---
    Rectangle {
        id: shapeSelOutline
        readonly property var _b: root.boundsFor(root.liveItem(root._selItem))
        readonly property real _dragOffX: root._selItem && root._selDragId === root._selItem.id ? root._selDragOffsetX : 0
        readonly property real _dragOffY: root._selItem && root._selDragId === root._selItem.id ? root._selDragOffsetY : 0
        readonly property bool _isBoxType:
        !!root._selItem &&
        (root._selItem.type === "rectangle" ||
        root._selItem.type === "circle")
        visible: root._selItem !== undefined && _b !== null
        color: "transparent"
        border.width: _isBoxType ? 1 : 0
        border.color: Theme.color3
        radius: 4
        x: visible ? _b.x + _dragOffX : 0
        y: visible ? _b.y + _dragOffY : 0
        width: visible ? _b.w : 0
        height: visible ? _b.h : 0

        Rectangle {
            visible: parent.visible
            width: 18; height: 18; radius: 9
            color: "#cc3333"
            x: parent.width
            y: -width
            Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 12 }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    ScreenshotSession.annotations.remove(root._selItem.id);
                    ScreenshotSession.clearAnnotationSelection();
                }
            }
        }

        Repeater {
            model: (root._selItem && (root._selItem.type === "rectangle" || root._selItem.type === "circle"))
            ? ["tl","t","tr","l","r","bl","b","br"] : []
            delegate: Rectangle {
                id: rHandle
                required property string modelData
                readonly property var _cursor: {
                    switch (modelData) {
                        case "tl": case "br": return Qt.SizeFDiagCursor;
                        case "tr": case "bl": return Qt.SizeBDiagCursor;
                        case "t": case "b": return Qt.SizeVerCursor;
                        default: return Qt.SizeHorCursor;
                    }
                }
                width: 12; height: 12; radius: 6
                color: Theme.color3
                border.color: "#ffffff"
                border.width: 1
                x: {
                    switch (modelData) {
                        case "tl": case "l": case "bl": return -width / 2;
                        case "tr": case "r": case "br": return shapeSelOutline.width - width / 2;
                        default: return shapeSelOutline.width / 2 - width / 2;
                    }
                }
                y: {
                    switch (modelData) {
                        case "tl": case "t": case "tr": return -height / 2;
                        case "bl": case "b": case "br": return shapeSelOutline.height - height / 2;
                        default: return shapeSelOutline.height / 2 - height / 2;
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: rHandle._cursor
                    onPressed: (mouse) => {
                        const item = root._selItem;
                        root._resizeId = item.id;
                        root._resizeHandle = rHandle.modelData;
                        root._resizeX = item.x; root._resizeY = item.y;
                        root._resizeW = item.width; root._resizeH = item.height;
                        const p = mapToItem(root, mouse.x, mouse.y);
                        root._resizeLastMouseX = p.x; root._resizeLastMouseY = p.y;
                    }
                    onPositionChanged: (mouse) => {
                        if (root._resizeId === -1) return;
                        const p = mapToItem(root, mouse.x, mouse.y);
                        const dx = p.x - root._resizeLastMouseX;
                        const dy = p.y - root._resizeLastMouseY;
                        root._resizeLastMouseX = p.x; root._resizeLastMouseY = p.y;
                        const id = root._resizeHandle;
                        if (id.includes("l")) {
                            const newW = root._resizeW - dx;
                            if (newW >= root.minSize) { root._resizeX += dx; root._resizeW = newW; }
                        }
                        if (id.includes("r")) root._resizeW = Math.max(root.minSize, root._resizeW + dx);
                        if (id.includes("t")) {
                            const newH = root._resizeH - dy;
                            if (newH >= root.minSize) { root._resizeY += dy; root._resizeH = newH; }
                        }
                        if (id.includes("b")) root._resizeH = Math.max(root.minSize, root._resizeH + dy);
                    }
                    onReleased: {
                        if (root._resizeId === -1) return;
                        ScreenshotSession.annotations.update(root._resizeId, {
                            x: root._resizeX, y: root._resizeY,
                            width: root._resizeW, height: root._resizeH
                        });
                        root._resizeId = -1;
                        root._resizeHandle = "";
                    }
                }
            }
        }
    }

    Repeater {
        model: (root._selItem && (root._selItem.type === "arrow" || root._selItem.type === "line")) ? ["p1","p2"] : []
        delegate: Rectangle {
            id: lHandle
            required property string modelData
            readonly property var _live: root.liveItem(root._selItem)
            width: 14; height: 14; radius: 7
            color: Theme.color3
            border.color: "#ffffff"
            border.width: 1
            x: (modelData === "p1" ? _live.x1 : _live.x2) + shapeSelOutline._dragOffX - width / 2
            y: (modelData === "p1" ? _live.y1 : _live.y2) + shapeSelOutline._dragOffY - height / 2
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onPressed: {
                    const item = root._selItem;
                    root._resizeId = item.id;
                    root._resizeHandle = lHandle.modelData;
                    root._resizeX1 = item.x1; root._resizeY1 = item.y1;
                    root._resizeX2 = item.x2; root._resizeY2 = item.y2;
                }
                onPositionChanged: (mouse) => {
                    if (root._resizeId === -1) return;
                    const p = mapToItem(root, mouse.x, mouse.y);
                    if (root._resizeHandle === "p1") { root._resizeX1 = p.x; root._resizeY1 = p.y; }
                    else { root._resizeX2 = p.x; root._resizeY2 = p.y; }
                }
                onReleased: {
                    if (root._resizeId === -1) return;
                    ScreenshotSession.annotations.update(root._resizeId, {
                        x1: root._resizeX1, y1: root._resizeY1,
                        x2: root._resizeX2, y2: root._resizeY2
                    });
                    root._resizeId = -1;
                    root._resizeHandle = "";
                }
            }
        }
    }

    // --- live preview while dragging a new shape ---
    RectShape {
        visible: root._drawing && root._activeType === "rectangle"
        x: Math.min(root._startX, root._curX)
        y: Math.min(root._startY, root._curY)
        width: Math.abs(root._curX - root._startX)
        height: Math.abs(root._curY - root._startY)
        strokeColor: ScreenshotSession.annotationColor
        strokeWidth: ScreenshotSession.annotationStrokeWidth
        filled: ScreenshotSession.annotationFilled
        dotted: ScreenshotSession.annotationDotted
        cornerRadius: ScreenshotSession.annotationCornerRadius
        opacity: 0.8
    }

    CircleShape {
        readonly property real previewRadius: Math.hypot(root._curX - root._startX, root._curY - root._startY)
        visible: root._drawing && root._activeType === "circle"
        x: root._startX - previewRadius
        y: root._startY - previewRadius
        width: previewRadius * 2
        height: previewRadius * 2
        strokeColor: ScreenshotSession.annotationColor
        strokeWidth: ScreenshotSession.annotationStrokeWidth
        filled: ScreenshotSession.annotationFilled
        dotted: ScreenshotSession.annotationDotted
        opacity: 0.8
    }

    ArrowShape {
        visible: root._drawing && root._activeType === "arrow"
        x1: root._startX; y1: root._startY
        x2: root._curX; y2: root._curY
        strokeColor: ScreenshotSession.annotationColor
        strokeWidth: ScreenshotSession.annotationStrokeWidth
        dotted: ScreenshotSession.annotationDotted
        opacity: 0.8
    }

    ArrowShape {
        visible: root._drawing && root._activeType === "line"
        x1: root._startX; y1: root._startY
        x2: root._curX; y2: root._curY
        strokeColor: ScreenshotSession.annotationColor
        strokeWidth: ScreenshotSession.annotationStrokeWidth
        dotted: ScreenshotSession.annotationDotted
        showHead: false
        opacity: 0.8
    }
}
