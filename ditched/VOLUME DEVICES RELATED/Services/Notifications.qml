pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

QtObject {
    id: root
    property ListModel list: ListModel {}
    property string expandedHash: ""
    readonly property int notificationCount: (list.count === 1 && list.get(0).hash === "") ? 0 : list.count

    property var _byId: ({})

    property ListModel activeToasts: ListModel {}
    readonly property var _urgencyTimeouts: ({ 0: 3000, 1: 10000, 2: 30000 })

    // ---- Do Not Disturb: silences toasts only. Notifications still land
    // in the popup/history list as normal via _addNotification. ----
    property bool dndEnabled: false

    function toggleDnd() {
        dndEnabled = !dndEnabled
    }

    function _addToast(n) {
        if (root.dndEnabled) return

            const urgency = n.urgency !== undefined ? n.urgency : 1
            const timeout = (n.expireTimeout && n.expireTimeout > 0) ? n.expireTimeout : root._urgencyTimeouts[urgency]

            // Coalesce key: same app + same summary counts as "the same toast
            // updating", not a new one. This is what was multiplying entrance/
            // exit blur cost by N during a burst - a spammy app re-notifying
            // rapidly (volume ticks, repeated build-status pings, etc.) now
            // updates ONE existing card in place instead of spawning a new
            // animated delegate each time.
            const mergeKey = (n.appName || "") + "|" + n.summary

            for (let i = 0; i < root.activeToasts.count; i++) {
                const existing = root.activeToasts.get(i)
                if (existing.mergeKey === mergeKey) {
                    root.activeToasts.set(i, {
                        hash: existing.hash,
                        title: n.summary,
                        body: n.body,
                        urgency: urgency,
                        timeout: timeout,
                        actions: n.actions ? n.actions : [],
                        mergeKey: mergeKey,
                        mergeCount: existing.mergeCount + 1,
                        restartToken: existing.restartToken + 1   // bumped so the toast's expiry Timer restarts
                    })
                    return
                }
            }

            root.activeToasts.append({
                hash: String(n.id) + "-toast",
                                     title: n.summary,
                                     body: n.body,
                                     urgency: urgency,
                                     timeout: timeout,
                                     actions: n.actions ? n.actions : [],
                                     mergeKey: mergeKey,
                                     mergeCount: 1,
                                     restartToken: 0
            })
    }

    function dismissToast(hash) {
        for (let i = 0; i < root.activeToasts.count; i++) {
            if (root.activeToasts.get(i).hash === hash) { root.activeToasts.remove(i); break }
        }
    }

    function dismissAllToasts() {
        root.activeToasts.clear()
    }

    function toggleExpand(hash) {
        expandedHash = (expandedHash === hash) ? "" : hash
    }

    function copy(hash) {
        const n = root._byId[hash]
        if (!n) return
            const text = n.body ? (n.summary + "\n" + n.body) : n.summary
            Quickshell.execDetached(["wl-copy", text])
    }

    function close(hash) {
        const n = root._byId[hash]
        if (n) n.dismiss()
            delete root._byId[hash]
            for (let i = 0; i < list.count; i++) {
                if (list.get(i).hash === hash) { list.remove(i); break }
            }
            if (root.expandedHash === hash) root.expandedHash = ""
                root._refreshEmptyPlaceholder()
    }

    function clearAll() {
        const items = []
        for (let i = 0; i < server.trackedNotifications.count; i++) {
            items.push(server.trackedNotifications.get(i))
        }
        for (const n of items) n.dismiss()
            for (let i = list.count - 1; i >= 0; i--) {
                if (list.get(i).hash !== "") list.remove(i)
            }
            root._byId = {}
            root.expandedHash = ""
            root._refreshEmptyPlaceholder()
    }

    function _refreshEmptyPlaceholder() {
        if (list.count === 0) {
            list.insert(0, { title: "No notifications", body: "", hash: "" })
        }
    }

    function _removeEmptyPlaceholder() {
        for (let i = list.count - 1; i >= 0; i--) {
            if (list.get(i).hash === "") list.remove(i)
        }
    }

    function _watchClosed(n, hash) {
        n.closed.connect(function () {
            delete root._byId[hash]
            for (let i = 0; i < list.count; i++) {
                if (list.get(i).hash === hash) { list.remove(i); break }
            }
            if (root.expandedHash === hash) root.expandedHash = ""
                root._refreshEmptyPlaceholder()
        })
    }

    function _addNotification(n) {
        const hash = String(n.id)
        root._byId[hash] = n
        root._removeEmptyPlaceholder()
        list.insert(0, { title: n.summary, body: n.body, hash: hash })
        root._watchClosed(n, hash)
    }

    property NotificationServer server: NotificationServer {
        keepOnReload: false

        onNotification: (notification) => {
            if (notification.appName === "kwrited") {
                notification.dismiss()
                return
            }

            if (notification.summary === "Volume" || notification.summary === "Brightness" || notification.summary === "Touchpad") {
                notification.dismiss()
                return
            }

            const _lsms = "local system message service"
            if ((notification.appName && notification.appName.toLowerCase().includes(_lsms))
                || (notification.summary && notification.summary.toLowerCase().includes(_lsms))) {
                notification.dismiss()
                return
                }

                if (notification.summary === "Music" && (notification.body === "Stopped" || notification.body === "Playing")) {
                    notification.dismiss()
                    return
                }

                // Transient hint: allowed to flash as a toast, but must not be
                // persisted into the popup/history list.
                if (notification.transient) {
                    root._addToast(notification)
                    return
                }

                notification.tracked = true
                root._addNotification(notification)
                root._addToast(notification)
        }
    }

    Component.onCompleted: root._refreshEmptyPlaceholder()
}
