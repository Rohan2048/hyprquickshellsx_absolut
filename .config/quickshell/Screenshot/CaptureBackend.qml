pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    signal captured(string path)
    signal failed(string reason)
    signal cropped(string path)
    signal cropFailed(string reason)

    property string _pendingPath: ""
    property string _pendingCropPath: ""
    property var _fallbackCommand: null

    // Captures can now be requested in quick succession (that's the whole
    // point of the popup stack), but only one grim process can run at a
    // time -- overlapping runs would stomp _pendingPath/_fallbackCommand
    // and misattribute results. Requests queue here and drain serially.
    property var _captureQueue: []
    property bool _grimBusy: false
    property int _captureSeq: 0

    function capture(outputName) {
        const path = "/tmp/qs-screenshot-" + Date.now() + "-" + (root._captureSeq++) + ".png";

        const primary = outputName
        ? ["grim", "-o", outputName, "-l", "1", "-t", "png", path]
        : ["grim", "-l", "1", "-t", "png", path];
        const fallback = outputName
        ? ["grim", "-o", outputName, "-t", "png", path]
        : ["grim", "-t", "png", path];

        root._captureQueue.push({ path: path, primary: primary, fallback: fallback });
        root._drainCaptureQueue();
    }

    function _drainCaptureQueue() {
        if (root._grimBusy || root._captureQueue.length === 0) return;
        root._grimBusy = true;
        const job = root._captureQueue.shift();
        root._pendingPath = job.path;
        root._fallbackCommand = job.fallback;
        grimProcess.command = job.primary;
        grimProcess.running = true;
    }

    function cropImage(sourcePath, x, y, w, h) {
        const ts = Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
        const path = "/tmp/qs-screenshot-crop-" + ts + ".png";
        root._pendingCropPath = path;

        cropProcess.command = ["convert", sourcePath, "-crop", w + "x" + h + "+" + x + "+" + y, "+repage", path];
        cropProcess.running = true;
    }

    Process {
        id: grimProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root._grimBusy = false;
                root.captured(root._pendingPath);
                root._drainCaptureQueue();
                return;
            }
            // -l may not exist on older grim -- retry once with the
            // plain command before reporting failure.
            if (root._fallbackCommand !== null) {
                const fallback = root._fallbackCommand;
                root._fallbackCommand = null;
                grimProcess.command = fallback;
                grimProcess.running = true;
                return;
            }
            root._grimBusy = false;
            root.failed("grim exited with code " + exitCode);
            root._drainCaptureQueue();
        }
    }

    Process {
        id: cropProcess
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.cropped(root._pendingCropPath);
            else
                root.cropFailed("convert exited with code " + exitCode);
        }
    }
}
