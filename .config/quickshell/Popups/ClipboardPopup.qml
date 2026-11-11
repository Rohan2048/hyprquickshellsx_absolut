import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// Quickshell version of the rofi clipboard history (`cliphist list | rofi -dmenu ... | cliphist decode | wl-copy`):
// a centred panel with a search box and the history, newest first. Used when Settings > Popups >
// Clipboard history has Style = Quickshell; the keybind (scripts/clipboard.sh) calls
//     qs ipc call clipboard toggle
// Enter copies the entry (cliphist decode | wl-copy) and closes. Same fade + spring scale as the launcher,
// drawn with the shell theme and the Theme > Border settings.
PanelWindow {
    id: popup

    readonly property bool shown: PopupSettings.clipboardOpen
    property bool _closing: false
    readonly property int fadeMs: Animations.panelFadeDuration

    readonly property real scrW: popup.screen ? popup.screen.width : 1920
    readonly property real scrH: popup.screen ? popup.screen.height : 1080

    // tell Settings the panel size this screen really gives (its live preview uses it, so the two always match)
    function _reportBase() { PopupSettings.reportBase("clipboard", Math.max(480, Math.min(820, popup.scrW * 0.35)), Math.max(360, Math.min(700, popup.scrH * 0.5))) }
    onScrWChanged: popup._reportBase()
    onScrHChanged: popup._reportBase()
    onVisibleChanged: if (visible) popup._reportBase()
    Component.onCompleted: popup._reportBase()

    visible: shown || _closing
    color: "transparent"
    exclusiveZone: 0
    // No anchors: centred by the compositor. Same proportions as the rofi theme (35% x 50%).
    implicitWidth: Math.round(Math.max(480, Math.min(820, scrW * 0.35))) + 24 + PopupSettings.sizeW("clipboard")
    implicitHeight: Math.round(Math.max(360, Math.min(700, scrH * 0.5))) + 24 + PopupSettings.sizeH("clipboard")

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:clipboard"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function open() { PopupSettings.clipboardOpen = true }
    function close() { PopupSettings.clipboardOpen = false }
    function toggle() { PopupSettings.clipboardOpen = !PopupSettings.clipboardOpen }

    // ---- the history ----
    // { id, text, image, info }  (cliphist list: "<id>\t<one-line preview>", images read "[[ binary data 34 KiB png 1280x720 ]]")
    property var entries: []
    property string query: ""
    property int cur: 0
    property bool wipeArmed: false
    property bool loaded: false

    readonly property var filtered: {
        const q = popup.query.trim().toLowerCase()
        if (q === "") return popup.entries
            return popup.entries.filter(function (e) { return (e.image ? "image " + e.info : e.text).toLowerCase().indexOf(q) >= 0 })
    }
    onFilteredChanged: popup.cur = Math.max(0, Math.min(popup.cur, popup.filtered.length - 1))

    function parse(raw) {
        const out = []
        const lines = raw.split("\n")
        for (let i = 0; i < lines.length; i++) {
            const ln = lines[i]
            const t = ln.indexOf("\t")
            if (t <= 0) continue
                const id = ln.substring(0, t)
                const body = ln.substring(t + 1)
                const m = /^\[\[ binary data (.*) \]\]$/.exec(body)
                out.push({ id: id, text: body, image: m !== null, info: m ? m[1] : "" })
        }
        popup.entries = out
        popup.loaded = true
        popup.cur = 0
    }
    function refresh() { if (!lister.running) lister.running = true }

    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector { onStreamFinished: popup.parse(text) }
    }

    function pick(entry) {
        if (!entry) return
            Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "_", entry.id])
            popup.close()
    }
    function remove(entry) {
        if (!entry) return
            Quickshell.execDetached(["sh", "-c", "printf '%s\\t\\n' \"$1\" | cliphist delete", "_", entry.id])
            popup.entries = popup.entries.filter(function (e) { return e.id !== entry.id })
    }
    function wipe() {
        Quickshell.execDetached(["cliphist", "wipe"])
        popup.entries = []
        popup.wipeArmed = false
    }
    function move(d) {
        const n = popup.filtered.length
        if (n === 0) return
            popup.cur = Math.max(0, Math.min(n - 1, popup.cur + d))
            body.list.positionViewAtIndex(popup.cur, ListView.Contain)
    }

    onShownChanged: {
        if (shown) {
            hideTimer.stop()
            _closing = false
            query = ""
            wipeArmed = false
            cur = 0
            refresh()
            focusTimer.restart()
        } else {
            _closing = true
            hideTimer.restart()
        }
    }
    Timer { id: hideTimer; interval: popup.fadeMs + 60; onTriggered: popup._closing = false }
    Timer { id: focusTimer; interval: 60; onTriggered: { body.search.text = ""; body.search.forceActiveFocus() } }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.shown
        onDismissed: popup.close()
    }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { popup.toggle() }
        function open(): void { popup.open() }
        function close(): void { popup.close() }
    }

    Item {
        anchors.fill: parent
        anchors.margins: 12
        opacity: popup.shown ? 1 : 0
        scale: popup.shown ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: popup.fadeMs } }
        Behavior on scale {
            SpringAnimation {
                spring: Animations.panelSlideSpring
                damping: Animations.panelSlideDamping
                mass: Animations.panelSlideMass
            }
        }

        GlassPanel {
            anchors.fill: parent
            radius: PopupSettings.radiusOf("clipboard")

            ClipboardContent {
                id: body
                anchors.fill: parent
                host: popup
            }

        }
    }
}
