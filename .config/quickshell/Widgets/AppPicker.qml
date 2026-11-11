import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "../Theme"
import "../Services"

// Search box + the installed applications, as a grid (default, like the rofi theme) or a
// list with descriptions. The view button sits at the top right and is remembered
// (PopupSettings apps.view).
//
// Apps come from Quickshell's DesktopEntries, i.e. the standard XDG way every desktop uses:
// every `applications/` folder of $XDG_DATA_HOME and $XDG_DATA_DIRS (system, ~/.local, source
// installs under /usr/local, and Flatpak / Snap exports when their share dir is in
// XDG_DATA_DIRS, which their installers set up). NoDisplay / Hidden entries are skipped.
//
// It only emits picked(entry); the owner decides what picking means (launch, add shortcut...).
Item {
    id: root

    property string placeholder: "Search applications..."
    // the main layout, for Widgets/PopupArrange (Settings > Popups > Popup styles)
    property alias topCol: topCol
    // a row of the most used apps above the list while the search is empty (Settings > Popups > Applications)
    property bool suggest: false
    // in the Settings preview there may be no usage yet: show a few apps so the row can be arranged
    readonly property bool sample: !!root.host && root.host.preview === true
    property var host: null
    readonly property var suggested: {
        if (!root.suggest) return []
            const withUse = []
            for (let i = 0; i < root.apps.length; i++) {
                const n = PopupSettings.appUses(root.apps[i].id)
                if (n > 0) withUse.push({ e: root.apps[i], n: n })
            }
            withUse.sort(function (a, b) { return b.n - a.n || a.e.name.localeCompare(b.e.name) })
            let out = withUse.slice(0, 6).map(function (h) { return h.e })
            if (out.length === 0 && root.sample) out = root.apps.slice(0, 4)
                return out
    }
    signal picked(var entry)
    signal dismissed()

    readonly property bool listMode: PopupSettings.appsView === "list"
    property int current: 0

    function reset() { search.text = ""; root.current = 0; search.forceActiveFocus() }
    function focusSearch() { search.forceActiveFocus() }

    // ---------------- data ----------------
    readonly property var apps: {
        const raw = DesktopEntries.applications.values
        const out = []
        for (let i = 0; i < raw.length; i++) if (!raw[i].noDisplay) out.push(raw[i])
            out.sort(function (a, b) { return a.name.localeCompare(b.name) })
            return out
    }

    function _score(e, q) {
        const n = e.name.toLowerCase()
        if (n.startsWith(q)) return 0
            if (n.indexOf(q) >= 0) return 1
                if ((e.genericName || "").toLowerCase().indexOf(q) >= 0) return 2
                    if ((e.id || "").toLowerCase().indexOf(q) >= 0) return 3
                        const kw = e.keywords || []
                        for (let i = 0; i < kw.length; i++) if (String(kw[i]).toLowerCase().indexOf(q) >= 0) return 4
                            if ((e.comment || "").toLowerCase().indexOf(q) >= 0) return 5
                                return -1
    }

    readonly property var filtered: {
        const q = search.text.trim().toLowerCase()
        if (q === "") return root.apps
            const hits = []
            for (let i = 0; i < root.apps.length; i++) {
                const sc = root._score(root.apps[i], q)
                if (sc >= 0) hits.push({ e: root.apps[i], sc: sc })
            }
            hits.sort(function (a, b) { return a.sc - b.sc || a.e.name.localeCompare(b.e.name) })
            return hits.map(function (h) { return h.e })
    }
    onFilteredChanged: root.current = 0

    function iconSrc(e) {
        const ic = e.icon
        if (!ic) return Quickshell.iconPath("application-x-executable", true)
            if (ic.startsWith("/")) return "file://" + ic.replace(/^\/home\/[^\/]+\/\.config\/quickshell\//, Quickshell.env("HOME") + "/.config/quickshell/")
                return Quickshell.iconPath(ic, "application-x-executable")
    }
    function describe(e) {
        return e.comment ? e.comment : (e.genericName ? e.genericName : "")
    }

    readonly property int cols: Math.max(3, Math.floor(view.width / 128))
    function pick(i) {
        if (i >= 0 && i < root.filtered.length) root.picked(root.filtered[i])
    }
    function move(delta) {
        const n = root.filtered.length
        if (n === 0) return
            root.current = Math.max(0, Math.min(n - 1, root.current + delta))
    }

    // ---------------- header: search + view toggle ----------------
    ColumnLayout {
        id: topCol
        anchors.fill: parent
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            TextField {
                id: search
                Layout.fillWidth: true
                implicitHeight: 34
                selectByMouse: true
                placeholderText: root.placeholder
                color: Theme.foreground
                placeholderTextColor: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                // border follows Settings > Theme > Border
                background: FieldBorder { radius: Theme.radiusSm; focused: search.activeFocus }
                Keys.onPressed: (event) => {
                    switch (event.key) {
                        case Qt.Key_Escape: root.dismissed(); event.accepted = true; break
                        case Qt.Key_Return:
                        case Qt.Key_Enter: root.pick(root.current); event.accepted = true; break
                        case Qt.Key_Down: root.move(root.listMode ? 1 : root.cols); event.accepted = true; break
                        case Qt.Key_Up: root.move(root.listMode ? -1 : -root.cols); event.accepted = true; break
                        case Qt.Key_Right: if (!root.listMode) { root.move(1); event.accepted = true } break
                        case Qt.Key_Left: if (!root.listMode) { root.move(-1); event.accepted = true } break
                        case Qt.Key_Tab: root.move(1); event.accepted = true; break
                        case Qt.Key_Backtab: root.move(-1); event.accepted = true; break
                    }
                }
            }

            GlassButton {
                implicitHeight: 34
                arrangeId: "View"
                text: root.listMode ? "Grid view" : "List view"
                onClicked: { PopupSettings.put("apps", "view", root.listMode ? null : "list"); search.forceActiveFocus() }
            }
        }

        // ---- suggestions: one object for the whole row (the apps inside it are not separate objects) ----
        Row {
            id: suggestRow
            visible: root.suggested.length > 0 && search.text.trim() === ""
            Layout.alignment: Qt.AlignHCenter
            spacing: 6
            Repeater {
                model: root.suggested
                delegate: Item {
                    id: sg
                    required property var modelData
                    readonly property bool noArrange: true
                    width: 96; height: 84
                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: sgMouse.containsMouse ? Theme.hoverBg : "transparent"
                    }
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 10
                        spacing: 4
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 40; height: 40
                            source: root.iconSrc(sg.modelData)
                            sourceSize: Qt.size(80, 80)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            asynchronous: true
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: sg.modelData.name
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }
                    MouseArea {
                        id: sgMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.picked(sg.modelData)
                    }
                }
            }
        }

        Item {
            id: view
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
                visible: root.filtered.length === 0
                anchors.centerIn: parent
                text: root.apps.length === 0 ? "Reading applications..." : "No applications match"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            // ---- grid ----
            GridView {
                id: grid
                anchors.fill: parent
                visible: !root.listMode
                clip: true
                cellWidth: Math.floor(width / root.cols)
                cellHeight: 108
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: root.current
                highlightMoveDuration: 0
                model: ScriptModel { values: root.listMode ? [] : root.filtered; objectProp: "id" }
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index
                    readonly property bool sel: root.current === index
                    width: grid.cellWidth
                    height: grid.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 3
                        radius: 10
                        color: cell.sel ? Theme.accentActive : (ma.containsMouse ? Theme.hoverBg : "transparent")
                    }
                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 14
                        spacing: 6
                        Image {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 48; height: 48
                            source: root.iconSrc(cell.modelData)
                            sourceSize: Qt.size(96, 96)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            asynchronous: true
                        }
                        Text {
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: cell.modelData.name
                            color: cell.sel ? Theme.textOnAccent : Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.current = cell.index
                        onClicked: root.pick(cell.index)
                    }
                }
            }

            // ---- list (with descriptions) ----
            ListView {
                id: list
                anchors.fill: parent
                visible: root.listMode
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: root.current
                highlightMoveDuration: 0
                model: ScriptModel { values: root.listMode ? root.filtered : []; objectProp: "id" }
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sel: root.current === index
                    readonly property string desc: root.describe(modelData)
                    width: list.width
                    height: 52

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: row.sel ? Theme.accentActive : (rma.containsMouse ? Theme.hoverBg : "transparent")
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12
                        Image {
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 34
                            source: root.iconSrc(row.modelData)
                            sourceSize: Qt.size(68, 68)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            mipmap: true
                            asynchronous: true
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row.modelData.name
                                color: row.sel ? Theme.textOnAccent : Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: row.desc !== ""
                                elide: Text.ElideRight
                                text: row.desc
                                color: row.sel ? Theme.textOnAccent : Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                            }
                        }
                    }
                    MouseArea {
                        id: rma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.current = row.index
                        onClicked: root.pick(row.index)
                    }
                }
            }
        }
    }
}
