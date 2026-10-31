pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: root

    property ListModel store: ListModel {}
    property UndoStack _undoStack: UndoStack {}
    property int _nextId: 1

    function itemsArray() {
        const arr = [];
        for (let i = 0; i < root.store.count; i++)
            arr.push(root.store.get(i).ann);
        return arr;
    }

    function _indexOf(annId) {
        for (let i = 0; i < root.store.count; i++)
            if (root.store.get(i).ann.id === annId) return i;
            return -1;
    }

    function _snapshot() {
        return root.itemsArray().map(a => Object.assign({}, a));
    }

    function _loadSnapshot(arr) {
        root.store.clear();
        for (const a of arr) root.store.append({ ann: a });
    }

    function _pushUndo() {
        root._undoStack.push(root._snapshot());
    }

    function _maxOrder() {
        let max = -Infinity;
        for (let i = 0; i < root.store.count; i++) {
            const o = root.store.get(i).ann.order;
            if (o !== undefined && o > max) max = o;
        }
        return max === -Infinity ? 0 : max;
    }

    function _minOrder() {
        let min = Infinity;
        for (let i = 0; i < root.store.count; i++) {
            const o = root.store.get(i).ann.order;
            if (o !== undefined && o < min) min = o;
        }
        return min === Infinity ? 0 : min;
    }

    function add(annotation) {
        root._pushUndo();
        const newId = root._nextId++;
        const withId = Object.assign({}, annotation, { id: newId, order: newId });
        root.store.append({ ann: withId });
        return newId;
    }

    function remove(annId) {
        const idx = root._indexOf(annId);
        if (idx === -1) return;
        root._pushUndo();
        root.store.remove(idx);
    }

    function update(annId, patch) {
        const idx = root._indexOf(annId);
        if (idx === -1) return;
        root._pushUndo();
        const current = root.store.get(idx).ann;
        root.store.setProperty(idx, "ann", Object.assign({}, current, patch));
    }

    // ---- Layer stacking ----
    function bringToFront(annId) {
        const idx = root._indexOf(annId);
        if (idx === -1) return;
        root._pushUndo();
        const current = root.store.get(idx).ann;
        root.store.setProperty(idx, "ann", Object.assign({}, current, { order: root._maxOrder() + 1 }));
    }

    function sendToBack(annId) {
        const idx = root._indexOf(annId);
        if (idx === -1) return;
        root._pushUndo();
        const current = root.store.get(idx).ann;
        root.store.setProperty(idx, "ann", Object.assign({}, current, { order: root._minOrder() - 1 }));
    }

    // One-step forward/back: swap order with the nearest neighbor in
    // stacking order (not id order), since gaps build up from repeated
    // front/back calls.
    function bringForward(annId) {
        const idx = root._indexOf(annId);
        if (idx === -1) return;
        const current = root.store.get(idx).ann;
        let neighborIdx = -1, neighborOrder = Infinity;
        for (let i = 0; i < root.store.count; i++) {
            const o = root.store.get(i).ann.order;
            if (o !== undefined && o > current.order && o < neighborOrder) { neighborOrder = o; neighborIdx = i; }
        }
        if (neighborIdx === -1) return;
        root._pushUndo();
        const neighbor = root.store.get(neighborIdx).ann;
        root.store.setProperty(idx, "ann", Object.assign({}, current, { order: neighborOrder }));
        root.store.setProperty(neighborIdx, "ann", Object.assign({}, neighbor, { order: current.order }));
    }

    function sendBackward(annId) {
        const idx = root._indexOf(annId);
        if (idx === -1) return;
        const current = root.store.get(idx).ann;
        let neighborIdx = -1, neighborOrder = -Infinity;
        for (let i = 0; i < root.store.count; i++) {
            const o = root.store.get(i).ann.order;
            if (o !== undefined && o < current.order && o > neighborOrder) { neighborOrder = o; neighborIdx = i; }
        }
        if (neighborIdx === -1) return;
        root._pushUndo();
        const neighbor = root.store.get(neighborIdx).ann;
        root.store.setProperty(idx, "ann", Object.assign({}, current, { order: neighborOrder }));
        root.store.setProperty(neighborIdx, "ann", Object.assign({}, neighbor, { order: current.order }));
    }

    function beginLiveEdit() {
        root._pushUndo();
    }

    function addLive(annotation) {
        const newId = root._nextId++;
        const withId = Object.assign({}, annotation, { id: newId, order: newId });
        root.store.append({ ann: withId });
        return newId;
    }

    function removeLive(annId) {
        const idx = root._indexOf(annId);
        if (idx === -1) return;
        root.store.remove(idx);
    }

    function updateLive(annId, patch) {
        const idx = root._indexOf(annId);
        if (idx === -1) return;
        const current = root.store.get(idx).ann;
        root.store.setProperty(idx, "ann", Object.assign({}, current, patch));
    }

    function clear() {
        root.store.clear();
        root._undoStack.clear();
    }

    function undo() {
        const snap = root._undoStack.undo(root._snapshot());
        if (snap !== null) root._loadSnapshot(snap);
    }

    function redo() {
        const snap = root._undoStack.redo(root._snapshot());
        if (snap !== null) root._loadSnapshot(snap);
    }
}
