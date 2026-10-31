pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../../Services"
import "../../Theme"

Item {
    id: root
    anchors.fill: parent
    z: 100
    required property Item shapeLayer
    required property Item blurLayer
    required property Item sourceItem
    property point sourceOffset: Qt.point(0, 0)

    readonly property bool selectionActive: ScreenshotSession.currentTool === "none"

    function _distToSegment(px, py, ax, ay, bx, by) {
        const dx = bx - ax, dy = by - ay;
        const len2 = dx * dx + dy * dy;
        let t = len2 === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
        t = Math.max(0, Math.min(1, t));
        const cx = ax + t * dx, cy = ay + t * dy;
        return Math.hypot(px - cx, py - cy);
    }

    function _minDistToStroke(pts, px, py) {
        let best = Infinity;
        for (let i = 0; i < pts.length - 1; i++) {
            const d = root._distToSegment(px, py, pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y);
            if (d < best) best = d;
        }
        return best;
    }

    function _textBoundsFor(annId) {
        for (let i = 0; i < textRepeater.count; i++) {
            const item = textRepeater.itemAt(i);
            if (item && item.ann.id === annId)
                return { x: item.x, y: item.y, w: item.width, h: item.height };
        }
        return null;
    }

    readonly property real hitPad: 6

    function _hits(a, mx, my) {
        const pad = root.hitPad;
        if (a.type === "rectangle" || a.type === "blur") {
            return mx >= a.x - pad && mx <= a.x + a.width + pad &&
            my >= a.y - pad && my <= a.y + a.height + pad;
        }
        if (a.type === "circle") {
            const cx = a.x + a.width / 2, cy = a.y + a.height / 2;
            const rx = a.width / 2 + pad, ry = a.height / 2 + pad;
            const nx = rx === 0 ? 0 : (mx - cx) / rx;
            const ny = ry === 0 ? 0 : (my - cy) / ry;
            return nx * nx + ny * ny <= 1;
        }
        if (a.type === "arrow" || a.type === "line") {
            return root._distToSegment(mx, my, a.x1, a.y1, a.x2, a.y2) <= Math.max(a.strokeWidth / 2, 6) + pad;
        }
        if (a.type === "freehand") {
            const effectiveWidth = a.highlighter ? a.strokeWidth * 3 : a.strokeWidth;
            return root._minDistToStroke(a.points, mx, my) <= Math.max(effectiveWidth / 2, 6) + pad;
        }
        if (a.type === "text") {
            const b = root._textBoundsFor(a.id);
            if (!b) return false;
            return mx >= b.x - pad && mx <= b.x + b.w + pad &&
            my >= b.y - pad && my <= b.y + b.h + pad;
        }
        return false;
    }

    // Every annotation evaluated the same way; when several qualify, the
    // one with the highest stacking order wins — matches what's actually
    // drawn on top instead of whichever arbiter happened to run first.
    function hitTestAll(mx, my) {
        const items = ScreenshotSession.annotations.itemsArray();
        let bestId = -1, bestOrder = -Infinity;
        for (const a of items) {
            if (root._hits(a, mx, my)) {
                const o = a.order !== undefined ? a.order : 0;
                if (o > bestOrder) { bestOrder = o; bestId = a.id; }
            }
        }
        return bestId;
    }
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

    function rawBounds(pts) {
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const p of pts) {
            minX = Math.min(minX, p.x); minY = Math.min(minY, p.y);
            maxX = Math.max(maxX, p.x); maxY = Math.max(maxY, p.y);
        }
        return { x: minX, y: minY, w: maxX - minX, h: maxY - minY };
    }

    function strokeBounds(pts, width) {
        const rb = root.rawBounds(pts);
        const pad = width / 2 + 4;
        return { x: rb.x - pad, y: rb.y - pad, w: rb.w + pad * 2, h: rb.h + pad * 2 };
    }

    function hitTestText(mx, my) {
        for (let i = 0; i < textRepeater.count; i++) {
            const item = textRepeater.itemAt(i);
            if (!item || !item.visible) continue;
            if (mx >= item.x && mx <= item.x + item.width &&
                my >= item.y && my <= item.y + item.height)
                return item.ann.id;
        }
        return -1;
    }

    // ---- rectangle / circle / arrow / line ----
    Repeater {
        model: ScreenshotSession.annotations.store
        delegate: RectShape {
            required property var ann
            z: ann.order || 0
            readonly property bool _dragging: ann.id === root.shapeLayer._selDragId
            readonly property bool _resizing: ann.id === root.shapeLayer._resizeId
            visible: ann.type === "rectangle"
            x: !visible ? 0 : _resizing ? root.shapeLayer._resizeX : ann.x + (_dragging ? root.shapeLayer._selDragOffsetX : 0)
            y: !visible ? 0 : _resizing ? root.shapeLayer._resizeY : ann.y + (_dragging ? root.shapeLayer._selDragOffsetY : 0)
            width: !visible ? 0 : _resizing ? root.shapeLayer._resizeW : ann.width
            height: !visible ? 0 : _resizing ? root.shapeLayer._resizeH : ann.height
            strokeColor: visible ? ann.color : "transparent"
            strokeWidth: visible ? ann.strokeWidth : 0
            filled: visible ? !!ann.filled : false
            dotted: visible ? !!ann.dotted : false
            cornerRadius: visible ? (ann.cornerRadius || 0) : 0
            erasedHoles: visible ? (ann.erasedHoles || []) : []
        }
    }

    Repeater {
        model: ScreenshotSession.annotations.store
        delegate: CircleShape {
            required property var ann
            z: ann.order || 0
            readonly property bool _dragging: ann.id === root.shapeLayer._selDragId
            readonly property bool _resizing: ann.id === root.shapeLayer._resizeId
            visible: ann.type === "circle"
            x: !visible ? 0 : _resizing ? root.shapeLayer._resizeX : ann.x + (_dragging ? root.shapeLayer._selDragOffsetX : 0)
            y: !visible ? 0 : _resizing ? root.shapeLayer._resizeY : ann.y + (_dragging ? root.shapeLayer._selDragOffsetY : 0)
            width: !visible ? 0 : _resizing ? root.shapeLayer._resizeW : ann.width
            height: !visible ? 0 : _resizing ? root.shapeLayer._resizeH : ann.height
            strokeColor: visible ? ann.color : "transparent"
            strokeWidth: visible ? ann.strokeWidth : 0
            filled: visible ? !!ann.filled : false
            dotted: visible ? !!ann.dotted : false
            erasedHoles: visible ? (ann.erasedHoles || []) : []
        }
    }

    Repeater {
        model: ScreenshotSession.annotations.store
        delegate: ArrowShape {
            required property var ann
            z: ann.order || 0
            readonly property bool _dragging: ann.id === root.shapeLayer._selDragId
            readonly property bool _resizing: ann.id === root.shapeLayer._resizeId
            visible: ann.type === "arrow"
            x1: !visible ? 0 : _resizing ? root.shapeLayer._resizeX1 : ann.x1 + (_dragging ? root.shapeLayer._selDragOffsetX : 0)
            y1: !visible ? 0 : _resizing ? root.shapeLayer._resizeY1 : ann.y1 + (_dragging ? root.shapeLayer._selDragOffsetY : 0)
            x2: !visible ? 0 : _resizing ? root.shapeLayer._resizeX2 : ann.x2 + (_dragging ? root.shapeLayer._selDragOffsetX : 0)
            y2: !visible ? 0 : _resizing ? root.shapeLayer._resizeY2 : ann.y2 + (_dragging ? root.shapeLayer._selDragOffsetY : 0)
            strokeColor: visible ? ann.color : "transparent"
            strokeWidth: visible ? ann.strokeWidth : 0
            dotted: visible ? !!ann.dotted : false
        }
    }

    Repeater {
        model: ScreenshotSession.annotations.store
        delegate: ArrowShape {
            required property var ann
            z: ann.order || 0
            readonly property bool _dragging: ann.id === root.shapeLayer._selDragId
            readonly property bool _resizing: ann.id === root.shapeLayer._resizeId
            visible: ann.type === "line"
            x1: !visible ? 0 : _resizing ? root.shapeLayer._resizeX1 : ann.x1 + (_dragging ? root.shapeLayer._selDragOffsetX : 0)
            y1: !visible ? 0 : _resizing ? root.shapeLayer._resizeY1 : ann.y1 + (_dragging ? root.shapeLayer._selDragOffsetY : 0)
            x2: !visible ? 0 : _resizing ? root.shapeLayer._resizeX2 : ann.x2 + (_dragging ? root.shapeLayer._selDragOffsetX : 0)
            y2: !visible ? 0 : _resizing ? root.shapeLayer._resizeY2 : ann.y2 + (_dragging ? root.shapeLayer._selDragOffsetY : 0)
            strokeColor: visible ? ann.color : "transparent"
            strokeWidth: visible ? ann.strokeWidth : 0
            dotted: visible ? !!ann.dotted : false
            showHead: false
        }
    }

    // ---- text (verbatim from TextLayer.qml, unchanged) ----
    Repeater {
        id: textRepeater
        model: ScreenshotSession.annotations.store
        delegate: Item {
            id: textItem
            required property var ann
            z: ann.order || 0

            visible: ann.type === "text"

            readonly property bool selected: ScreenshotSession.selectedAnnotationId === ann.id
            readonly property bool movable: root.selectionActive

            property real _dragOffsetX: 0
            property real _dragOffsetY: 0
            property real _fontSizeDelta: 0

            x: ann.x + _dragOffsetX
            y: ann.y + _dragOffsetY
            width: Math.max(edit.implicitWidth, 40)
            height: Math.max(edit.implicitHeight, (ann.fontSize + _fontSizeDelta) * 1.4)

            Component.onCompleted: {
                edit.text = ann.text;
                if (textItem.selected) edit.forceActiveFocus();
            }

            onSelectedChanged: {
                if (textItem.selected) {
                    edit.forceActiveFocus();
                } else if (edit.text !== ann.text) {
                    ScreenshotSession.annotations.update(ann.id, { text: edit.text });
                }
            }

            Rectangle {
                visible: textItem.selected
                anchors.fill: parent
                anchors.margins: -4
                color: "transparent"
                border.color: ScreenshotSession.annotationColor
                border.width: 1
                radius: 2
            }

            TextEdit {
                id: edit
                anchors.fill: parent
                font.pixelSize: ann.fontSize + textItem._fontSizeDelta
                font.family: ann.fontFamily
                color: ann.color
                wrapMode: TextEdit.NoWrap
                selectByMouse: true
                readOnly: !textItem.selected

                Binding {
                    target: edit
                    property: "text"
                    value: ann.text
                    when: !textItem.selected
                    restoreMode: Binding.RestoreNone
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: textItem.movable
                cursorShape: Qt.SizeAllCursor
                property real startX: 0
                property real startY: 0
                onPressed: (mouse) => {
                    ScreenshotSession.selectAnnotation(ann.id);
                    edit.forceActiveFocus();
                    const p = mapToItem(root, mouse.x, mouse.y);
                    startX = p.x; startY = p.y;
                }
                onPositionChanged: (mouse) => {
                    if (!pressed) return;
                    const p = mapToItem(root, mouse.x, mouse.y);
                    textItem._dragOffsetX = p.x - startX;
                    textItem._dragOffsetY = p.y - startY;
                }
                onReleased: {
                    if (textItem._dragOffsetX === 0 && textItem._dragOffsetY === 0) return;
                    ScreenshotSession.annotations.update(ann.id, {
                        x: ann.x + textItem._dragOffsetX,
                        y: ann.y + textItem._dragOffsetY
                    });
                    textItem._dragOffsetX = 0;
                    textItem._dragOffsetY = 0;
                }
            }

            Rectangle {
                visible: textItem.selected && textItem.movable
                width: 12; height: 12
                radius: 6
                color: ScreenshotSession.annotationColor
                border.color: "#ffffff"
                border.width: 1
                x: parent.width - width / 2
                y: parent.height - height / 2

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.SizeFDiagCursor
                    property real startY: 0
                    onPressed: (mouse) => {
                        const p = mapToItem(root, mouse.x, mouse.y);
                        startY = p.y;
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed) return;
                        const p = mapToItem(root, mouse.x, mouse.y);
                        textItem._fontSizeDelta = (p.y - startY) * 0.5;
                    }
                    onReleased: {
                        if (textItem._fontSizeDelta === 0) return;
                        const newSize = Math.max(8, ann.fontSize + textItem._fontSizeDelta);
                        ScreenshotSession.annotations.update(ann.id, { fontSize: newSize });
                        textItem._fontSizeDelta = 0;
                    }
                }
            }

            Rectangle {
                visible: textItem.selected
                width: 18; height: 18
                radius: 9
                color: "#cc3333"
                x: parent.width
                y: -width
                Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 12 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        ScreenshotSession.annotations.remove(ann.id);
                        ScreenshotSession.clearAnnotationSelection();
                    }
                }
            }
        }
    }

    // ---- freehand (verbatim from FreehandLayer.qml, unchanged) ----
    Repeater {
        model: ScreenshotSession.annotations.store
        delegate: Item {
            id: strokeItem
            required property var ann
            z: ann.order || 0
            visible: strokeItem.ann.type === "freehand"
            anchors.fill: parent

            readonly property bool selected: ScreenshotSession.selectedAnnotationId === strokeItem.ann.id
            readonly property var _bounds: visible ? root.strokeBounds(strokeItem.ann.points, strokeItem.ann.strokeWidth) : ({x:0,y:0,w:0,h:0})
            readonly property var _rawBounds: visible ? root.rawBounds(strokeItem.ann.points) : ({x:0,y:0,w:0,h:0})
            readonly property var _liveRawBounds: root._resizeId === strokeItem.ann.id
            ? root.rawBounds(root._resizeLivePoints)
            : strokeItem._rawBounds

            property real _dragOffsetX: 0
            property real _dragOffsetY: 0

            function liveScaledPoints() {
                if (root._resizeId !== strokeItem.ann.id) return strokeItem.ann.points;
                const ob = root._resizeOrigBounds;
                const sx = ob.w === 0 ? 1 : root._resizeW / ob.w;
                const sy = ob.h === 0 ? 1 : root._resizeH / ob.h;
                return root._resizeOrigPoints.map(p => ({
                    x: root._resizeX + (p.x - ob.x) * sx,
                                                        y: root._resizeY + (p.y - ob.y) * sy
                }));
            }

            onAnnChanged: strokeCanvas.requestPaint()

            Canvas {
                id: strokeCanvas
                x: strokeItem._dragOffsetX
                y: strokeItem._dragOffsetY
                width: parent.width
                height: parent.height
                renderStrategy: Canvas.Immediate

                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const pts = strokeItem.liveScaledPoints();
                    if (!pts || pts.length < 2) return;

                    ctx.lineCap = "round";
                    ctx.lineJoin = "round";
                    ctx.strokeStyle = strokeItem.ann.color;
                    ctx.lineWidth = strokeItem.ann.highlighter
                    ? strokeItem.ann.strokeWidth * 3
                    : strokeItem.ann.strokeWidth;
                    ctx.globalAlpha = strokeItem.ann.highlighter ? 0.4 : 1.0;
                    if (strokeItem.ann.dotted) ctx.setLineDash([2, 6]);
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

                Component.onCompleted: requestPaint()
            }

            Shape {
                id: selectionHalo
                visible: strokeItem.selected
                x: strokeItem._dragOffsetX
                y: strokeItem._dragOffsetY
                anchors.fill: parent
                antialiasing: true
                opacity: 0.55

                ShapePath {
                    strokeColor: Theme.color3
                    strokeWidth: (strokeItem.ann.highlighter
                    ? strokeItem.ann.strokeWidth * 3
                    : strokeItem.ann.strokeWidth) + 4
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin

                    PathPolyline {
                        path: {
                            const pts = strokeItem.liveScaledPoints();
                            return pts ? pts.map(p => Qt.point(p.x, p.y)) : [];
                        }
                    }
                }
            }

            Rectangle {
                visible: strokeItem.selected
                color: "transparent"
                border.width: 1
                border.color: Theme.color3
                radius: 4
                x: strokeItem._liveRawBounds.x - 6 + strokeItem._dragOffsetX
                y: strokeItem._liveRawBounds.y - 6 + strokeItem._dragOffsetY
                width: strokeItem._liveRawBounds.w + 12
                height: strokeItem._liveRawBounds.h + 12
            }

            MouseArea {
                x: strokeItem._bounds.x
                y: strokeItem._bounds.y
                width: strokeItem._bounds.w
                height: strokeItem._bounds.h
                enabled: strokeItem.selected && root.selectionActive
                cursorShape: Qt.SizeAllCursor
                property real lastX: 0
                property real lastY: 0
                onPressed: (mouse) => { lastX = mouse.x; lastY = mouse.y; }
                onPositionChanged: (mouse) => {
                    if (!pressed) return;
                    strokeItem._dragOffsetX += mouse.x - lastX;
                    strokeItem._dragOffsetY += mouse.y - lastY;
                    lastX = mouse.x; lastY = mouse.y;
                }
                onReleased: {
                    if (strokeItem._dragOffsetX === 0 && strokeItem._dragOffsetY === 0) return;
                    const shifted = strokeItem.ann.points.map(p => ({
                        x: p.x + strokeItem._dragOffsetX, y: p.y + strokeItem._dragOffsetY
                    }));
                    ScreenshotSession.annotations.update(strokeItem.ann.id, { points: shifted });
                    strokeItem._dragOffsetX = 0;
                    strokeItem._dragOffsetY = 0;
                }
            }

            Repeater {
                model: strokeItem.selected && root.selectionActive ? ["tl","t","tr","l","r","bl","b","br"] : []
                delegate: Rectangle {
                    id: sHandle
                    required property string modelData
                    readonly property var _rb: strokeItem._liveRawBounds
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
                            case "tl": case "l": case "bl": return _rb.x - width / 2;
                            case "tr": case "r": case "br": return _rb.x + _rb.w - width / 2;
                            default: return _rb.x + _rb.w / 2 - width / 2;
                        }
                    }
                    y: {
                        switch (modelData) {
                            case "tl": case "t": case "tr": return _rb.y - height / 2;
                            case "bl": case "b": case "br": return _rb.y + _rb.h - height / 2;
                            default: return _rb.y + _rb.h / 2 - height / 2;
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: sHandle._cursor
                        onPressed: {
                            root._resizeId = strokeItem.ann.id;
                            root._resizeHandle = sHandle.modelData;
                            root._resizeOrigPoints = strokeItem.ann.points.map(p => ({ x: p.x, y: p.y }));
                            root._resizeOrigBounds = root.rawBounds(root._resizeOrigPoints);
                            root._resizeX = root._resizeOrigBounds.x;
                            root._resizeY = root._resizeOrigBounds.y;
                            root._resizeW = root._resizeOrigBounds.w;
                            root._resizeH = root._resizeOrigBounds.h;
                            root._resizeLivePoints = root._resizeOrigPoints;
                        }
                        onPositionChanged: (mouse) => {
                            if (root._resizeId !== strokeItem.ann.id) return;
                            const p = mapToItem(root, mouse.x, mouse.y);
                            const ob = root._resizeOrigBounds;
                            const id = root._resizeHandle;
                            let newX = root._resizeX, newY = root._resizeY, newW = root._resizeW, newH = root._resizeH;
                            if (id.includes("l")) { newW = (ob.x + ob.w) - p.x; newX = p.x; }
                            if (id.includes("r")) { newW = p.x - ob.x; newX = ob.x; }
                            if (id.includes("t")) { newH = (ob.y + ob.h) - p.y; newY = p.y; }
                            if (id.includes("b")) { newH = p.y - ob.y; newY = ob.y; }
                            root._resizeX = newX; root._resizeY = newY;
                            root._resizeW = Math.max(4, newW); root._resizeH = Math.max(4, newH);
                            root._resizeLivePoints = strokeItem.liveScaledPoints();
                            strokeCanvas.requestPaint();
                        }
                        onReleased: {
                            if (root._resizeId !== strokeItem.ann.id) return;
                            const finalPoints = strokeItem.liveScaledPoints();
                            ScreenshotSession.annotations.update(strokeItem.ann.id, { points: finalPoints });
                            root._resizeId = -1;
                            root._resizeHandle = "";
                        }
                    }
                }
            }

            Rectangle {
                visible: strokeItem.selected
                width: 18; height: 18; radius: 9
                color: "#cc3333"
                x: strokeItem._liveRawBounds.x + strokeItem._liveRawBounds.w
                y: strokeItem._liveRawBounds.y - height
                Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 12 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        ScreenshotSession.annotations.remove(strokeItem.ann.id);
                        ScreenshotSession.selectAnnotation(-1);
                    }
                }
            }
        }
    }

    property int _resizeId: -1
    property string _resizeHandle: ""
    property var _resizeOrigPoints: []
    property var _resizeOrigBounds: null
    property real _resizeX: 0
    property real _resizeY: 0
    property real _resizeW: 0
    property real _resizeH: 0
    property var _resizeLivePoints: []

    // ---- blur (verbatim from BlurLayer.qml, unchanged) ----
    Repeater {
        model: ScreenshotSession.annotations.itemsArray().filter(i => i.type === "blur")

        delegate: Item {
            id: blurDelegate
            required property var modelData
            z: modelData.order || 0
            readonly property bool _dragging: modelData.id === root.blurLayer._selDragId
            readonly property bool _resizing: modelData.id === root._resizeId2
            readonly property bool _selected: modelData.id === ScreenshotSession.selectedAnnotationId
            readonly property real blockSize: modelData.radius !== undefined ? modelData.radius : 16

            x: _resizing ? root._resizeX2 : modelData.x + (_dragging ? root.blurLayer._selDragOffsetX : 0)
            y: _resizing ? root._resizeY2 : modelData.y + (_dragging ? root.blurLayer._selDragOffsetY : 0)
            width: _resizing ? root._resizeW2 : modelData.width
            height: _resizing ? root._resizeH2 : modelData.height

            Item {
                anchors.fill: parent
                clip: true

                ShaderEffectSource {
                    id: srcGrab
                    anchors.fill: parent
                    sourceItem: root.sourceItem
                    sourceRect: Qt.rect(
                        blurDelegate.x + root.sourceOffset.x,
                        blurDelegate.y + root.sourceOffset.y,
                        blurDelegate.width, blurDelegate.height)
                    textureSize: Qt.size(
                        Math.max(1, Math.round(blurDelegate.width / blurDelegate.blockSize)),
                                         Math.max(1, Math.round(blurDelegate.height / blurDelegate.blockSize))
                    )
                    smooth: false
                    mipmap: false
                    hideSource: false
                    live: blurDelegate._dragging || blurDelegate._resizing
                    onLiveChanged: if (!live) scheduleUpdate()
                }
            }

            Rectangle {
                anchors.fill: parent
                visible: blurDelegate._selected
                color: "transparent"
                border.width: 1
                border.color: Theme.color3
                radius: 4
            }

            Rectangle {
                visible: blurDelegate._selected
                width: 18; height: 18; radius: 9
                color: "#cc3333"
                x: parent.width
                y: -width
                Text { anchors.centerIn: parent; text: "×"; color: "white"; font.pixelSize: 12 }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        ScreenshotSession.annotations.remove(blurDelegate.modelData.id);
                        ScreenshotSession.clearAnnotationSelection();
                    }
                }
            }

            Repeater {
                model: blurDelegate._selected ? ["tl","t","tr","l","r","bl","b","br"] : []
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
                            case "tr": case "r": case "br": return blurDelegate.width - width / 2;
                            default: return blurDelegate.width / 2 - width / 2;
                        }
                    }
                    y: {
                        switch (modelData) {
                            case "tl": case "t": case "tr": return -height / 2;
                            case "bl": case "b": case "br": return blurDelegate.height - height / 2;
                            default: return blurDelegate.height / 2 - height / 2;
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: rHandle._cursor
                        onPressed: (mouse) => {
                            root._resizeId2 = blurDelegate.modelData.id;
                            root._resizeHandle2 = rHandle.modelData;
                            root._resizeX2 = blurDelegate.modelData.x;
                            root._resizeY2 = blurDelegate.modelData.y;
                            root._resizeW2 = blurDelegate.modelData.width;
                            root._resizeH2 = blurDelegate.modelData.height;
                            const p = mapToItem(root, mouse.x, mouse.y);
                            root._resizeLastMouseX2 = p.x; root._resizeLastMouseY2 = p.y;
                        }
                        onPositionChanged: (mouse) => {
                            if (root._resizeId2 === -1) return;
                            const p = mapToItem(root, mouse.x, mouse.y);
                            const dx = p.x - root._resizeLastMouseX2;
                            const dy = p.y - root._resizeLastMouseY2;
                            root._resizeLastMouseX2 = p.x; root._resizeLastMouseY2 = p.y;
                            const id = root._resizeHandle2;
                            if (id.includes("l")) {
                                const newW = root._resizeW2 - dx;
                                if (newW >= 20) { root._resizeX2 += dx; root._resizeW2 = newW; }
                            }
                            if (id.includes("r")) root._resizeW2 = Math.max(20, root._resizeW2 + dx);
                            if (id.includes("t")) {
                                const newH = root._resizeH2 - dy;
                                if (newH >= 20) { root._resizeY2 += dy; root._resizeH2 = newH; }
                            }
                            if (id.includes("b")) root._resizeH2 = Math.max(20, root._resizeH2 + dy);
                        }
                        onReleased: {
                            if (root._resizeId2 === -1) return;
                            ScreenshotSession.annotations.update(root._resizeId2, {
                                x: root._resizeX2, y: root._resizeY2,
                                width: root._resizeW2, height: root._resizeH2
                            });
                            root._resizeId2 = -1;
                            root._resizeHandle2 = "";
                        }
                    }
                }
            }
        }
    }

    property int _resizeId2: -1
    property string _resizeHandle2: ""
    property real _resizeX2: 0
    property real _resizeY2: 0
    property real _resizeW2: 0
    property real _resizeH2: 0
    property real _resizeLastMouseX2: 0
    property real _resizeLastMouseY2: 0
}
