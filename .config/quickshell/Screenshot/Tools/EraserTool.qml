pragma ComponentBehavior: Bound
import QtQuick
import "../../Services"

Item {
    id: root
    anchors.fill: parent

    function _categoryOf(a) {
        return a.sourceType || a.type;
    }

    function _splitRuns(points, mx, my, threshold) {
        const runs = [];
        let current = [];
        for (let i = 0; i < points.length; i++) {
            const d = Math.hypot(points[i].x - mx, points[i].y - my);
            if (d > threshold) {
                current.push(i);
            } else {
                if (current.length >= 2) runs.push(current);
                current = [];
            }
        }
        if (current.length >= 2) runs.push(current);
        return runs;
    }

    function _sampleRect(a) {
        const step = 4;
        const w = a.width, h = a.height;
        const pts = [];
        for (let x = 0; x <= w; x += step) pts.push({ x: a.x + x, y: a.y });
        for (let y = 0; y <= h; y += step) pts.push({ x: a.x + w, y: a.y + y });
        for (let x = w; x >= 0; x -= step) pts.push({ x: a.x + x, y: a.y + h });
        for (let y = h; y >= 0; y -= step) pts.push({ x: a.x, y: a.y + y });
        return pts;
    }

    function _sampleCircle(a) {
        const rx = a.width / 2, ry = a.height / 2;
        const cx = a.x + rx, cy = a.y + ry;
        const circumference = Math.PI * (rx + ry);
        const samples = Math.max(24, Math.round(circumference / 4));
        const pts = [];
        for (let i = 0; i <= samples; i++) {
            const t = (i / samples) * Math.PI * 2;
            pts.push({ x: cx + rx * Math.cos(t), y: cy + ry * Math.sin(t) });
        }
        return pts;
    }

    function _sampleLine(a) {
        const dist = Math.hypot(a.x2 - a.x1, a.y2 - a.y1);
        const step = 4;
        const samples = Math.max(1, Math.round(dist / step));
        const pts = [];
        for (let i = 0; i <= samples; i++) {
            const t = i / samples;
            pts.push({ x: a.x1 + (a.x2 - a.x1) * t, y: a.y1 + (a.y2 - a.y1) * t });
        }
        return pts;
    }

    function _touchesFilledRect(a, mx, my, eraserRadius) {
        const pad = a.strokeWidth / 2 + eraserRadius;
        return mx >= a.x - pad && mx <= a.x + a.width + pad &&
        my >= a.y - pad && my <= a.y + a.height + pad;
    }

    function _touchesFilledCircle(a, mx, my, eraserRadius) {
        const pad = a.strokeWidth / 2 + eraserRadius;
        const rx = a.width / 2 + pad, ry = a.height / 2 + pad;
        if (rx <= 0 || ry <= 0) return false;
        const cx = a.x + a.width / 2, cy = a.y + a.height / 2;
        const nx = (mx - cx) / rx, ny = (my - cy) / ry;
        return nx * nx + ny * ny <= 1;
    }

    // Cheap pre-check before the expensive per-shape work
    // (_sampleRect/_sampleCircle/_sampleLine regenerate their whole point
    // array from scratch on every call). Almost every shape on the canvas
    // isn't anywhere near the eraser at any given instant, so testing the
    // bounding box first — instead of resampling and then checking — is
    // what keeps eraseAt() cheap when it's being called many times per
    // interpolated drag segment.
    function _nearBBox(bx, by, bw, bh, mx, my, pad) {
        return mx >= bx - pad && mx <= bx + bw + pad &&
        my >= by - pad && my <= by + bh + pad;
    }

    function _eraseFreehand(a, mx, my, eraserRadius, removeIds, additions, updates) {
        const threshold = eraserRadius + a.strokeWidth / 2;
        const runs = root._splitRuns(a.points, mx, my, threshold);
        if (runs.length === 1 && runs[0].length === a.points.length) return;

        if (runs.length === 0) {
            removeIds.push(a.id);
            return;
        }

        updates.push({ id: a.id, patch: { points: runs[0].map(i => a.points[i]) } });

        for (let r = 1; r < runs.length; r++) {
            const frag = {
                type: "freehand",
                points: runs[r].map(i => a.points[i]),
                color: a.color,
                strokeWidth: a.strokeWidth,
                highlighter: !!a.highlighter,
                dotted: !!a.dotted
            };
            if (a.sourceType) frag.sourceType = a.sourceType;
            additions.push(frag);
        }
    }

    function _eraseHollowOutline(a, mx, my, eraserRadius, points, removeIds, additions, updates) {
        const threshold = eraserRadius + a.strokeWidth / 2;
        const runs = root._splitRuns(points, mx, my, threshold);
        if (runs.length === 1 && runs[0].length === points.length) return;

        if (runs.length === 0) {
            removeIds.push(a.id);
            return;
        }

        updates.push({
            id: a.id,
            patch: {
                type: "freehand",
                points: runs[0].map(i => points[i]),
                     sourceType: a.type
            }
        });

        for (let r = 1; r < runs.length; r++) {
            additions.push({
                type: "freehand",
                points: runs[r].map(i => points[i]),
                           color: a.color,
                           strokeWidth: a.strokeWidth,
                           highlighter: false,
                           dotted: !!a.dotted,
                           sourceType: a.type
            });
        }
    }

    // Minimum spacing (as a fraction of eraser radius) between consecutive
    // holes stamped for the same shape. eraseSegment samples every
    // eraserWidth/4 px along the swept path so hit-testing never misses a
    // gap — but that density is overkill for the holes we actually persist:
    // circles that close together are almost fully redundant with their
    // neighbor's coverage, yet each one still costs the renderer a full
    // hole to draw/subtract.
    readonly property real _holeSpacingFactor: 0.75

    // Punch state lives here for the duration of a whole drag (reset on
    // press, cleared on release) rather than being rebuilt per mouse-move
    // event. Keeping it drag-persistent does two things a per-event
    // accumulator can't:
    //   1. The min-spacing check in _touchesPunch compares against the
    //      last hole stamped anywhere in the drag, not just within the
    //      current interpolation batch — so it actually thins holes across
    //      event boundaries, not just within one.
    //   2. `base` is read from the model once per shape per drag instead of
    //      once per event, and — the big one — _flushPunchCache below can
    //      be throttled, so the O(current size) array copy needed to grow
    //      erasedHoles happens on a fraction of events instead of every
    //      single one. A fast drag fires far more move events per second
    //      than a slow one, so without throttling, fast erasing pays that
    //      growing copy cost far more often — that's what scaled the lag
    //      with speed.
    property var _punchCache: ({})
    property real _lastPunchFlushTime: 0
    readonly property int _punchFlushIntervalMs: 32 // ~30fps is plenty for visual feedback

    function _touchesPunch(a, mx, my, eraserRadius, touchesFn) {
        if (!touchesFn(a, mx, my, eraserRadius)) return;
        let entry = root._punchCache[a.id];
        if (!entry) {
            entry = { base: a.erasedHoles || [], pending: [], lastX: null, lastY: null };
            root._punchCache[a.id] = entry;
        }
        const lx = mx - a.x, ly = my - a.y;
        if (entry.lastX !== null) {
            const d = Math.hypot(lx - entry.lastX, ly - entry.lastY);
            if (d < eraserRadius * root._holeSpacingFactor) return;
        }
        entry.pending.push({ x: lx, y: ly, r: eraserRadius });
        entry.lastX = lx;
        entry.lastY = ly;
    }

    // Flushes accumulated holes to the model. Throttled by wall-clock time
    // unless force is set (initial press and final release always flush
    // immediately, so feedback never feels delayed at the start or lost at
    // the end — only the steady-state mid-drag writes get batched).
    function _flushPunchCache(force) {
        const now = Date.now();
        if (!force && now - root._lastPunchFlushTime < root._punchFlushIntervalMs) return;
        root._lastPunchFlushTime = now;
        for (const id in root._punchCache) {
            const entry = root._punchCache[id];
            if (entry.pending.length === 0) continue;
            entry.base = entry.base.concat(entry.pending);
            entry.pending = [];
            ScreenshotSession.annotations.updateLive(Number(id), { erasedHoles: entry.base });
        }
    }

    function _eraseLine(a, mx, my, eraserRadius, removeIds, additions, updates) {
        const threshold = eraserRadius + a.strokeWidth / 2;
        const points = root._sampleLine(a);
        const runs = root._splitRuns(points, mx, my, threshold);
        if (runs.length === 1 && runs[0].length === points.length) return;

        if (runs.length === 0) {
            removeIds.push(a.id);
            return;
        }

        const lastIdx = points.length - 1;
        const hasHead = a.type === "arrow";
        const category = a.sourceType || a.type;

        const first = runs[0];
        const p1 = points[first[0]];
        const p2 = points[first[first.length - 1]];
        const reachesTip = hasHead && first[first.length - 1] === lastIdx;
        const patch = { type: reachesTip ? "arrow" : "line", x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y };
        if (category === "arrow" && patch.type !== "arrow") patch.sourceType = "arrow";
        updates.push({ id: a.id, patch });

        for (let r = 1; r < runs.length; r++) {
            const run = runs[r];
            const q1 = points[run[0]];
            const q2 = points[run[run.length - 1]];
            const runReachesTip = hasHead && run[run.length - 1] === lastIdx;
            const frag = {
                type: runReachesTip ? "arrow" : "line",
                x1: q1.x, y1: q1.y, x2: q2.x, y2: q2.y,
                color: a.color, strokeWidth: a.strokeWidth, dotted: !!a.dotted
            };
            if (category === "arrow" && frag.type !== "arrow") frag.sourceType = "arrow";
            additions.push(frag);
        }
    }

    // Reads a fresh snapshot of the model every call (previous point's
    // writes already landed in the model in real time, so this always
    // sees current state — no working-copy juggling needed) and applies
    // the result immediately via the targeted *Live() ops.
    //
    // Punched holes are the one exception: they're order-independent and
    // never need a mid-segment re-read to stay correct (unlike freehand/
    // hollow-outline splitting), so they're collected into punchAccum
    // instead of written here — eraseSegment() flushes them once per
    // drag segment rather than once per interpolated point, which is
    // what keeps filled-shape erasing from repainting the whole Canvas
    // (fill + stroke + every hole so far) on every single sub-step.
    function eraseAt(mx, my) {
        const eraserRadius = ScreenshotSession.eraserWidth / 2;
        const target = ScreenshotSession.eraserTargetType;
        const items = ScreenshotSession.annotations.itemsArray();

        const removeIds = [];
        const additions = [];
        const updates = [];

        for (const a of items) {
            if (root._categoryOf(a) !== target) continue;

            if (a.type === "freehand") {
                root._eraseFreehand(a, mx, my, eraserRadius, removeIds, additions, updates);
            } else if (a.type === "rectangle") {
                if (a.filled) {
                    root._touchesPunch(a, mx, my, eraserRadius, root._touchesFilledRect);
                } else {
                    const threshold = eraserRadius + a.strokeWidth / 2;
                    if (root._nearBBox(a.x, a.y, a.width, a.height, mx, my, threshold))
                        root._eraseHollowOutline(a, mx, my, eraserRadius, root._sampleRect(a), removeIds, additions, updates);
                }
            } else if (a.type === "circle") {
                if (a.filled) {
                    root._touchesPunch(a, mx, my, eraserRadius, root._touchesFilledCircle);
                } else {
                    const threshold = eraserRadius + a.strokeWidth / 2;
                    if (root._nearBBox(a.x, a.y, a.width, a.height, mx, my, threshold))
                        root._eraseHollowOutline(a, mx, my, eraserRadius, root._sampleCircle(a), removeIds, additions, updates);
                }
            } else if (a.type === "arrow" || a.type === "line") {
                const threshold = eraserRadius + a.strokeWidth / 2;
                const minX = Math.min(a.x1, a.x2), minY = Math.min(a.y1, a.y2);
                const maxX = Math.max(a.x1, a.x2), maxY = Math.max(a.y1, a.y2);
                if (root._nearBBox(minX, minY, maxX - minX, maxY - minY, mx, my, threshold))
                    root._eraseLine(a, mx, my, eraserRadius, removeIds, additions, updates);
            }
        }

        if (removeIds.length === 0 && additions.length === 0 && updates.length === 0) return;

        for (const id of removeIds) ScreenshotSession.annotations.removeLive(id);
        for (const u of updates) ScreenshotSession.annotations.updateLive(u.id, u.patch);
        for (const ann of additions) ScreenshotSession.annotations.addLive(ann);
    }

    property real _lastEraseX: 0
    property real _lastEraseY: 0

    // Walks the whole segment from the last known point to (mx, my) instead
    // of testing only the endpoint. On a fast drag, onPositionChanged
    // deltas can exceed the eraser radius — and for filled shapes,
    // _touchesFilledRect/_touchesFilledCircle only test a single point, so
    // a big enough jump can land entirely outside the shape even though
    // the cursor visually swept across it. Stepping at a fraction of the
    // eraser width keeps consecutive test points close enough that
    // nothing gets skipped, regardless of drag speed.
    function eraseSegment(mx, my) {
        const dist = Math.hypot(mx - root._lastEraseX, my - root._lastEraseY);
        const step = Math.max(2, ScreenshotSession.eraserWidth / 4);
        // Capped so one very large, very fast jump can't spawn an
        // unbounded number of eraseAt() calls — 32 steps covers well
        // beyond any realistic per-event mouse delta at typical eraser
        // sizes, so accuracy in normal use is unaffected.
        const steps = Math.min(32, Math.max(1, Math.ceil(dist / step)));
        for (let i = 1; i <= steps; i++) {
            const t = i / steps;
            root.eraseAt(root._lastEraseX + (mx - root._lastEraseX) * t,
                         root._lastEraseY + (my - root._lastEraseY) * t);
        }
        root._flushPunchCache(false);
        root._lastEraseX = mx;
        root._lastEraseY = my;
    }

    Rectangle {
        id: cursor
        visible: false
        width: ScreenshotSession.eraserWidth
        height: ScreenshotSession.eraserWidth
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: "#ffffff"
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: (mouse) => {
            cursor.x = mouse.x - cursor.width / 2;
            cursor.y = mouse.y - cursor.height / 2;
            cursor.visible = true;
            if (pressed) root.eraseSegment(mouse.x, mouse.y);
        }
        onPressed: (mouse) => {
            ScreenshotSession.annotations.beginLiveEdit();
            root._punchCache = {};
            root._lastPunchFlushTime = 0;
            root._lastEraseX = mouse.x;
            root._lastEraseY = mouse.y;
            root.eraseAt(mouse.x, mouse.y);
            root._flushPunchCache(true);
        }
        onReleased: (mouse) => {
            root._flushPunchCache(true);
            root._punchCache = {};
        }
        onExited: cursor.visible = false
    }
}
