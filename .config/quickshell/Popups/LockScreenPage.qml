import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Lock screen > Layout: your own lock screen layouts (see Services/LockPresets.qml).
//   list   Default (the lock screen as it always was) + your presets: Apply / Edit / Delete, Create
//   edit   a big live preview you can drag things around in, and per element controls:
//          clock (+ date), password, power buttons, settings button (+ push), battery,
//          background (blur or a wallpaper), shapes (filled / hollow, theme fills)
//   browse pick an image (wallpaper, or a shape's pattern)
Item {
    id: page

    property string mode: "list"            // "list" | "edit" | "browse"
    property var draft: null
    property string focusId: LockPresets.active
    property string section: "clock"        // clock password power settings battery user text bg shapes notes
    property string sel: "clock"            // highlighted in the preview
    property int shapeSel: -1
    property int noteSel: -1
    property string openKey: ""
    property string browseFor: "bg"
    property bool showPush: false

    readonly property var shownLayout: {
        if (page.mode !== "list" && page.draft) return page.draft.layout
            const p = LockPresets.presetById(page.focusId)
            return p ? p.layout : LockPresets.classic()
    }
    // The layout being edited and the selected shape. Plain properties refreshed by sync() whenever the
    // draft or the selection changes (every control below reads these, so each edit updates them all).
    property var lay: null
    property var shape: null
    property var note: null
    function sync() {
        const l = page.draft ? page.draft.layout : null
        page.lay = l
        page.note = (l && page.noteSel >= 0 && page.noteSel < l.notes.length) ? l.notes[page.noteSel] : null
        page.shape = (l && page.shapeSel >= 0 && page.shapeSel < l.shapes.length) ? l.shapes[page.shapeSel] : null
    }
    onDraftChanged: page.sync()
    onShapeSelChanged: page.sync()
    onNoteSelChanged: page.sync()
    readonly property var sections: [
        { id: "clock", label: "Clock / date" }, { id: "password", label: "Password" },
        { id: "power", label: "Power buttons" }, { id: "settings", label: "Settings button" },
        { id: "battery", label: "Battery" }, { id: "user", label: "User / picture" },
        { id: "text", label: "Text colour" }, { id: "bg", label: "Background" }, { id: "shapes", label: "Shapes" }, { id: "notes", label: "Notes" }
    ]
    property bool hasPos: true
    onSectionChanged: page.hasPos = ["clock", "password", "power", "settings", "battery", "user"].indexOf(page.section) >= 0
    readonly property var spots: [
        { l: "Top left", x: 0, y: 0 }, { l: "Top", x: 0.5, y: 0 }, { l: "Top right", x: 1, y: 0 },
        { l: "Left", x: 0, y: 0.5 }, { l: "Centre", x: 0.5, y: 0.5 }, { l: "Right", x: 1, y: 0.5 },
        { l: "Bottom left", x: 0, y: 1 }, { l: "Bottom", x: 0.5, y: 1 }, { l: "Bottom right", x: 1, y: 1 }
    ]

    component SectionLabel: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        Layout.preferredWidth: 110
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 6
    }
    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    component Hr: Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }
    component OnOff: Row {
        id: oo
        property bool value: false
        signal choose(bool v)
        spacing: 6
        GlassButton { text: "On"; active: oo.value; onClicked: oo.choose(true) }
        GlassButton { text: "Off"; active: !oo.value; onClicked: oo.choose(false) }
    }
    component PctRow: RowLayout {
        id: pr
        property string label: ""
        property real value: 0          // 0..1
        property real from: 0
        property real to: 1
        signal committed(real v)
        Layout.fillWidth: true
        spacing: 10
        SectionLabel { text: pr.label }
        GlassSlider {
            Layout.fillWidth: true; Layout.preferredHeight: 26
            min: pr.from * 100; max: pr.to * 100
            value: pr.value * 100
            onValueCommitted: (v) => pr.committed(v / 100)
        }
        Text {
            text: Math.round(pr.value * 100) + " %"
            color: Theme.foreground
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
            Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight
        }
    }

    // whole-number slider with a unit ("points", "%", "px" ...)
    component NumRow: RowLayout {
        id: nr
        property string label: ""
        property real value: 0
        property real from: 0
        property real to: 10
        property string unit: ""
        signal committed(int v)
        Layout.fillWidth: true
        spacing: 10
        SectionLabel { text: nr.label }
        GlassSlider {
            Layout.fillWidth: true; Layout.preferredHeight: 26
            min: nr.from; max: nr.to
            value: nr.value
            onValueCommitted: (v) => nr.committed(Math.round(v))
        }
        Text {
            text: Math.round(nr.value) + (nr.unit !== "" ? " " + nr.unit : "")
            color: Theme.foreground
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
            Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight
        }
    }

    component PxRow: RowLayout {
        id: xr
        property string label: ""
        property real value: 0
        property real from: -300
        property real to: 300
        signal committed(real v)
        Layout.fillWidth: true
        spacing: 10
        SectionLabel { text: xr.label }
        GlassSlider {
            Layout.fillWidth: true; Layout.preferredHeight: 26
            min: xr.from; max: xr.to
            value: xr.value
            onValueCommitted: (v) => xr.committed(v)
        }
        Text {
            text: Math.round(xr.value) + " px"
            color: Theme.foreground
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
            Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight
        }
    }

    // ---- draft helpers ----
    function mutate(fn) {
        const d = LockPresets.clone(page.draft)
        fn(d)
        page.draft = d
    }
    function setPos(key, fx, fy) {
        page.mutate(function (d) {
            const t = key.indexOf("note:") === 0 ? d.layout.notes[parseInt(key.slice(5))] : d.layout[key]
            if (!t) return
                t.fx = fx; t.fy = fy
                if (key === "password") d.layout.password.follow = false
        })
    }
    // stretched by a handle in the preview (the top-left corner stays put, so fx / fy follow)
    function setScale(key, sx, sy, fx, fy) {
        page.mutate(function (d) {
            const t = key.indexOf("note:") === 0 ? d.layout.notes[parseInt(key.slice(5))] : d.layout[key]
            if (!t) return
                t.sx = sx; t.sy = sy; t.fx = fx; t.fy = fy
        })
    }
    function setLayoutKey(key, prop, v) { page.mutate(function (d) { d.layout[key][prop] = v }) }
    function startEdit(p) {
        page.openKey = ""
        page.draft = LockPresets.clone(p)
        page.shapeSel = -1
        page.noteSel = -1
        page.showPush = false
        page.section = "clock"; page.sel = "clock"
        page.mode = "edit"
    }
    function leaveEdit() { page.draft = null; page.openKey = ""; page.mode = "list" }
    function setSection(s) {
        page.openKey = ""
        page.section = s
        if (s === "shapes") page.sel = (page.shape !== null) ? "shape:" + page.shapeSel : ""
            else if (s === "notes") page.sel = (page.note !== null) ? "note:" + page.noteSel : ""
                else if (s === "bg" || s === "text") page.sel = ""
                    else page.sel = s
    }
    function onPicked(key) {
        page.openKey = ""
        if (key === "") { page.sel = ""; return }
        if (key.indexOf("shape:") === 0) { page.shapeSel = parseInt(key.slice(6)); page.section = "shapes" }
        else if (key.indexOf("note:") === 0) { page.noteSel = parseInt(key.slice(5)); page.section = "notes" }
        else page.section = key
            page.sel = key
    }
    function addShape(kind) {
        page.mutate(function (d) { if (d.layout.shapes.length < 40) d.layout.shapes.push(LockPresets.newShape(kind)) })
        page.shapeSel = page.draft.layout.shapes.length - 1
        page.section = "shapes"
        page.sel = "shape:" + page.shapeSel
    }
    function addNote(kind) {
        page.mutate(function (d) { if (d.layout.notes.length < 8) d.layout.notes.push(LockPresets.newNote(kind)) })
        page.noteSel = page.draft.layout.notes.length - 1
        page.section = "notes"
        page.sel = "note:" + page.noteSel
    }
    function setNote(prop, v) { page.mutate(function (d) { d.layout.notes[page.noteSel][prop] = v }) }
    function removeNote() {
        const i = page.noteSel
        if (i < 0) return
            page.mutate(function (d) { d.layout.notes.splice(i, 1) })
            page.noteSel = Math.min(i, page.draft.layout.notes.length - 1)
            page.sel = page.noteSel >= 0 ? "note:" + page.noteSel : ""
    }
    function dupNote() {
        const i = page.noteSel
        if (i < 0 || page.draft.layout.notes.length >= 8) return
            page.mutate(function (d) {
                const c = LockPresets.clone(d.layout.notes[i])
                c.id = LockPresets.newId("n"); c.fx = Math.min(1, c.fx + 0.04); c.fy = Math.min(1, c.fy + 0.04)
                d.layout.notes.push(c)
            })
            page.noteSel = page.draft.layout.notes.length - 1
            page.sel = "note:" + page.noteSel
    }
    function setShape(prop, v) { page.mutate(function (d) { d.layout.shapes[page.shapeSel][prop] = v }) }
    function removeShape() {
        const i = page.shapeSel
        if (i < 0) return
            page.mutate(function (d) { d.layout.shapes.splice(i, 1) })
            page.shapeSel = Math.min(i, page.draft.layout.shapes.length - 1)
            page.sel = page.shapeSel >= 0 ? "shape:" + page.shapeSel : ""
    }
    function dupShape() {
        const i = page.shapeSel
        if (i < 0) return
            page.mutate(function (d) {
                const c = LockPresets.clone(d.layout.shapes[i])
                c.id = LockPresets.newId("s"); c.fx += 0.03; c.fy += 0.03
                d.layout.shapes.push(c)
            })
            page.shapeSel = page.draft.layout.shapes.length - 1
            page.sel = "shape:" + page.shapeSel
    }
    function toFront() {
        const i = page.shapeSel
        if (i < 0 || i >= page.draft.layout.shapes.length - 1) return
            page.mutate(function (d) { const s = d.layout.shapes.splice(i, 1)[0]; d.layout.shapes.push(s) })
            page.shapeSel = page.draft.layout.shapes.length - 1
            page.sel = "shape:" + page.shapeSel
    }
    function toBack() {
        const i = page.shapeSel
        if (i <= 0) return
            page.mutate(function (d) { const s = d.layout.shapes.splice(i, 1)[0]; d.layout.shapes.unshift(s) })
            page.shapeSel = 0
            page.sel = "shape:0"
    }
    function pushText() {
        const s = page.lay.settings
        if (!s.push) return "The clock stays where it is when the settings panel opens."
            const v = LockPresets.pushVector(s.fx, s.fy, true, 1)
            const dir = v.dx < 0 ? "left" : (v.dx > 0 ? "right" : (v.dy > 0 ? "down" : "up"))
            return "When the settings panel opens, the clock / date slide " + dir + " to make room."
    }
    function fileName(p) { const i = p.lastIndexOf("/"); return i >= 0 ? p.slice(i + 1) : p }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8
        visible: page.mode !== "browse"

        // the big live preview (always on): the draft while editing, the selected preset in the list
        LockPresetPreview {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(page.width, 500)
            Layout.preferredHeight: implicitHeight
            layout: page.shownLayout
            sel: page.mode === "edit" ? page.sel : ""
            editable: page.mode === "edit"
            showPush: page.showPush && page.mode === "edit"
            onPicked: (k) => page.onPicked(k)
            onMoved: (k, fx, fy) => page.setPos(k, fx, fy)
            onScaled: (k, sx, sy, fx, fy) => page.setScale(k, sx, sy, fx, fy)
            onShapeRect: (i, fx, fy, fw, fh) => page.mutate(function (d) {
                const s = d.layout.shapes[i]
                s.fx = fx; s.fy = fy; s.fw = fw; s.fh = fh
            })
        }
        Hr {}

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // =============================== LIST ===============================
            Flickable {
                anchors.fill: parent
                anchors.leftMargin: -14; anchors.rightMargin: -14   // horizontal gutter only (hover-scaled buttons); top/bottom clip at the real edge
                visible: page.mode === "list"
                clip: true
                contentWidth: width
                contentHeight: listCol.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: listCol
                    x: 14; y: 4
                    width: parent.width - 28
                    spacing: 10

                    Hint { text: "Presets are your own lock screens: move the clock, password, buttons and battery anywhere, set a wallpaper and add shapes. Default is the lock screen as it always was. Click a name to see it above; Apply uses it from the next lock. Only where things sit and how they look change, unlocking works the same." }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "Default (classic lock screen)" + (page.focusId === "" ? "  - shown above" : "")
                            color: Theme.foreground
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                            Layout.fillWidth: true
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.focusId = "" }
                        }
                        GlassButton {
                            text: LockPresets.active === "" ? "In use" : "Apply"
                            active: LockPresets.active === ""
                            onClicked: LockPresets.apply("")
                        }
                    }
                    Hr {}
                    Repeater {
                        model: LockPresets.presets
                        delegate: RowLayout {
                            id: row
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: row.modelData.name + (page.focusId === row.modelData.id ? "  - shown above" : "")
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.focusId = row.modelData.id }
                                }
                                Text {
                                    text: row.modelData.layout.shapes.length + (row.modelData.layout.shapes.length === 1 ? " shape" : " shapes")
                                    + (row.modelData.layout.bg.mode === "wallpaper" ? ", wallpaper" : ", blurred screen")
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm
                                }
                            }
                            GlassButton {
                                text: LockPresets.active === row.modelData.id ? "In use" : "Apply"
                                active: LockPresets.active === row.modelData.id
                                onClicked: LockPresets.apply(row.modelData.id)
                            }
                            GlassButton { text: "Edit"; onClicked: page.startEdit(row.modelData) }
                            GlassButton { text: "Delete"; onClicked: LockPresets.deletePreset(row.modelData.id) }
                        }
                    }
                    Hint { visible: LockPresets.presets.length === 0; text: "No presets yet." }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        GlassButton { text: "Create"; onClicked: page.startEdit(LockPresets.newPreset()) }
                    }
                    Item { Layout.preferredHeight: 4 }
                }
            }

            // =============================== EDIT ===============================
            ColumnLayout {
                anchors.fill: parent
                visible: page.mode === "edit" && page.draft !== null
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    TextField {
                        id: nameField
                        Layout.fillWidth: true
                        implicitHeight: 32
                        selectByMouse: true
                        text: page.draft ? page.draft.name : ""
                        placeholderText: "Preset name"
                        color: Theme.foreground
                        placeholderTextColor: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        background: Rectangle {
                            radius: Theme.radiusSm
                            color: "transparent"
                            border.width: 1
                            border.color: nameField.activeFocus ? Theme.accentActive : Theme.borderMuted
                        }
                        onTextEdited: page.mutate(function (d) { d.name = nameField.text })
                    }
                    GlassButton {
                        text: "Save & apply"; active: true
                        onClicked: { const id = LockPresets.savePreset(page.draft); LockPresets.apply(id); page.leaveEdit() }
                    }
                    GlassButton { text: "Save"; onClicked: { LockPresets.savePreset(page.draft); page.leaveEdit() } }
                    GlassButton { text: "Cancel"; onClicked: page.leaveEdit() }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: page.sections
                        delegate: GlassButton {
                            required property var modelData
                            text: modelData.label
                            active: page.section === modelData.id
                            onClicked: page.setSection(modelData.id)
                        }
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: -14; Layout.rightMargin: -14   // horizontal gutter only (hover-scaled buttons); top/bottom clip at the real edge
                    clip: true
                    contentWidth: width
                    contentHeight: editCol.implicitHeight + 8
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: editCol
                        x: 14; y: 4
                        width: parent.width - 28
                        spacing: 12
                        visible: page.lay !== null

                        Hint {
                            visible: page.hasPos
                            text: "Drag it in the preview, pick a spot, or use the sliders."
                        }

                        // ---- position (every element but background / shapes) ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: page.lay !== null && page.hasPos
                            && !(page.section === "password" && page.lay.password.follow)

                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Spot" }
                                Grid {
                                    columns: 3; spacing: 6
                                    Repeater {
                                        model: page.spots
                                        delegate: GlassButton {
                                            required property var modelData
                                            text: modelData.l
                                            implicitWidth: 96
                                            onClicked: page.setPos(page.section, modelData.x, modelData.y)
                                        }
                                    }
                                }
                            }
                            PctRow {
                                label: "Horizontal"
                                value: page.lay ? page.lay[page.hasPos ? page.section : "clock"].fx : 0
                                onCommitted: (v) => page.setPos(page.section, v, page.lay[page.section].fy)
                            }
                            PctRow {
                                label: "Vertical"
                                value: page.lay ? page.lay[page.hasPos ? page.section : "clock"].fy : 0
                                onCommitted: (v) => page.setPos(page.section, page.lay[page.section].fx, v)
                            }
                        }

                        // ---- size: stretch the clock / buttons / battery (or drag the square handles in the preview) ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: page.lay !== null && ["clock", "power", "settings", "battery"].indexOf(page.section) >= 0
                            PctRow {
                                label: "Width"
                                from: 0.3; to: 4
                                value: page.lay && page.lay[page.section] ? (page.lay[page.section].sx || 1) : 1
                                onCommitted: (v) => page.setLayoutKey(page.section, "sx", v)
                            }
                            PctRow {
                                label: "Height"
                                from: 0.3; to: 4
                                value: page.lay && page.lay[page.section] ? (page.lay[page.section].sy || 1) : 1
                                onCommitted: (v) => page.setLayoutKey(page.section, "sy", v)
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                GlassButton {
                                    text: "Reset size"
                                    onClicked: page.mutate(function (d) { d.layout[page.section].sx = 1; d.layout[page.section].sy = 1 })
                                }
                                Hint { text: "Stretch or squash it: use these sliders, or select it in the preview and drag the square handles on its right edge, bottom edge or corner." }
                            }
                            NumRow {
                                visible: page.section === "power" || page.section === "settings"
                                label: "Corner radius"
                                from: 0; to: 40; unit: "px"
                                value: page.lay && page.lay[page.section] && page.lay[page.section].radius >= 0 ? page.lay[page.section].radius : 6
                                onCommitted: (v) => page.setLayoutKey(page.section, "radius", v)
                            }
                            RowLayout {
                                visible: page.section === "power" || page.section === "settings"
                                Layout.fillWidth: true; spacing: 10
                                GlassButton {
                                    text: "Normal corners"
                                    active: page.lay && page.lay[page.section] && page.lay[page.section].radius < 0
                                    onClicked: page.setLayoutKey(page.section, "radius", -1)
                                }
                                Hint { text: "How round the button corners are. Normal = the usual look." }
                            }
                        }

                        // ---- clock ----
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: page.section === "clock"
                            SectionLabel { text: "Date" }
                            OnOff { value: page.lay ? page.lay.clock.showDate : true; onChoose: (v) => page.setLayoutKey("clock", "showDate", v) }
                            Hint { text: "Show the date under the time." }
                        }

                        // ---- password ----
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            visible: page.section === "password"
                            SectionLabel { text: "Follow clock" }
                            OnOff { value: page.lay ? page.lay.password.follow : true; onChoose: (v) => page.setLayoutKey("password", "follow", v) }
                            Hint { text: "On: sits under the clock wherever it goes. Off: place it anywhere (dragging it turns this off)." }
                        }

                        // ---- user / picture ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: page.section === "user"
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Show" }
                                OnOff { value: page.lay ? page.lay.user.show : false; onChoose: (v) => page.setLayoutKey("user", "show", v) }
                                Hint { text: "Your user name and picture on the lock screen. When on, drag it anywhere in the preview." }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Picture" }
                                OnOff { value: page.lay ? page.lay.user.showPfp : true; onChoose: (v) => page.setLayoutKey("user", "showPfp", v) }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Name" }
                                OnOff { value: page.lay ? page.lay.user.showName : true; onChoose: (v) => page.setLayoutKey("user", "showName", v) }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Image" }
                                Flow {
                                    Layout.fillWidth: true; spacing: 6
                                    GlassButton { text: "System picture"; active: page.lay && page.lay.user.pfp === ""; onClicked: page.setLayoutKey("user", "pfp", "") }
                                    GlassButton { text: page.lay && page.lay.user.pfp !== "" ? "Custom: " + page.fileName(page.lay.user.pfp) : "Custom..."; active: page.lay && page.lay.user.pfp !== ""; onClicked: { page.browseFor = "pfp"; page.mode = "browse" } }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Size" }
                                GlassSlider {
                                    Layout.fillWidth: true; Layout.preferredHeight: 26
                                    min: 32; max: 240
                                    value: page.lay ? page.lay.user.size : 96
                                    onValueCommitted: (v) => page.setLayoutKey("user", "size", Math.round(v))
                                }
                                Text {
                                    text: (page.lay ? page.lay.user.size : 0) + " px"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                    Layout.preferredWidth: 52; horizontalAlignment: Text.AlignRight
                                }
                            }
                            Hint { text: "System picture: ~/.face, else your account's icon, else a badge with your initial." }
                        }

                        // ---- text colour ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: page.section === "text"
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Colour" }
                                Flow {
                                    Layout.fillWidth: true; spacing: 6
                                    GlassButton { text: "Theme (default)"; active: page.lay && page.lay.text.mode === "theme"; onClicked: page.setLayoutKey("text", "mode", "theme") }
                                    GlassButton { text: "Solid"; active: page.lay && page.lay.text.mode === "solid"; onClicked: page.setLayoutKey("text", "mode", "solid") }
                                    GlassButton { text: "Gradient"; active: page.lay && page.lay.text.mode === "gradient"; onClicked: page.setLayoutKey("text", "mode", "gradient") }
                                }
                            }
                            ColorField {
                                visible: page.lay && page.lay.text.mode === "solid"
                                Layout.fillWidth: true
                                label: "Text"
                                col: page.lay ? page.lay.text.color : null
                                open: page.openKey === "lt"
                                onToggled: page.openKey = (page.openKey === "lt" ? "" : "lt")
                                onEdited: (v) => page.mutate(function (d) { d.layout.text.color = v })
                            }
                            Repeater {
                                model: (page.lay && page.lay.text.mode === "gradient") ? page.lay.text.stops.length : 0
                                delegate: ColorField {
                                    id: ltstop
                                    required property int index
                                    Layout.fillWidth: true
                                    label: "Colour " + (ltstop.index + 1)
                                    col: page.lay.text.stops[ltstop.index]
                                    removable: page.lay.text.stops.length > 2
                                    open: page.openKey === "lt.stop." + ltstop.index
                                    onToggled: page.openKey = (page.openKey === "lt.stop." + ltstop.index ? "" : "lt.stop." + ltstop.index)
                                    onEdited: (v) => page.mutate(function (d) { d.layout.text.stops[ltstop.index] = v })
                                    onRemoved: page.mutate(function (d) { d.layout.text.stops.splice(ltstop.index, 1) })
                                }
                            }
                            Row {
                                visible: page.lay && page.lay.text.mode === "gradient"
                                spacing: 6
                                GlassButton {
                                    visible: !!(page.lay && page.lay.text.stops.length < 6)
                                    text: "Add colour"
                                    onClicked: page.mutate(function (d) { d.layout.text.stops.push({ mode: "dyn", i: (d.layout.text.stops.length * 3 + 1) % 16 }) })
                                }
                                GlassButton { text: "Left to right"; active: page.lay && page.lay.text.horizontal !== false; onClicked: page.setLayoutKey("text", "horizontal", true) }
                                GlassButton { text: "Top to bottom"; active: page.lay && page.lay.text.horizontal === false; onClicked: page.setLayoutKey("text", "horizontal", false) }
                            }
                            Hint { text: "Applies to the clock, the date and the user name. The text itself is painted in this colour (a gradient is a real gradient inside the letters), with no tint layer over it." }
                        }

                        // ---- settings button ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            visible: page.section === "settings"
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Push clock" }
                                OnOff { value: page.lay ? page.lay.settings.push : true; onChoose: (v) => page.setLayoutKey("settings", "push", v) }
                                Hint { text: page.lay ? page.pushText() : "" }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Preview" }
                                OnOff { value: page.showPush; onChoose: (v) => page.showPush = v }
                                Hint { text: "Shows the clock pushed away and a box where the panel opens." }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Panel opens" }
                                Flow {
                                    Layout.fillWidth: true; spacing: 6
                                    Repeater {
                                        model: [{ l: "Auto", v: "auto" }, { l: "Below", v: "below" }, { l: "Above", v: "above" }, { l: "Left", v: "left" }, { l: "Right", v: "right" }]
                                        delegate: GlassButton {
                                            required property var modelData
                                            text: modelData.l
                                            active: page.lay && page.lay.settings.panelSide === modelData.v
                                            onClicked: { page.setLayoutKey("settings", "panelSide", modelData.v); page.showPush = true }
                                        }
                                    }
                                }
                            }
                            Hint { text: "The panel always starts from the button. Auto: below it in the top half of the screen, above it in the bottom half. It is drawn over everything else." }
                            PxRow { label: "Panel X"; value: page.lay ? page.lay.settings.panelX : 0; from: -600; to: 600; onCommitted: (v) => page.setLayoutKey("settings", "panelX", Math.round(v)) }
                            PxRow { label: "Panel Y"; value: page.lay ? page.lay.settings.panelY : 0; from: -600; to: 600; onCommitted: (v) => page.setLayoutKey("settings", "panelY", Math.round(v)) }
                            PxRow { label: "Contents X"; value: page.lay ? page.lay.settings.contentX : 0; from: -150; to: 150; onCommitted: (v) => page.setLayoutKey("settings", "contentX", Math.round(v)) }
                            PxRow { label: "Contents Y"; value: page.lay ? page.lay.settings.contentY : 0; from: -150; to: 150; onCommitted: (v) => page.setLayoutKey("settings", "contentY", Math.round(v)) }
                            Hint { text: "Panel X / Y move the whole panel from where it would open. Contents X / Y move what is inside it. The panel stays on screen." }
                            Hint { text: "Right side: pushes left. Left side: pushes right. Bottom centre: pushes up. Top centre: pushes down. The panel opens beside the button." }
                        }

                        // ---- background ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: page.section === "bg"
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                SectionLabel { text: "Background" }
                                Flow {
                                    Layout.fillWidth: true; spacing: 6
                                    GlassButton { text: "Blurred screen (default)"; active: page.lay && page.lay.bg.mode === "blur"; onClicked: page.setLayoutKey("bg", "mode", "blur") }
                                    GlassButton {
                                        text: "Wallpaper"; active: page.lay && page.lay.bg.mode === "wallpaper"
                                        onClicked: {
                                            if (page.lay.bg.path === "") { page.browseFor = "bg"; page.mode = "browse" }
                                            else page.setLayoutKey("bg", "mode", "wallpaper")
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 10
                                visible: page.lay && page.lay.bg.mode === "wallpaper"
                                SectionLabel { text: "Image" }
                                Text {
                                    Layout.fillWidth: true
                                    text: page.lay && page.lay.bg.path !== "" ? page.fileName(page.lay.bg.path) : "none chosen"
                                    elide: Text.ElideMiddle
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                }
                                GlassButton { text: "Choose..."; onClicked: { page.browseFor = "bg"; page.mode = "browse" } }
                            }
                            PctRow {
                                label: "Darkening"
                                from: 0; to: 0.9
                                value: page.lay ? page.lay.bg.dim / 100 : 0.4
                                onCommitted: (v) => page.setLayoutKey("bg", "dim", Math.round(v * 100))
                            }
                            Hint { text: "Default: the screen as it was when you locked, blurred. The preview shows a stand-in for it." }
                        }

                        // ---- shapes ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: page.section === "shapes"

                            Hint { text: "Add a shape, then drag it in the preview to place it and drag a corner dot to stretch it. Shapes sit behind the clock and buttons." }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                GlassButton { text: "+ Rectangle"; disabled: page.lay && page.lay.shapes.length >= 40; onClicked: page.addShape("rect") }
                                GlassButton { text: "+ Ellipse"; disabled: page.lay && page.lay.shapes.length >= 40; onClicked: page.addShape("ellipse") }
                                GlassButton { text: "+ Arrow"; disabled: page.lay && page.lay.shapes.length >= 40; onClicked: page.addShape("arrow") }
                                GlassButton { text: "+ Star"; disabled: page.lay && page.lay.shapes.length >= 40; onClicked: page.addShape("star") }
                                GlassButton { text: "+ Polygon"; disabled: page.lay && page.lay.shapes.length >= 40; onClicked: page.addShape("polygon") }
                            }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                visible: page.lay && page.lay.shapes.length > 0
                                Repeater {
                                    model: page.lay ? page.lay.shapes.length : 0
                                    delegate: GlassButton {
                                        required property int index
                                        text: "Shape " + (index + 1)
                                        active: page.shapeSel === index
                                        onClicked: { page.shapeSel = index; page.sel = "shape:" + index; page.openKey = "" }
                                    }
                                }
                            }
                            Hint { visible: page.lay && page.lay.shapes.length === 0; text: "No shapes yet." }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                visible: page.shape !== null

                                Flow {
                                    Layout.fillWidth: true; spacing: 6
                                    GlassButton { text: "Duplicate"; onClicked: page.dupShape() }
                                    GlassButton { text: "Bring to front"; onClicked: page.toFront() }
                                    GlassButton { text: "Send to back"; onClicked: page.toBack() }
                                    GlassButton { text: "Remove"; onClicked: page.removeShape() }
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    SectionLabel { text: "Kind" }
                                    Flow {
                                        Layout.fillWidth: true; spacing: 6
                                        Repeater {
                                            model: [{ l: "Rectangle", v: "rect" }, { l: "Ellipse", v: "ellipse" }, { l: "Arrow", v: "arrow" }, { l: "Star", v: "star" }, { l: "Polygon", v: "polygon" }]
                                            delegate: GlassButton {
                                                required property var modelData
                                                text: modelData.l
                                                active: page.shape && page.shape.kind === modelData.v
                                                onClicked: page.setShape("kind", modelData.v)
                                            }
                                        }
                                    }
                                }
                                // ---- what each kind can do ----
                                NumRow {
                                    visible: page.shape && page.shape.kind === "rect"
                                    label: "Corner radius"
                                    from: 0; to: 200; unit: "px"
                                    value: page.shape ? page.shape.radius : 0
                                    onCommitted: (v) => page.setShape("radius", v)
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: page.shape && page.shape.kind === "arrow"
                                    RowLayout {
                                        Layout.fillWidth: true; spacing: 10
                                        SectionLabel { text: "Points" }
                                        Flow {
                                            Layout.fillWidth: true; spacing: 6
                                            Repeater {
                                                model: [{ l: "\u2192", v: "right" }, { l: "\u2190", v: "left" }, { l: "\u2191", v: "up" }, { l: "\u2193", v: "down" }]
                                                delegate: GlassButton {
                                                    required property var modelData
                                                    text: modelData.l
                                                    active: page.shape && page.shape.arrowDir === modelData.v
                                                    onClicked: page.setShape("arrowDir", modelData.v)
                                                }
                                            }
                                            GlassButton { text: "One way"; active: page.shape && !page.shape.arrowDouble; onClicked: page.setShape("arrowDouble", false) }
                                            GlassButton { text: "Both ways"; active: page.shape && page.shape.arrowDouble; onClicked: page.setShape("arrowDouble", true) }
                                        }
                                    }
                                    NumRow { label: "Shaft thickness"; from: 15; to: 80; unit: "%"; value: page.shape ? page.shape.shaft : 40; onCommitted: (v) => page.setShape("shaft", v) }
                                    NumRow { label: "Head length"; from: 15; to: 60; unit: "%"; value: page.shape ? page.shape.head : 35; onCommitted: (v) => page.setShape("head", v) }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: page.shape && page.shape.kind === "star"
                                    NumRow { label: "Points"; from: 3; to: 12; value: page.shape ? page.shape.points : 5; onCommitted: (v) => page.setShape("points", v) }
                                    NumRow { label: "Notch depth"; from: 20; to: 90; unit: "%"; value: page.shape ? page.shape.inner : 45; onCommitted: (v) => page.setShape("inner", v) }
                                }
                                NumRow {
                                    visible: page.shape && page.shape.kind === "polygon"
                                    label: "Sides"
                                    from: 3; to: 12
                                    value: page.shape ? page.shape.sides : 6
                                    onCommitted: (v) => page.setShape("sides", v)
                                }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    SectionLabel { text: "Style" }
                                    Row {
                                        spacing: 6
                                        GlassButton { text: "Filled"; active: page.shape && page.shape.filled; onClicked: page.setShape("filled", true) }
                                        GlassButton { text: "Hollow"; active: page.shape && !page.shape.filled; onClicked: page.setShape("filled", false) }
                                    }
                                }
                                PctRow {
                                    visible: page.shape && !page.shape.filled
                                    label: "Line width"
                                    from: 0.01; to: 0.40
                                    value: page.shape ? page.shape.stroke / 100 : 0.03
                                    onCommitted: (v) => page.setShape("stroke", Math.max(1, Math.round(v * 100)))
                                }
                                Hint {
                                    visible: page.shape && !page.shape.filled
                                    text: "Hollow shapes draw an outline in the fill's colour (the average colour for a gradient or pattern). Arrows, stars and polygons fill with a solid colour or a gradient; a pattern uses its average colour."
                                }
                                Hr {}
                                Hint { text: "Fill: the same Solid / Gradient / Pattern options as Theme settings (a pattern can fill or tile)." }
                                ThemeFillEditor {
                                    Layout.fillWidth: true
                                    prefix: "lockshape"
                                    fillDef: page.shape ? page.shape.fill : ({})
                                    openKey: page.openKey
                                    onChanged: (d) => page.setShape("fill", d)
                                    onOpenToggled: (k) => page.openKey = (page.openKey === k ? "" : k)
                                    onBrowseRequested: { page.browseFor = "shape"; page.mode = "browse" }
                                }
                            }
                        }
                        // ---- notes: a message / your signature ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: page.section === "notes"

                            Hint { text: "Add a line of text or your signature. Drag a note in the preview to place it anywhere, and use the square handles on its right and bottom edges to stretch it. Notes sit behind the clock and buttons." }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                GlassButton { text: "+ Message"; disabled: page.lay && page.lay.notes.length >= 8; onClicked: page.addNote("message") }
                                GlassButton { text: "+ Signature"; disabled: page.lay && page.lay.notes.length >= 8; onClicked: page.addNote("signature") }
                            }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                visible: page.lay && page.lay.notes.length > 0
                                Repeater {
                                    model: page.lay ? page.lay.notes.length : 0
                                    delegate: GlassButton {
                                        required property int index
                                        text: (page.lay.notes[index].kind === "signature" ? "Signature " : "Message ") + (index + 1)
                                        active: page.noteSel === index
                                        onClicked: { page.noteSel = index; page.sel = "note:" + index; page.openKey = "" }
                                    }
                                }
                            }
                            Hint { visible: page.lay && page.lay.notes.length === 0; text: "No notes yet." }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                visible: page.note !== null

                                Flow {
                                    Layout.fillWidth: true; spacing: 6
                                    GlassButton { text: "Duplicate"; onClicked: page.dupNote() }
                                    GlassButton { text: "Remove"; onClicked: page.removeNote() }
                                }

                                // message
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: page.note && page.note.kind === "message"
                                    TextField {
                                        id: noteText
                                        Layout.fillWidth: true
                                        text: page.note ? page.note.text : ""
                                        placeholderText: "What should it say?"
                                        color: Theme.foreground
                                        placeholderTextColor: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSize
                                        background: Rectangle {
                                            radius: Theme.radiusSm
                                            color: "transparent"
                                            border.width: 1
                                            border.color: noteText.activeFocus ? Theme.accentActive : Theme.borderMuted
                                        }
                                        onTextEdited: page.setNote("text", noteText.text)
                                    }
                                    NumRow { label: "Text size"; from: 12; to: 200; unit: "px"; value: page.note ? page.note.size : 40; onCommitted: (v) => page.setNote("size", v) }
                                }

                                // signature
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    visible: page.note && page.note.kind === "signature"
                                    Hint { text: "Sign in the box with your mouse, touchpad, touch screen or a digital pen." }
                                    SignaturePad {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: width * 0.4
                                        spec: page.note ? page.note : ({})
                                        strokes: page.note ? page.note.strokes : []
                                        onCommitted: (s) => page.setNote("strokes", s)
                                    }
                                    Row {
                                        spacing: 6
                                        GlassButton {
                                            text: "Undo stroke"
                                            disabled: !page.note || page.note.strokes.length === 0
                                            onClicked: page.setNote("strokes", page.note.strokes.slice(0, page.note.strokes.length - 1))
                                        }
                                        GlassButton {
                                            text: "Clear"
                                            disabled: !page.note || page.note.strokes.length === 0
                                            onClicked: page.setNote("strokes", [])
                                        }
                                    }
                                    NumRow { label: "Pen width"; from: 1; to: 12; unit: "px"; value: page.note ? page.note.pen : 3; onCommitted: (v) => page.setNote("pen", v) }
                                }

                                // colour: the same Theme / Solid / Gradient choice as the text colour
                                Hr {}
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 10
                                    SectionLabel { text: "Colour" }
                                    Flow {
                                        Layout.fillWidth: true; spacing: 6
                                        GlassButton { text: "Theme (default)"; active: page.note && page.note.color.mode === "theme"; onClicked: page.mutate(function (d) { d.layout.notes[page.noteSel].color.mode = "theme" }) }
                                        GlassButton { text: "Solid"; active: page.note && page.note.color.mode === "solid"; onClicked: page.mutate(function (d) { d.layout.notes[page.noteSel].color.mode = "solid" }) }
                                        GlassButton { text: "Gradient"; active: page.note && page.note.color.mode === "gradient"; onClicked: page.mutate(function (d) { d.layout.notes[page.noteSel].color.mode = "gradient" }) }
                                    }
                                }
                                ColorField {
                                    visible: page.note && page.note.color.mode === "solid"
                                    Layout.fillWidth: true
                                    label: "Colour"
                                    col: page.note ? page.note.color.color : null
                                    open: page.openKey === "nc"
                                    onToggled: page.openKey = (page.openKey === "nc" ? "" : "nc")
                                    onEdited: (v) => page.mutate(function (d) { d.layout.notes[page.noteSel].color.color = v })
                                }
                                Repeater {
                                    model: (page.note && page.note.color.mode === "gradient") ? page.note.color.stops.length : 0
                                    delegate: ColorField {
                                        id: ncstop
                                        required property int index
                                        Layout.fillWidth: true
                                        label: "Colour " + (ncstop.index + 1)
                                        col: page.note.color.stops[ncstop.index]
                                        removable: page.note.color.stops.length > 2
                                        open: page.openKey === "nc.stop." + ncstop.index
                                        onToggled: page.openKey = (page.openKey === "nc.stop." + ncstop.index ? "" : "nc.stop." + ncstop.index)
                                        onEdited: (v) => page.mutate(function (d) { d.layout.notes[page.noteSel].color.stops[ncstop.index] = v })
                                        onRemoved: page.mutate(function (d) { d.layout.notes[page.noteSel].color.stops.splice(ncstop.index, 1) })
                                    }
                                }
                                Row {
                                    visible: page.note && page.note.color.mode === "gradient"
                                    spacing: 6
                                    GlassButton {
                                        visible: !!(page.note && page.note.color.stops.length < 6)
                                        text: "Add colour"
                                        onClicked: page.mutate(function (d) { const c = d.layout.notes[page.noteSel].color; c.stops.push({ mode: "dyn", i: (c.stops.length * 3 + 1) % 16 }) })
                                    }
                                    GlassButton { text: "Left to right"; active: page.note && page.note.color.horizontal !== false; onClicked: page.mutate(function (d) { d.layout.notes[page.noteSel].color.horizontal = true }) }
                                    GlassButton { text: "Top to bottom"; active: page.note && page.note.color.horizontal === false; onClicked: page.mutate(function (d) { d.layout.notes[page.noteSel].color.horizontal = false }) }
                                }
                            }
                        }
                        Item { Layout.preferredHeight: 6 }
                    }
                }
            }
        }
    }

    // =============================== IMAGE BROWSER ===============================
    Loader {
        anchors.fill: parent
        active: page.mode === "browse"
        sourceComponent: ImageBrowser {
            onPicked: (f) => {
                if (page.browseFor === "bg") page.mutate(function (d) { d.layout.bg.path = f; d.layout.bg.mode = "wallpaper" })
                    else if (page.browseFor === "pfp") page.mutate(function (d) { d.layout.user.pfp = f })
                        else page.mutate(function (d) { d.layout.shapes[page.shapeSel].fill.image = f })
                            page.mode = "edit"
            }
            onCancelled: page.mode = "edit"
        }
    }
}
