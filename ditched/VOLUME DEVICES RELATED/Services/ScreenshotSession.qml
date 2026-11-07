
pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "."
import "../Screenshot"
import "../Screenshot/Models"
import "../Theme"
Singleton {
    id: root

    property string imagePath: ""
    property string originalImagePath: ""
    property bool active: false

    // Offset (in original-image pixel coords) of the current imagePath's
    // top-left corner relative to originalImagePath's top-left corner.
    // Zero when imagePath === originalImagePath. Used to translate
    // annotation coordinates when switching between crop <-> fullscreen
    // instead of deleting them outright.
    property real _cropOffsetX: 0
    property real _cropOffsetY: 0
    // Crop rect (in original-image pixel coords) captured at commitCrop()
    // time, consumed by the backend's onCropped handler once the crop
    // actually completes.
    property real _pendingCropX: 0
    property real _pendingCropY: 0

    // ---- Deferred annotation remap state ----
    // Annotations are stored in DISPLAY-pixel coordinates (the coordinate
    // space they're drawn in), which changes scale whenever imagePath
    // switches to an image with a different sourceSize. So a remap can't
    // happen synchronously inside onCropped/setMode — displayScale hasn't
    // been recomputed for the new image yet at that point (it's driven by
    // baseImage.onStatusChanged -> _updateScale() in ScreenshotWindow).
    // Instead we stash what's needed and ScreenshotWindow calls
    // applyPendingRemap() once the new image is Ready and displayScale is
    // current.
    property bool _remapPending: false
    property string _remapKind: ""   // "toCrop" | "toFullscreen"
    property real _scaleBeforeRemap: 1.0
    property bool layersPanelOpen: false
    function toggleLayersPanel() { layersPanelOpen = !layersPanelOpen; }
    // Rescales + repositions every stored annotation. dx, dy are already
    // in DISPLAY-pixel coords for the target image (caller multiplies the
    // original-image-pixel crop offset by the new displayScale before
    // calling this). scaleRatio converts existing display-pixel
    // coords/sizes from the old scale to the new one — this has to be
    // applied to every size-like field (strokeWidth, fontSize, radius,
    // width/height, erasedHoles), not just position, or those stay stuck
    // at whatever scale they were originally drawn at.
    function _remapAnnotations(dx, dy, scaleRatio) {
        if (dx === 0 && dy === 0 && scaleRatio === 1) return;
        const items = root.annotations.itemsArray();
        for (const a of items) {
            if (a.type === "rectangle") {
                const patch = {
                    x: a.x * scaleRatio + dx,
                    y: a.y * scaleRatio + dy,
                    width: a.width * scaleRatio,
                    height: a.height * scaleRatio,
                    strokeWidth: a.strokeWidth * scaleRatio,
                    cornerRadius: (a.cornerRadius || 0) * scaleRatio
                };
                if (a.erasedHoles && a.erasedHoles.length) {
                    patch.erasedHoles = a.erasedHoles.map(h => ({
                        x: h.x * scaleRatio, y: h.y * scaleRatio, r: h.r * scaleRatio
                    }));
                }
                root.annotations.update(a.id, patch);
            } else if (a.type === "circle") {
                const patch = {
                    x: a.x * scaleRatio + dx,
                    y: a.y * scaleRatio + dy,
                    width: a.width * scaleRatio,
                    height: a.height * scaleRatio,
                    strokeWidth: a.strokeWidth * scaleRatio
                };
                if (a.erasedHoles && a.erasedHoles.length) {
                    patch.erasedHoles = a.erasedHoles.map(h => ({
                        x: h.x * scaleRatio, y: h.y * scaleRatio, r: h.r * scaleRatio
                    }));
                }
                root.annotations.update(a.id, patch);
            } else if (a.type === "text") {
                root.annotations.update(a.id, {
                    x: a.x * scaleRatio + dx,
                    y: a.y * scaleRatio + dy,
                    fontSize: a.fontSize * scaleRatio
                });
            } else if (a.type === "blur") {
                root.annotations.update(a.id, {
                    x: a.x * scaleRatio + dx,
                    y: a.y * scaleRatio + dy,
                    width: a.width * scaleRatio,
                    height: a.height * scaleRatio,
                    radius: (a.radius !== undefined ? a.radius : 64) * scaleRatio
                });
            } else if (a.type === "arrow" || a.type === "line") {
                root.annotations.update(a.id, {
                    x1: a.x1 * scaleRatio + dx, y1: a.y1 * scaleRatio + dy,
                    x2: a.x2 * scaleRatio + dx, y2: a.y2 * scaleRatio + dy,
                    strokeWidth: a.strokeWidth * scaleRatio
                });
            } else if (a.type === "freehand") {
                root.annotations.update(a.id, {
                    points: a.points.map(p => ({ x: p.x * scaleRatio + dx, y: p.y * scaleRatio + dy })),
                                        strokeWidth: a.strokeWidth * scaleRatio
                });
            }
        }
    }

    // Called by ScreenshotWindow's baseImage.onStatusChanged, AFTER
    // _updateScale() has run for the newly-loaded image, so
    // root.displayScale reflects the new image's scale.
    function applyPendingRemap() {
        if (!root._remapPending) return;
        const newScale = root.displayScale > 0 ? root.displayScale : 1;
        const scaleRatio = newScale / (root._scaleBeforeRemap > 0 ? root._scaleBeforeRemap : 1);

        // eraserWidth is a session-level tool setting, not a stored
        // annotation, so it's rescaled once here rather than per-item in
        // _remapAnnotations.


        if (root._remapKind === "toCrop") {
            // Shift origin by -cropOffset (original-image px), expressed
            // in the NEW (cropped) image's display-pixel space.
            const dx = -root._pendingCropX * newScale;
            const dy = -root._pendingCropY * newScale;
            root._remapAnnotations(dx, dy, scaleRatio);
            root._cropOffsetX = root._pendingCropX;
            root._cropOffsetY = root._pendingCropY;
        } else if (root._remapKind === "toFullscreen") {
            // Shift origin by +cropOffset (original-image px), expressed
            // in the NEW (fullscreen) image's display-pixel space.
            const dx = root._cropOffsetX * newScale;
            const dy = root._cropOffsetY * newScale;
            root._remapAnnotations(dx, dy, scaleRatio);
            root._cropOffsetX = 0;
            root._cropOffsetY = 0;
        }

        root._remapPending = false;
        root._remapKind = "";
    }

    property CaptureBackend _backend: CaptureBackend {
        // Raw captures land in the popup stack first instead of opening
        // the editor directly -- see ScreenshotQueue / openFromQueue().
        onCaptured: (path) => ScreenshotQueue.enqueue(path)
        onFailed: (reason) => console.warn("Screenshot capture failed:", reason)
        onCropped: (path) => {
            // Capture the scale annotations are CURRENTLY drawn at
            // (fullscreen/original image's scale) before swapping images.
            root._scaleBeforeRemap = root.displayScale;
            root._remapKind = "toCrop";
            root._remapPending = true;
            root.imagePath = path;
            root.clearSelection();
            root.currentMode = "fullscreen";
            // NOTE: applyPendingRemap() fires from ScreenshotWindow once
            // baseImage reports Ready for the new imagePath and
            // _updateScale() has run.
        }
        onCropFailed: (reason) => console.warn("Crop failed:", reason)
    }

    // Promotes a raw capture out of ScreenshotQueue into the full
    // annotation editor. This is what onCaptured used to do directly
    // before screenshots started landing in the popup stack first.
    function openFromQueue(path) {
        root.annotations.clear();
        root.imagePath = path;
        root.originalImagePath = path;
        root._cropOffsetX = 0;
        root._cropOffsetY = 0;
        root._remapPending = false;
        root.active = true;
    }

    property string screenName: ""
    property rect selectionRect: Qt.rect(0, 0, 0, 0)
    property bool hasSelection: false

    function setSelection(rect) {
        root.selectionRect = rect;
        root.hasSelection = rect.width > 0 && rect.height > 0;
    }

    function clearSelection() {
        root.selectionRect = Qt.rect(0, 0, 0, 0);
        root.hasSelection = false;
    }

    property real displayScale: 1.0
    property color annotationColor: Theme.color3
    property real annotationStrokeWidth: 3
    property int selectedAnnotationId: -1
    property real annotationFontSize: 24
    property string annotationFontFamily: "sans-serif"
    property real annotationCornerRadius: 0
    property bool annotationFilled: false
    property bool annotationDotted: false
    property bool annotationHighlighter: false
    property real eraserWidth: 20
    property string eraserTargetType: "freehand" // "freehand" | "rectangle" | "circle" | "arrow" | "line"

    property var customFonts: [] // [{ family, path }] — mirrors _customFontsFile.adapter.fonts
    property bool colorPopupOpen: false

    // ---- Custom font persistence ----
    readonly property string _customFontsPath: Quickshell.env("HOME") + "/.config/quickshell/state/custom_fonts.json"

    property FileView _customFontsFile: FileView {
        id: customFontsFile
        path: root._customFontsPath
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        adapter: JsonAdapter {
            id: customFontsAdapter
            property var fonts: []
            onFontsChanged: root.customFonts = customFontsAdapter.fonts
        }
    }

    // Re-registers every persisted font with Qt's font database on startup.
    // Remembering the family name alone isn't enough — the .ttf/.otf file
    // has to be reloaded each run for that family to actually render.
    property Instantiator _persistedFontLoaders: Instantiator {
        model: root.customFonts
        delegate: FontLoader {
            required property var modelData
            source: modelData && modelData.path ? "file://" + modelData.path : ""
        }
    }

    function setAnnotationColor(color) {
        root.annotationColor = color;
        if (root.selectedAnnotationId !== -1)
            root.annotations.update(root.selectedAnnotationId, { color: color });
    }

    function setAnnotationFontFamily(family) {
        root.annotationFontFamily = family;
        if (root.selectedAnnotationId !== -1)
            root.annotations.update(root.selectedAnnotationId, { fontFamily: family });
    }

    function addCustomFont(family, path) {
        for (const f of root.customFonts) {
            if (f.family === family) {
                console.log("ScreenshotSession: font already registered:", family);
                return;
            }
        }
        const updated = root.customFonts.concat([{ family: family, path: path }]);
        root.customFonts = updated;
        root._customFontsFile.adapter.fonts = updated; // triggers onAdapterUpdated -> writeAdapter()
    }

    function removeCustomFont(family) {
        const updated = root.customFonts.filter(f => f.family !== family);
        root.customFonts = updated;
        root._customFontsFile.adapter.fonts = updated; // triggers onAdapterUpdated -> writeAdapter()
    }

    function selectAnnotation(annId) { root.selectedAnnotationId = annId; }
    function clearAnnotationSelection() { root.selectedAnnotationId = -1; }

    property string currentMode: "fullscreen"
    property string currentTool: "none"

    function setMode(mode) {
        if (mode === "fullscreen" && root.imagePath !== root.originalImagePath) {
            root._scaleBeforeRemap = root.displayScale;
            root._remapKind = "toFullscreen";
            root._remapPending = true;
            root.imagePath = root.originalImagePath;
            root.clearSelection();
            // applyPendingRemap() fires from ScreenshotWindow once the
            // original image reports Ready and displayScale is updated.
        }
        root.currentMode = mode;
    }

    function toggleCropMode() {
        if (root.currentMode === "crop") {
            root.setMode("fullscreen");
        } else {
            root.setMode("crop");
        }
    }


    function setTool(tool) {
        if (tool === "doodle") root.eraserTargetType = "freehand";
        else if (["rectangle", "circle", "arrow", "line"].includes(tool)) root.eraserTargetType = tool;

        root.currentTool = (root.currentTool === tool) ? "none" : tool;
        root.clearAnnotationSelection();
    }

    function save() { console.log("save() not yet implemented"); }
    function saveAs() { console.log("saveAs() not yet implemented"); }
    function copyToClipboard() { console.log("copyToClipboard() not yet implemented"); }

    property AnnotationModel annotations: AnnotationModel {}
    function undo() { root.annotations.undo(); }
    function redo() { root.annotations.redo(); }

    function capture() {
        if (root.active)
            return;
        const monitor = Hyprland.focusedMonitor;
        root.screenName = monitor ? monitor.name : "";
        root._backend.capture(root.screenName);
    }

    function commitCrop() {
        if (!root.hasSelection) return;
        const scale = root.displayScale > 0 ? root.displayScale : 1;
        const px = Math.round(root.selectionRect.x / scale);
        const py = Math.round(root.selectionRect.y / scale);
        const pw = Math.round(root.selectionRect.width / scale);
        const ph = Math.round(root.selectionRect.height / scale);
        root._pendingCropX = px;
        root._pendingCropY = py;
        root._backend.cropImage(root.originalImagePath, px, py, pw, ph);
    }

    function cancel() {
        root.active = false;
        root.imagePath = "";
        root.originalImagePath = "";
        root._cropOffsetX = 0;
        root._cropOffsetY = 0;
        root._remapPending = false;
        root._remapKind = "";
        root.annotations.clear();
        root.clearSelection();
        root.clearAnnotationSelection();
    }

    property IpcHandler _ipc: IpcHandler {
        target: "screenshot"
        function capture(): void { root.capture(); }
        function cancel(): void { root.cancel(); }
    }
}
