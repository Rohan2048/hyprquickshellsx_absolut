pragma ComponentBehavior: Bound
import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../Services"
import "../Theme"
import "../Widgets"

// Music file picker (grid). Toggle with the "musicPickerToggle" global
// shortcut or:  qs ipc call musicPicker toggle
//
// Two pages (Tab or click to switch):
//   Local = file browser    Radio = saved links (paste a URL, Enter to save)
// Keys:  type = filter   arrows = move   Enter = open folder / play file
//        Backspace = parent folder   Ctrl+Enter = play current folder
//        Esc = clear filter / close
//   Radio: Enter = save pasted link (or play selected when the box is empty)
//          Ctrl+D = remove selected link
PanelWindow {
    id: picker

    property int selected: 0
    readonly property int columns: 5
    property bool shown: false
    // Rows of whichever page is showing (Local = files, Radio = saved links).
    readonly property var curRows: MusicPicker.page === "radio" ? MusicPicker.radioRows : MusicPicker.rows
    readonly property int fadeMs: Animations.panelFadeDuration

    WlrLayershell.namespace: "quickshell:musicPicker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Window is panel-sized plus a 12px margin (room for the spring overshoot)
    // instead of a fullscreen layer surface, so there is far less to composite.
    implicitWidth: 664
    implicitHeight: 556
    color: "transparent"

    // Quickshell tears the whole window down when `visible` goes false, so
    // every open used to rebuild the GL context, all textures, every icon
    // layer and the shader pipelines -- that was the GPU spike. After the
    // startup preload the window therefore stays mapped, fully transparent
    // and input-transparent (empty mask), and open/close only fade the panel.
    // Set keepMapped to false to go back to map-on-open (spiky, but no
    // surface exists while closed).
    property bool keepMapped: true
    property bool _forceMap: false
    visible: shown || _forceMap || (keepMapped && MusicPicker.ready)
    mask: shown ? null : emptyMask
    Region { id: emptyMask }

    function open() {
        hideTimer.stop()
        MusicPicker.start()
        selected = 0
        if (picker.visible) {
            shown = true
        } else {
            // Opened before the preload mapped the window: let the surface
            // commit its first frame before the fade starts.
            _forceMap = true
            showTimer.restart()
        }
    }
    function close() {
        showTimer.stop()
        shown = false
        hideTimer.restart()
    }
    function toggle() { shown ? close() : open() }

    // Device hot-plug monitoring only runs while the picker is open.
    onShownChanged: MusicPicker.watching = shown

    Timer {
        id: showTimer
        interval: 32
        onTriggered: picker.shown = true
    }

    Timer {
        id: hideTimer
        interval: picker.fadeMs + 60
        onTriggered: picker._forceMap = false
    }

    ClickAwayCloser {
        targetWindows: [picker]
        active: picker.shown
        onDismissed: picker.close()
    }

    function focusInput() {
        if (MusicPicker.page === "radio") urlInput.forceActiveFocus()
            else scope.forceActiveFocus()
    }

    function activate(i) {
        const r = picker.curRows[i]
        if (!r) return
            if (r.kind === "station") { MusicPicker.play(r.url, false); close(); return }
            if (r.kind === "up") MusicPicker.up()
                else if (r.isDir) MusicPicker.enter(r.path)
                    else { MusicPicker.play(r.path, false); close() }
    }

    GlobalShortcut {
        appid: "quickshell"
        name: "musicPickerToggle"
        description: "Toggle music file picker"
        onPressed: picker.toggle()
    }

    IpcHandler {
        target: "musicPicker"
        function toggle() { picker.toggle() }
        function open() { picker.open() }
        function close() { picker.close() }
    }

    Connections {
        target: MusicPicker
        function onRowsChanged() {
            picker.selected = Math.min(picker.selected, Math.max(0, picker.curRows.length - 1))
        }
        function onPageChanged() { picker.selected = 0; picker.focusInput() }
        function onRadioChanged() {
            picker.selected = Math.min(picker.selected, Math.max(0, picker.curRows.length - 1))
        }
        function onPathChanged() { picker.selected = 0 }
        function onFilterChanged() { picker.selected = 0 }
    }


    FocusScope {
        id: scope
        anchors.fill: parent
        focus: picker.shown

        Keys.onPressed: (event) => {
            const n = picker.curRows.length
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            const radio = MusicPicker.page === "radio"
            switch (event.key) {
                case Qt.Key_Escape:
                    if (!radio && MusicPicker.filter !== "") MusicPicker.filter = ""
                        else if (radio && urlInput.text !== "") urlInput.text = ""
                            else picker.close()
                                break
                case Qt.Key_Tab:
                case Qt.Key_Backtab:
                    MusicPicker.togglePage()
                    break
                case Qt.Key_Return:
                case Qt.Key_Enter:
                    if (ctrl && !radio) { MusicPicker.play(MusicPicker.path, true); picker.close() }
                    else picker.activate(picker.selected)
                        break
                case Qt.Key_Right: picker.selected = Math.min(n - 1, picker.selected + 1); break
                case Qt.Key_Left: picker.selected = Math.max(0, picker.selected - 1); break
                case Qt.Key_Down: picker.selected = Math.min(n - 1, picker.selected + picker.columns); break
                case Qt.Key_Up: picker.selected = Math.max(0, picker.selected - picker.columns); break
                case Qt.Key_PageDown: picker.selected = Math.min(n - 1, picker.selected + picker.columns * 3); break
                case Qt.Key_PageUp: picker.selected = Math.max(0, picker.selected - picker.columns * 3); break
                case Qt.Key_Home: picker.selected = 0; break
                case Qt.Key_End: picker.selected = Math.max(0, n - 1); break
                case Qt.Key_Backspace:
                    if (radio) return
                        if (MusicPicker.filter !== "") MusicPicker.filter = MusicPicker.filter.slice(0, -1)
                            else MusicPicker.up()
                                break
                default:
                    if (ctrl && event.key === Qt.Key_S) MusicPicker.stop()
                        else if (ctrl && radio && event.key === Qt.Key_D) MusicPicker.removeRadio(picker.selected)
                            else if (!ctrl && !radio && event.text.length === 1 && event.text >= " ")
                                MusicPicker.filter += event.text
                                else return
            }
            event.accepted = true
        }

        Rectangle {
            id: panel
            anchors.fill: parent
            anchors.margins: 12
            radius: BorderSettings.radiusFor(18)
            color: Theme.popupPaintBg

            // gradient / image of a custom theme (paints nothing for solid fills)
            ThemeFill { anchors.fill: parent; fill: Theme.popupFill; radius: panel.radius }

            // Same motion as WorkspaceOverview: fade + small spring scale.
            // The panel lives in one permanent texture, so the GPU animates a
            // single quad instead of re-drawing the whole grid every frame, and
            // nothing is allocated or freed per open.
            opacity: picker.shown ? 1 : 0
            scale: picker.shown ? 1 : 0.94
            layer.enabled: true
            layer.smooth: true
            Behavior on opacity { NumberAnimation { id: fadeAnim; duration: picker.fadeMs } }
            Behavior on scale {
                SpringAnimation {
                    id: scaleAnim
                    spring: Animations.panelSlideSpring
                    damping: Animations.panelSlideDamping
                    mass: Animations.panelSlideMass
                }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                // Local | Radio
                Row {
                    id: pageBar
                    spacing: 6

                    Repeater {
                        model: [{ id: "local", label: "Local" }, { id: "radio", label: "Radio" }]

                        Rectangle {
                            id: pageChip
                            required property var modelData
                            readonly property bool active: MusicPicker.page === modelData.id
                            height: 24
                            width: pageChipText.implicitWidth + 28
                            radius: 12
                            color: active
                            ? Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.30)
                            : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, pageMouse.containsMouse ? 0.12 : 0.06)

                            Text {
                                id: pageChipText
                                anchors.centerIn: parent
                                text: pageChip.modelData.label
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                font.bold: pageChip.active
                            }

                            MouseArea {
                                id: pageMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: MusicPicker.page = pageChip.modelData.id
                            }
                        }
                    }
                }

                Item {
                    id: headerRow
                    width: parent.width
                    height: 26

                    Text {
                        anchors.left: parent.left
                        anchors.right: playBtn.visible ? playBtn.left : stopBtn.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: MusicPicker.page === "radio" ? "Saved links: " + MusicPicker.radio.length
                        : (MusicPicker.path === "" ? "..." : MusicPicker.path)
                        elide: Text.ElideLeft
                        color: Theme.color3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    Rectangle {
                        id: playBtn
                        visible: MusicPicker.page === "local"
                        anchors.right: stopBtn.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 104
                        height: 24
                        radius: 12
                        readonly property bool on: MusicPicker.path !== ""
                        color: on ? (playMouse.containsMouse ? Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.45)
                        : Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.25))
                        : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.05)
                        opacity: on ? 1 : 0.4

                        Text {
                            anchors.centerIn: parent
                            text: "\u25B6  Play Folder"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }

                        MouseArea {
                            id: playMouse
                            anchors.fill: parent
                            enabled: playBtn.on
                            hoverEnabled: true
                            onClicked: { MusicPicker.play(MusicPicker.path, true); picker.close() }
                        }
                    }

                    Rectangle {
                        id: stopBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 72
                        height: 24
                        radius: 12
                        readonly property bool on: MusicPicker.mpvRunning
                        color: on ? (stopMouse.containsMouse ? Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.45)
                        : Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.25))
                        : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.05)
                        opacity: on ? 1 : 0.4

                        Text {
                            anchors.centerIn: parent
                            text: "\u25A0  Stop"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }

                        MouseArea {
                            id: stopMouse
                            anchors.fill: parent
                            enabled: stopBtn.on
                            hoverEnabled: true
                            onClicked: MusicPicker.stop()
                        }
                    }
                }

                // Shown only while an external device is connected.
                Flow {
                    id: deviceBar
                    width: parent.width
                    spacing: 6
                    visible: MusicPicker.page === "local" && MusicPicker.deviceTabs.length > 0

                    Repeater {
                        model: MusicPicker.deviceTabs

                        Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool isInternal: modelData.kind === "internal"
                            height: 24
                            readonly property bool canEject: !isInternal && modelData.mounted
                            width: chipText.implicitWidth + 24 + (canEject ? 22 : 0)
                            radius: 12
                            color: modelData.active
                            ? Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.30)
                            : Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, chipMouse.containsMouse ? 0.12 : 0.06)
                            opacity: isInternal || modelData.mounted ? 1 : 0.6

                            Text {
                                id: chipText
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: chip.isInternal ? "Internal"
                                : (chip.modelData.mounted ? chip.modelData.label : chip.modelData.label + "  \u00B7  mount")
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                font.bold: chip.modelData.active
                            }

                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: chip.isInternal ? MusicPicker.goInternal() : MusicPicker.openDevice(chip.modelData)
                            }

                            // Eject: only on mounted external devices
                            Item {
                                visible: chip.canEject
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: 24

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u23CF"
                                    color: Theme.foreground
                                    opacity: ejectMouse.containsMouse ? 1 : 0.6
                                    font.pixelSize: Theme.fontSize
                                }
                                MouseArea {
                                    id: ejectMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: MusicPicker.eject(chip.modelData)
                                }
                            }
                        }
                    }
                }

                Text {
                    id: filterText
                    width: parent.width
                    visible: MusicPicker.page === "local"
                    text: "> " + MusicPicker.filter + "▂"
                    elide: Text.ElideRight
                    color: Theme.foreground
                    opacity: MusicPicker.filter === "" ? 0.45 : 1
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                // Radio page: paste a link here, Enter (or Save) stores it.
                Rectangle {
                    id: urlRow
                    width: parent.width
                    height: 28
                    radius: 8
                    visible: MusicPicker.page === "radio"
                    color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.06)
                    border.width: urlInput.activeFocus ? 1 : 0
                    border.color: Theme.color3

                    TextInput {
                        id: urlInput
                        anchors.left: parent.left
                        anchors.right: saveBtn.left
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        focus: picker.shown && MusicPicker.page === "radio"
                        color: Theme.foreground
                        selectionColor: Theme.color3
                        selectByMouse: true
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        onAccepted: {
                            if (text.trim() === "") picker.activate(picker.selected)
                                else if (MusicPicker.addRadio(text)) text = ""
                        }
                    }

                    Text {
                        anchors.left: urlInput.left
                        anchors.right: urlInput.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: urlInput.text === ""
                        text: "Paste a stream / YouTube / radio link, then Enter"
                        elide: Text.ElideRight
                        color: Theme.foreground
                        opacity: 0.45
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    Rectangle {
                        id: saveBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 64
                        height: 22
                        radius: 11
                        color: Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, saveMouse.containsMouse ? 0.45 : 0.25)

                        Text {
                            anchors.centerIn: parent
                            text: "Save"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }

                        MouseArea {
                            id: saveMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { if (MusicPicker.addRadio(urlInput.text)) urlInput.text = ""; picker.focusInput() }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.foreground; opacity: 0.12 }

                GridView {
                    id: list
                    width: parent.width
                    height: Math.max(0, parent.height - (pageBar.height + 8) - (headerRow.height + 8)
                    - (deviceBar.visible ? deviceBar.height + 8 : 0)
                    - (urlRow.visible ? urlRow.height : filterText.height) - 8
                    - 9 - footerText.height - 8)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    cellWidth: Math.floor(width / picker.columns)
                    cellHeight: 112
                    model: picker.curRows
                    currentIndex: picker.selected
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, GridView.Contain)

                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        readonly property bool sel: index === picker.selected
                        width: list.cellWidth
                        height: list.cellHeight
                        readonly property bool hasThumb: (modelData.thumb || "") !== ""
                        readonly property bool thumbOk: hasThumb && thumbImg.status === Image.Ready

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: 12
                            color: cell.sel ? Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b, 0.28) : "transparent"
                        }

                        // Same method as Bar.qml: the icon's own layer is tinted with
                        // Theme.iconColor, which follows the light/dark theme. The Bar
                        // already uses this ColorOverlay, so its shader is compiled by
                        // the time the picker opens.
                        Image {
                            id: ico
                            anchors.top: parent.top
                            anchors.topMargin: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 56
                            height: 56
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
                            smooth: true
                            sourceSize: Qt.size(112, 112)
                            visible: !cell.thumbOk
                            source: cell.modelData.isDir ? MusicPicker.folderIcon : MusicPicker.musicIcon

                            layer.enabled: true
                            layer.smooth: true
                            layer.textureSize: Qt.size(112, 112)
                            layer.effect: ColorOverlay { color: Theme.iconColor }
                        }

                        // Radio thumbnail (only when one was found), rounded like the tiles.
                        Image {
                            id: thumbImg
                            anchors.fill: ico
                            visible: false
                            asynchronous: true
                            cache: true
                            smooth: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(112, 112)
                            source: cell.hasThumb ? "file://" + cell.modelData.thumb : ""
                        }
                        Rectangle { id: thumbMask; anchors.fill: ico; radius: 10; visible: false }
                        OpacityMask {
                            anchors.fill: ico
                            visible: cell.thumbOk
                            source: thumbImg
                            maskSource: thumbMask
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
                            text: cell.modelData.label + (cell.modelData.loading ? " …" : "")
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                            font.bold: cell.modelData.isDir
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: picker.selected = cell.index
                            onClicked: { picker.selected = cell.index; picker.activate(cell.index) }
                        }

                        // Remove a saved link (also Ctrl+D)
                        Rectangle {
                            visible: cell.modelData.kind === "station" && cell.sel
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.topMargin: 6
                            anchors.rightMargin: 6
                            width: 18
                            height: 18
                            radius: 9
                            color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, delMouse.containsMouse ? 0.30 : 0.15)

                            Text {
                                anchors.centerIn: parent
                                text: "\u00D7"
                                color: Theme.foreground
                                font.pixelSize: Theme.fontSize
                            }
                            MouseArea {
                                id: delMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: MusicPicker.removeRadio(cell.index)
                            }
                        }
                    }
                }

                Text {
                    id: footerText
                    width: parent.width
                    text: MusicPicker.page === "radio"
                    ? (MusicPicker.radioBusy ? "Fetching name & thumbnail..." :
                    "Enter: Save link / Play  ·  Ctrl+D: Remove  ·  Ctrl+S: Stop  ·  Tab: Local  ·  Esc: Close")
                    : MusicPicker.mounting ? "Working..." : MusicPicker.loading ? "Loading..." :
                    "Enter Open/Play  ·  Ctrl+Enter: Play folder  ·  Ctrl+S: Stop  ·  Backspace: Back  ·  Tab: Radio  ·  Esc: Close"
                    elide: Text.ElideRight
                    color: Theme.foreground
                    opacity: 0.4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }

            Text {
                visible: MusicPicker.page === "radio" && MusicPicker.radio.length === 0
                x: 16
                y: 16 + list.y + 24
                width: panel.width - 32
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "No saved links yet.\nPaste a stream or YouTube link above and press Enter."
                color: Theme.foreground
                opacity: 0.5
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }

        // Border: on / off, thickness, colour, effects and radius all from Settings > Theme > Border.
        // It sits NEXT to the panel, not inside it: the panel is rendered as one texture (layer.enabled)
        // and a texture cuts off everything drawn outside the panel's edge -- which is exactly where the
        // wavy streaks and the x / o marks go. This item copies the panel's fade + scale so it moves with it.
        Item {
            anchors.fill: panel
            opacity: panel.opacity
            scale: panel.scale
            PanelBorder { tl: panel.radius; tr: panel.radius; bl: panel.radius; br: panel.radius }
        }
    }
}
