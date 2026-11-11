pragma ComponentBehavior: Bound
import QtQuick

QtObject {
    id: root

    property var _past: []   // snapshots to restore on undo
    property var _future: [] // snapshots to restore on redo

    function push(previousSnapshot) {
        root._past = root._past.concat([previousSnapshot]);
        root._future = []; // any new action invalidates redo history
    }

    function undo(currentSnapshot) {
        if (root._past.length === 0) return null;
        const prev = root._past[root._past.length - 1];
        root._past = root._past.slice(0, -1);
        root._future = root._future.concat([currentSnapshot]);
        return prev;
    }

    function redo(currentSnapshot) {
        if (root._future.length === 0) return null;
        const next = root._future[root._future.length - 1];
        root._future = root._future.slice(0, -1);
        root._past = root._past.concat([currentSnapshot]);
        return next;
    }

    function clear() {
        root._past = [];
        root._future = [];
    }
}
