pragma ComponentBehavior: Bound
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../Services"
import "../Theme"

// Font stack + .ttf/.otf picker. Toggle: qs ipc call fontPicker toggle
// Stack: arrows move, Enter apply, Delete remove, Ctrl+N add, Esc close
// Browse: type = filter, Enter open/add, Backspace up, Esc back
PanelWindow {
    id: picker

    property int selected: 0
    property bool browsing: false
    readonly property int columns: 5
    property bool shown: false
    readonly property int fadeMs: Animations.panelFadeDuration
    readonly property int pageMs: Animations.pageSlideDuration
    readonly property int count: browsing ? FontPicker.rows.length : Theme.fontStack.length

    WlrLayershell.namespace: "quickshell:fontPicker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    implicitWidth: 664
    implicitHeight: 560
    color: "transparent"

    property bool keepMapped: true
    property bool _forceMap: false
    visible: shown || _forceMap || (keepMapped && FontPicker.ready)
    mask: shown ? null : emptyMask
    Region { id: emptyMask }

    function open() {
        hideTimer.stop()
        browsing = false
        selected = 0
        if (picker.visible) shown = true
            else { _forceMap = true; showTimer.restart() }
    }
    function close() { showTimer.stop(); shown = false; hideTimer.restart() }
    function toggle() { shown ? close() : open() }

    function showBrowse() { browsing = true; selected = 0; FontPicker.start() }
    function showStack()  { browsing = false; selected = 0 }

    Timer { id: showTimer; interval: 32; onTriggered: picker.shown = true }
    Timer { id: hideTimer; interval: picker.fadeMs + 60; onTriggered: picker._forceMap = false }

    ClickAwayCloser {
        targetWindows: [picker]
        active: picker.shown
        onDismissed: picker.close()
    }

    function activate(i) {
        if (picker.browsing) {
            const r = FontPicker.rows[i]
            if (!r) return
                if (r.kind === "up") FontPicker.up()
                    else if (r.isDir) FontPicker.enter(r.path)
                        else { FontPicker.pick(r.path); picker.showStack() }
        } else {
            const f = Theme.fontStack[i]
            if (f) Theme.setFont(f.family)
        }
    }

    function removeAt(i) {
        const f = Theme.fontStack[i]
        if (f && !f.builtin) {
            Theme.removeFont(f.family)
            selected = Math.min(selected, Theme.fontStack.length - 2)
        }
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "fontPickerToggle"
        description: "Toggle font picker"
        onPressed: picker.toggle()
    }

    IpcHandler {
        target: "fontPicker"
        function toggle() { picker.toggle() }
        function open() { picker.open() }
        function close() { picker.close() }
    }

    Connections {
        target: FontPicker
        function onRowsChanged() { if (picker.browsing) picker.selected = Math.min(picker.selected, Math.max(0, FontPicker.rows.length - 1)) }
        function onPathChanged() { picker.selected = 0 }
        function onFilterChanged() { picker.selected = 0 }
    }

    FocusScope {
        anchors.fill: parent
        focus: picker.shown

        Keys.onPressed: (event) => {
            const n = picker.count
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            switch (event.key) {
                case Qt.Key_Escape:
                    if (picker.browsing) {
                        if (FontPicker.filter !== "") FontPicker.filter = ""
                            else picker.showStack()
                    } else picker.close()
                        break
                case Qt.Key_Return:
                case Qt.Key_Enter: picker.activate(picker.selected); break
                case Qt.Key_Right:
                    if (ctrl) { Theme.setFontScale(Theme.fontScale + 0.05); break }
                    picker.selected = Math.min(n - 1, picker.selected + 1); break
                case Qt.Key_Left:
                    if (ctrl) { Theme.setFontScale(Theme.fontScale - 0.05); break }
                    picker.selected = Math.max(0, picker.selected - 1); break
                case Qt.Key_Down: picker.selected = Math.min(n - 1, picker.selected + picker.columns); break
                case Qt.Key_Up: picker.selected = Math.max(0, picker.selected - picker.columns); break
                case Qt.Key_PageDown: picker.selected = Math.min(n - 1, picker.selected + picker.columns * 3); break
                case Qt.Key_PageUp: picker.selected = Math.max(0, picker.selected - picker.columns * 3); break
                case Qt.Key_Home: picker.selected = 0; break
                case Qt.Key_End: picker.selected = Math.max(0, n - 1); break
                case Qt.Key_Delete: if (!picker.browsing) picker.removeAt(picker.selected); break
                case Qt.Key_Backspace:
                    if (!picker.browsing) break
                        if (FontPicker.filter !== "") FontPicker.filter = FontPicker.filter.slice(0, -1)
                            else FontPicker.up()
                                break
                default:
                    if (ctrl && event.key === Qt.Key_N && !picker.browsing) picker.showBrowse()
                        else if (picker.browsing && !ctrl && event.text.length === 1 && event.text >= " ")
                            FontPicker.filter += event.text
                            else return
            }
            event.accepted = true
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            anchors.margins: 12
            radius: 18
             color: Theme.opaque ? Theme.popupBg : (Theme.effectiveDark ? Qt.rgba(0.08, 0.08, 0.1, 0.58) : Qt.rgba(0.95, 0.95, 0.96, 0.58))
            border.width: 1
            border.color: Theme.color3

            opacity: picker.shown ? 1 : 0
            scale: picker.shown ? 1 : 0.94
            layer.enabled: true
            layer.smooth: true
            Behavior on opacity { NumberAnimation { duration: picker.fadeMs } }
            Behavior on scale {
                SpringAnimation {
                    spring: Animations.panelSlideSpring
                    damping: Animations.panelSlideDamping
                    mass: Animations.panelSlideMass
                }
            }

            Item {
                id: body
                anchors.fill: parent
                anchors.margins: 16

                // ---- Header: [+ / ←]  title ----
                Item {
                    id: header
                    anchors.top: parent.top
                    width: parent.width
                    height: 26

                    Rectangle {
                        id: modeBtn
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 24
                        radius: 12
                        color: Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, modeMouse.containsMouse ? 0.45 : 0.25)

                        // "+" spins out as "←" spins in
                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            opacity: picker.browsing ? 0 : 1
                            rotation: picker.browsing ? 90 : 0
                            Behavior on opacity { NumberAnimation { duration: picker.pageMs } }
                            Behavior on rotation { NumberAnimation { duration: picker.pageMs; easing.type: Animations.pageSlideEasingOut } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: "\u2190"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            opacity: picker.browsing ? 1 : 0
                            rotation: picker.browsing ? 0 : -90
                            Behavior on opacity { NumberAnimation { duration: picker.pageMs } }
                            Behavior on rotation { NumberAnimation { duration: picker.pageMs; easing.type: Animations.pageSlideEasingOut } }
                        }

                        MouseArea {
                            id: modeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: picker.browsing ? picker.showStack() : picker.showBrowse()
                        }
                    }

                    Text {
                        anchors.left: modeBtn.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: picker.browsing ? (FontPicker.path === "" ? "..." : FontPicker.path) : "Font Stack"
                        elide: Text.ElideLeft
                        color: Theme.color3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                }

                // ---- Pages ----
                Item {
                    id: pages
                    anchors.top: header.bottom
                    anchors.topMargin: 8
                    anchors.bottom: scaleRow.top
                    anchors.bottomMargin: 8
                    width: parent.width
                    clip: true

                    // Page 1: the stack
                    Item {
                        id: stackPage
                        width: parent.width
                        height: parent.height
                        opacity: picker.browsing ? 0 : 1
                        x: picker.browsing ? -24 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: picker.pageMs; easing.type: picker.browsing ? Animations.pageSlideEasingIn : Animations.pageSlideEasingOut } }
                        Behavior on x { NumberAnimation { duration: picker.pageMs; easing.type: picker.browsing ? Animations.pageSlideEasingIn : Animations.pageSlideEasingOut } }

                        GridView {
                            id: stackGrid
                            anchors.fill: parent
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            cellWidth: Math.floor(width / picker.columns)
                            cellHeight: 112
                            model: Theme.fontStack
                            currentIndex: picker.selected
                            onCurrentIndexChanged: if (!picker.browsing) positionViewAtIndex(currentIndex, GridView.Contain)

                            delegate: Item {
                                id: cell
                                required property var modelData
                                required property int index
                                readonly property bool sel: !picker.browsing && index === picker.selected
                                readonly property bool active: modelData.family === Theme.fontFamily
                                width: stackGrid.cellWidth
                                height: stackGrid.cellHeight

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    radius: 12
                                    color: cell.sel ? Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.28) : "transparent"
                                    border.width: cell.active ? 1 : 0
                                    border.color: Theme.color3
                                }

                                // The icon is the font itself
                                Text {
                                    id: sample
                                    anchors.top: parent.top
                                    anchors.topMargin: 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 56
                                    verticalAlignment: Text.AlignVCenter
                                    text: "Aa"
                                    color: Theme.foreground
                                    font.family: cell.modelData.family
                                    font.pixelSize: 38
                                }

                                Text {
                                    anchors.top: sample.bottom
                                    anchors.topMargin: 6
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    text: cell.modelData.label
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    font.bold: cell.active
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: picker.selected = cell.index
                                    onClicked: { picker.selected = cell.index; picker.activate(cell.index) }
                                }

                                // Remove button: top-right of the tile, custom fonts only.
                                // Declared after the MouseArea above so it sits on top.
                                Rectangle {
                                    visible: !cell.modelData.builtin && cell.sel
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: 7
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, delMouse.containsMouse ? 0.55 : 0.3)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "\u2715"
                                        color: Theme.foreground
                                        font.pixelSize: Theme.fontSizeXs
                                    }
                                    MouseArea {
                                        id: delMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: picker.removeAt(cell.index)
                                    }
                                }
                            }
                        }
                    }

                    // Page 2: file browser
                    Item {
                        id: browsePage
                        width: parent.width
                        height: parent.height
                        opacity: picker.browsing ? 1 : 0
                        x: picker.browsing ? 0 : 24
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: picker.pageMs; easing.type: picker.browsing ? Animations.pageSlideEasingOut : Animations.pageSlideEasingIn } }
                        Behavior on x { NumberAnimation { duration: picker.pageMs; easing.type: picker.browsing ? Animations.pageSlideEasingOut : Animations.pageSlideEasingIn } }

                        Text {
                            id: filterText
                            anchors.top: parent.top
                            width: parent.width
                            text: "> " + FontPicker.filter + "▂"
                            elide: Text.ElideRight
                            color: Theme.foreground
                            opacity: FontPicker.filter === "" ? 0.45 : 1
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        Rectangle {
                            id: divider
                            anchors.top: filterText.bottom
                            anchors.topMargin: 8
                            width: parent.width
                            height: 1
                            color: Theme.foreground
                            opacity: 0.12
                        }

                        GridView {
                            id: fileGrid
                            anchors.top: divider.bottom
                            anchors.topMargin: 8
                            anchors.bottom: parent.bottom
                            width: parent.width
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            cellWidth: Math.floor(width / picker.columns)
                            cellHeight: 112
                            model: FontPicker.rows
                            currentIndex: picker.selected
                            onCurrentIndexChanged: if (picker.browsing) positionViewAtIndex(currentIndex, GridView.Contain)

                            delegate: Item {
                                id: fcell
                                required property var modelData
                                required property int index
                                readonly property bool sel: picker.browsing && index === picker.selected
                                width: fileGrid.cellWidth
                                height: fileGrid.cellHeight

                                // Only visible cells exist, so this loads previews lazily
                                FontLoader {
                                    id: fl
                                    source: fcell.modelData.isDir ? "" : "file://" + fcell.modelData.path
                                }

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    radius: 12
                                    color: fcell.sel ? Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.28) : "transparent"
                                }

                                Item {
                                    id: ico
                                    anchors.top: parent.top
                                    anchors.topMargin: 10
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 56
                                    height: 56

                                    Image {
                                        anchors.fill: parent
                                        visible: fcell.modelData.isDir
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                        cache: true
                                        smooth: true
                                        sourceSize: Qt.size(112, 112)
                                        source: fcell.modelData.isDir ? FontPicker.folderIcon : ""
                                        layer.enabled: true
                                        layer.smooth: true
                                        layer.textureSize: Qt.size(112, 112)
                                        layer.effect: ColorOverlay { color: Theme.iconColor }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !fcell.modelData.isDir
                                        text: "Aa"
                                        color: Theme.foreground
                                        font.family: fl.name
                                        font.pixelSize: 38
                                    }
                                }

                                Text {
                                    anchors.top: ico.bottom
                                    anchors.topMargin: 6
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    text: fcell.modelData.label
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                    font.bold: fcell.modelData.isDir
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onEntered: picker.selected = fcell.index
                                    onClicked: { picker.selected = fcell.index; picker.activate(fcell.index) }
                                }
                            }
                        }
                    }
                }

                // ---- Font scale slider (bottom centre) ----
                Item {
                    id: scaleRow
                    anchors.bottom: hint.top
                    anchors.bottomMargin: 8
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 300
                    height: 26

                    readonly property real span: Theme.fontScaleMax - Theme.fontScaleMin
                    readonly property real frac: (Theme.fontScale - Theme.fontScaleMin) / span

                    Text {
                        id: smallA
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "A"
                        color: Theme.foreground
                        opacity: 0.7
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                    }
                    Text {
                        id: pct
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(Theme.fontScale * 100) + "%"
                        color: Theme.color3
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.bold: true
                    }
                    Text {
                        id: bigA
                        anchors.right: pct.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: "A"
                        color: Theme.foreground
                        opacity: 0.7
                        font.family: Theme.fontFamily
                        font.pixelSize: 19
                    }

                    Item {
                        id: track
                        anchors.left: smallA.right
                        anchors.leftMargin: 10
                        anchors.right: bigA.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        height: 20

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Theme.foreground
                            opacity: 0.15
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: handle.x + handle.width / 2
                            height: 4
                            radius: 2
                            color: Theme.color3
                        }
                        Rectangle {
                            id: handle
                            anchors.verticalCenter: parent.verticalCenter
                            width: 14
                            height: 14
                            radius: 7
                            x: scaleRow.frac * (track.width - width)
                            color: Theme.color3
                            border.width: scaleMouse.pressed ? 3 : 0
                            border.color: Qt.rgba(1, 1, 1, 0.35)
                        }
                        MouseArea {
                            id: scaleMouse
                            anchors.fill: parent
                            function setFrom(mx) {
                                const f = Math.max(0, Math.min(1, (mx - handle.width / 2) / (track.width - handle.width)))
                                Theme.setFontScale(Math.round((Theme.fontScaleMin + f * scaleRow.span) * 20) / 20)
                            }
                            onPressed: (m) => setFrom(m.x)
                            onPositionChanged: (m) => { if (pressed) setFrom(m.x) }
                            onDoubleClicked: Theme.setFontScale(1.0)
                        }
                    }
                }

                Text {
                    id: hint
                    anchors.bottom: parent.bottom
                    width: parent.width
                    text: picker.browsing
                    ? (FontPicker.loading ? "Loading..." : "Enter Open/Add  ·  Backspace: Up  ·  Esc: Back")
                    : "Enter Apply  ·  Del: Remove  ·  Ctrl+N: Add  ·  Ctrl+←/→: Scale  ·  Esc: Close"
                    elide: Text.ElideRight
                    color: Theme.foreground
                    opacity: 0.8
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }
        }
    }
}
