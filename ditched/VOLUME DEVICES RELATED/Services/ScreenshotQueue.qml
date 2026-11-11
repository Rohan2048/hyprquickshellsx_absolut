pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "."

Singleton {
    id: root

    readonly property int maxItems: 3
    readonly property int lingerMs: 5000

    property ListModel store: ListModel {}
    property int _nextId: 1

    function _indexOfId(itemId) {
        for (let i = 0; i < root.store.count; i++)
            if (root.store.get(i).itemId === itemId) return i;
            return -1;
    }

    function enqueue(path) {
        if (root.store.count >= root.maxItems)
            root._finalize(0, "save");

        const id = root._nextId++;
        root.store.append({ itemId: id, path: path, createdAt: Date.now() });
    }

    function _finalize(index, action) {
        if (index < 0 || index >= root.store.count) return;
        const path = root.store.get(index).path;
        root.store.remove(index);
        if (action === "save") root._saveRaw(path);
        else if (action === "discard") root._discardRaw(path);
    }

    function dismiss(itemId) {
        root._finalize(root._indexOfId(itemId), "save");
    }

    function dismissAll() {
        if (root.store.count === 0) return;
        const paths = [];
        for (let i = 0; i < root.store.count; i++)
            paths.push(root.store.get(i).path);
        root.store.clear();
        root._saveRawBatch(paths);
    }

    function discard(itemId) {
        root._finalize(root._indexOfId(itemId), "discard");
    }

    function openInEditor(itemId) {
        if (ScreenshotSession.active) return;
        const idx = root._indexOfId(itemId);
        if (idx === -1) return;
        const path = root.store.get(idx).path;
        root._finalize(idx, "none");
        ScreenshotSession.openFromQueue(path);
    }

    function _shellQuote(str) {
        return "'" + String(str).replace(/'/g, "'\\''") + "'";
    }

    function _timestampName() {
        const d = new Date();
        const pad = n => String(n).padStart(2, "0");
        // FIX 1: Added millisecond precision to prevent filename collisions during rapid bursts
        const ms = String(d.getMilliseconds()).padStart(3, "0");
        return "Screenshot_" + d.getFullYear() + pad(d.getMonth() + 1) + pad(d.getDate())
        + "_" + pad(d.getHours()) + pad(d.getMinutes()) + pad(d.getSeconds()) + "_" + ms;
    }

    property var _scriptQueue: []
    property bool _scriptBusy: false
    property string _currentLabel: ""
    property var _currentMeta: null

    property var _pendingSaved: []
    property int _pendingFailed: 0

    function _runScript(script, label, meta) {
        root._scriptQueue.push({ script: script, label: label, meta: meta || null });
        root._drainScriptQueue();
    }

    function _drainScriptQueue() {
        if (root._scriptBusy || root._scriptQueue.length === 0) return;
        root._scriptBusy = true;
        const job = root._scriptQueue.shift();
        root._currentLabel = job.label;
        root._currentMeta = job.meta;

        scriptProc.command = ["bash", "-c", job.script];
        // FIX 2: Defer starting to the next event loop tick to prevent QML property batching from dropping rapid successive process starts
        deferStartTimer.start();
    }

    function _flushSaveNotification() {
        const saved = root._pendingSaved;
        const failedCount = root._pendingFailed;
        root._pendingSaved = [];
        root._pendingFailed = 0;
        if (saved.length === 0 && failedCount === 0) return;

        let parts = [];
        if (saved.length === 1) parts.push("Saved as " + saved[0]);
        else if (saved.length > 1) parts.push("Saved " + saved.length + " screenshots");
        if (failedCount > 0) parts.push(failedCount + " failed");

        const urgency = (failedCount > 0 && saved.length === 0) ? "-u critical " : "";
        const script = "notify-send " + urgency + "-t 3000 'Screenshot' " + root._shellQuote(parts.join(", "));
        root._runScript(script, "notify", null);
    }

    Process {
        id: scriptProc
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    console.warn("ScreenshotQueue " + root._currentLabel + "() stderr:", text);
            }
        }
        onExited: (exitCode, exitStatus) => {
            const meta = root._currentMeta;
            if (meta && meta.type === "save") {
                if (exitCode === 0) root._pendingSaved.push(meta.filename);
                else root._pendingFailed++;
            } else if (meta && meta.type === "saveBatch") {
                if (exitCode === 0) root._pendingSaved = root._pendingSaved.concat(meta.filenames);
                else root._pendingFailed += meta.filenames.length;
            }
            root._scriptBusy = false;
            if (root._scriptQueue.length === 0) root._flushSaveNotification();
            else root._drainScriptQueue();
        }
    }

    // FIX 2 (continued): Timer to safely trigger the process start on the next event loop tick
    Timer {
        id: deferStartTimer
        interval: 0
        repeat: false
        onTriggered: {
            scriptProc.running = true;
        }
    }

    function _saveRaw(path) {
        const filename = root._timestampName() + ".png";
        const script = "mkdir -p \"$HOME/Pictures/Screenshots\" && cp "
        + root._shellQuote(path)
        + " \"$HOME/Pictures/Screenshots/" + filename + "\""
        + " && rm -f " + root._shellQuote(path);
        root._runScript(script, "save", { type: "save", filename: filename });
    }

    function _saveRawBatch(paths) {
        if (paths.length === 0) return;
        const base = root._timestampName();
        const filenames = [];
        let script = "mkdir -p \"$HOME/Pictures/Screenshots\"";
        paths.forEach((p, i) => {
            const filename = (paths.length > 1 ? base + "_" + (i + 1) : base) + ".png";
            filenames.push(filename);
            script += " && cp " + root._shellQuote(p) + " \"$HOME/Pictures/Screenshots/" + filename + "\""
            + " && rm -f " + root._shellQuote(p);
        });
        root._runScript(script, "saveBatch", { type: "saveBatch", filenames: filenames });
    }

    function _discardRaw(path) {
        root._runScript("rm -f " + root._shellQuote(path), "discard");
    }
}
