import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Bar > Presets: build your own bar layouts out of mini bars (see Services/BarPresets.qml).
//   list   Default (the classic bar) + your presets: Apply / Edit / Delete, and Create
//   edit   name, mini bars (edge, alignment, size, auto-hide, scale, roundness, background,
//          popups, modules). "Preview" shows the draft on screen, "Back" stops previewing.
Item {
    id: page

    property string mode: "list"            // "list" | "edit"
    property var draft: null
    // list view: which preset the preview shows ("" = the classic bar)
    property string focusId: BarPresets.active
    property int sel: 0
    // the classic bar as a one-bar preset, so Default can be previewed like any other
    readonly property var defaultBars: [{
        edge: BarSettings.edge, align: "center", offset: 0,
        sizeMode: (BarSettings.fillScreen || !BarSettings.autohide) ? "fill" : "fit", lengthPx: 600,
        autohide: BarSettings.autohide, scalePct: BarSettings.scalePct, roundnessPct: BarSettings.roundnessPct,
        bg: "theme", popupMode: "float", modules: BarSettings.order
    }]
    readonly property var previewBars: {
        if (page.mode === "edit") return page.draft ? page.draft.bars : []
            if (page.focusId === "") return page.defaultBars
                const p = BarPresets.presetById(page.focusId)
                return p ? p.bars : page.defaultBars
    }
    readonly property var bar: (draft && draft.bars && draft.bars[sel]) ? draft.bars[sel] : null

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

    // ---- draft helpers ----
    function mutate(fn) {
        const d = BarPresets.clone(page.draft)
        fn(d)
        page.draft = d
    }
    function setB(key, v) { page.mutate(function (d) { d.bars[page.sel][key] = v }) }
    function startEdit(p) {
        page.draft = BarPresets.clone(p)
        page.sel = 0
        page.mode = "edit"
    }
    function leaveEdit() {
        page.draft = null
        page.mode = "list"
    }
    function addBar() {
        page.mutate(function (d) { if (d.bars.length < 8) d.bars.push(BarPresets.newBar()) })
        page.sel = page.draft.bars.length - 1
    }
    function removeBar() {
        if (page.draft.bars.length <= 1) return
            const i = page.sel
            page.mutate(function (d) { d.bars.splice(i, 1) })
            page.sel = Math.max(0, Math.min(i, page.draft.bars.length - 1))
    }
    // icons: while the bar flows they just append; once an icon has been placed by hand the bar is "free"
    // and a new icon goes at the first free spot at the end
    function addModule(m) {
        if (page.bar && page.bar.places) bpv.addAtEnd(m)
            else page.setB("modules", page.bar.modules.concat([m]))
    }
    function removeModule(id) {
        page.mutate(function (d) {
            const b = d.bars[page.sel]
            b.modules = b.modules.filter(function (x) { return x !== id })
            if (b.places) { delete b.places[id]; if (Object.keys(b.places).length === 0) b.places = null }
        })
        bpv.selModule = ""
    }
    // an icon was dropped in the preview
    function placeModule(bi, id, pos, all) {
        page.mutate(function (d) {
            const b = d.bars[bi]
            const pl = all || {}
            pl[id] = pos
            if (b.modules.indexOf(id) < 0) b.modules.push(id)
                b.places = pl
        })
    }
    function setAllAutohide(v) { page.mutate(function (d) { for (let i = 0; i < d.bars.length; i++) d.bars[i].autohide = v }) }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // live preview (always on): the draft while editing, the selected preset in the list
        BarPresetPreview {
            id: bpv
            Layout.fillWidth: true
            Layout.preferredHeight: implicitHeight
            bars: page.previewBars
            sel: page.mode === "edit" ? page.sel : -1
            editable: page.mode === "edit"
            onBarClicked: (i) => { if (page.mode === "edit") page.sel = i }
            onPlaced: (bi, id, pos, all) => page.placeModule(bi, id, pos, all)
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

                    Hint { text: "Presets are your own bar layouts: one bar, or several mini bars of any size, on any edges. Default is the classic bar from the Bar settings. Click a name to see it in the preview above; Apply uses it until you apply another." }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Text {
                            text: "Default (classic bar)" + (page.focusId === "" ? "  - shown above" : "")
                            color: Theme.foreground
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                            Layout.fillWidth: true
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.focusId = "" }
                        }
                        GlassButton {
                            text: BarPresets.active === "" ? "In use" : "Apply"
                            active: BarPresets.active === ""
                            onClicked: BarPresets.apply("")
                        }
                    }
                    Hr {}

                    Repeater {
                        model: BarPresets.presets
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
                                    text: row.modelData.bars.length + (row.modelData.bars.length === 1 ? " bar" : " mini bars")
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm
                                }
                            }
                            GlassButton {
                                text: BarPresets.active === row.modelData.id ? "In use" : "Apply"
                                active: BarPresets.active === row.modelData.id
                                onClicked: BarPresets.apply(row.modelData.id)
                            }
                            GlassButton { text: "Edit"; onClicked: page.startEdit(row.modelData) }
                            GlassButton { text: "Delete"; onClicked: BarPresets.deletePreset(row.modelData.id) }
                        }
                    }

                    Hint { visible: BarPresets.presets.length === 0; text: "No presets yet." }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        GlassButton { text: "Create"; onClicked: page.startEdit(BarPresets.newPreset()) }
                    }
                    Item { Layout.preferredHeight: 4 }
                }
            }

            // =============================== EDIT ===============================
            ColumnLayout {
                anchors.fill: parent
                visible: page.mode === "edit" && page.draft !== null
                spacing: 8

                // top bar: name + preview / save / cancel
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
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    GlassButton {
                        text: "Save & apply"
                        active: true
                        onClicked: { const id = BarPresets.savePreset(page.draft); BarPresets.apply(id); page.leaveEdit() }
                    }
                    GlassButton { text: "Save"; onClicked: { BarPresets.savePreset(page.draft); page.leaveEdit() } }
                    GlassButton { text: "Cancel"; onClicked: page.leaveEdit() }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "Persistent, all bars:"
                        color: Theme.foreground
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm
                    }
                    GlassButton { text: "On"; onClicked: page.setAllAutohide(false) }
                    GlassButton { text: "Off"; onClicked: page.setAllAutohide(true) }
                }

                Hr {}

                // mini bar tabs
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: page.draft ? page.draft.bars.length : 0
                        delegate: GlassButton {
                            required property int index
                            text: "Bar " + (index + 1)
                            active: page.sel === index
                            onClicked: page.sel = index
                        }
                    }
                    GlassButton { text: "+ Add mini bar"; disabled: !page.draft || page.draft.bars.length >= 8; onClicked: page.addBar() }
                    GlassButton { text: "Remove this bar"; disabled: !page.draft || page.draft.bars.length <= 1; onClicked: page.removeBar() }
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
                        spacing: 14
                        visible: page.bar !== null

                        // edge
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            SectionLabel { text: "Edge" }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                Repeater {
                                    model: [{ l: "Bottom", v: "bottom" }, { l: "Top", v: "top" }, { l: "Left", v: "left" }, { l: "Right", v: "right" }]
                                    delegate: GlassButton {
                                        required property var modelData
                                        text: modelData.l
                                        active: page.bar && page.bar.edge === modelData.v
                                        onClicked: page.setB("edge", modelData.v)
                                    }
                                }
                            }
                        }

                        // size
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            SectionLabel { text: "Size" }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Flow {
                                    Layout.fillWidth: true; spacing: 6
                                    Repeater {
                                        model: [{ l: "Fit to content", v: "fit" }, { l: "Edge to edge", v: "fill" }, { l: "Fixed length", v: "fixed" }]
                                        delegate: GlassButton {
                                            required property var modelData
                                            text: modelData.l
                                            active: page.bar && page.bar.sizeMode === modelData.v
                                            onClicked: page.setB("sizeMode", modelData.v)
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: page.bar && page.bar.sizeMode === "fixed"
                                    spacing: 10
                                    GlassSlider {
                                        Layout.fillWidth: true; Layout.preferredHeight: 26
                                        min: 120; max: 3840
                                        value: page.bar ? page.bar.lengthPx : 600
                                        onValueCommitted: (v) => page.setB("lengthPx", Math.round(v))
                                    }
                                    Text {
                                        text: (page.bar ? page.bar.lengthPx : 0) + " px"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                        Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }
                        }

                        // align
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            SectionLabel { text: "Alignment" }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Row {
                                    spacing: 6
                                    Repeater {
                                        model: [{ l: "Start", v: "start" }, { l: "Centre", v: "center" }, { l: "End", v: "end" }]
                                        delegate: GlassButton {
                                            required property var modelData
                                            text: modelData.l
                                            active: page.bar && page.bar.align === modelData.v
                                            onClicked: page.setB("align", modelData.v)
                                        }
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: page.bar && page.bar.align !== "center" && page.bar.sizeMode !== "fill"
                                    spacing: 10
                                    Text { text: "Distance from the end"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm }
                                    GlassSlider {
                                        Layout.fillWidth: true; Layout.preferredHeight: 26
                                        min: 0; max: 600
                                        value: page.bar ? page.bar.offset : 0
                                        onValueCommitted: (v) => page.setB("offset", Math.round(v))
                                    }
                                    Text {
                                        text: (page.bar ? page.bar.offset : 0) + " px"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                        Layout.preferredWidth: 60; horizontalAlignment: Text.AlignRight
                                    }
                                }
                                Hint { text: "Start / End is the left / right end of a top or bottom bar, the top / bottom end of a side bar. Bars on the same edge need different alignments (or distances) so they do not overlap." }
                            }
                        }

                        // autohide
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            SectionLabel { text: "Persistent" }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Row {
                                    spacing: 6
                                    GlassButton { text: "On"; active: page.bar && !page.bar.autohide; onClicked: page.setB("autohide", false) }
                                    GlassButton { text: "Off"; active: page.bar && page.bar.autohide; onClicked: page.setB("autohide", true) }
                                }
                                Hint { text: "On: the bar is always shown and keeps screen space for windows (the wallpaper is not resized; with several persistent bars on one edge the thickest reserves). Off: it slides away until you hover its edge. While any popup or thumbnail of any bar is open, all bars of the preset stay shown." }
                            }
                        }

                        // scale
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            SectionLabel { text: "Scale" }
                            GlassSlider {
                                Layout.fillWidth: true; Layout.preferredHeight: 26
                                min: 70; max: 160
                                value: page.bar ? page.bar.scalePct : 100
                                onValueCommitted: (v) => page.setB("scalePct", Math.round(v))
                            }
                            Text {
                                text: (page.bar ? page.bar.scalePct : 100) + "%"
                                color: Theme.foreground
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight
                            }
                        }

                        // roundness
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            SectionLabel { text: "Roundness" }
                            GlassSlider {
                                Layout.fillWidth: true; Layout.preferredHeight: 26
                                min: 0; max: 100
                                value: page.bar ? page.bar.roundnessPct : 100
                                onValueCommitted: (v) => page.setB("roundnessPct", Math.round(v))
                            }
                            Text {
                                text: (page.bar ? page.bar.roundnessPct : 100) + "%"
                                color: Theme.foreground
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight
                            }
                        }

                        // background
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            SectionLabel { text: "Background" }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Row {
                                    spacing: 6
                                    GlassButton { text: "Theme"; active: page.bar && page.bar.bg === "theme"; onClicked: page.setB("bg", "theme") }
                                    GlassButton { text: "Transparent"; active: page.bar && page.bar.bg === "transparent"; onClicked: page.setB("bg", "transparent") }
                                }
                                Hint { text: "Theme: the bar fill of the current theme. Transparent: no panel at all, just the icons." }
                            }
                        }

                        // popups
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            SectionLabel { text: "Popups" }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Row {
                                    spacing: 6
                                    GlassButton { text: "Float"; active: page.bar && page.bar.popupMode === "float"; onClicked: page.setB("popupMode", "float") }
                                    GlassButton { text: "Merge & expand"; active: page.bar && page.bar.popupMode === "merge"; onClicked: page.setB("popupMode", "merge") }
                                }
                                Hint { text: "Float: popups open just off the bar, like the classic bar. Merge & expand: the popup sits flush against the bar and the bar grows to at least the popup's width while it is open (only this bar; other bars stay as they are), with the touching corners squared so they read as one shape." }
                            }
                        }

                        Hr {}

                        // icons: they are arranged in the preview above (drag them anywhere, never on top of each other)
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            SectionLabel { text: "Icons" }
                            ColumnLayout {
                                Layout.fillWidth: true; spacing: 6
                                Hint { text: "Drag the icons in the preview above to place them anywhere along the bar, with room between them. They cannot overlap: one that does turns red and lands in the nearest free place when you let go. Use Zoom for finer control. Click an icon to select it." }
                                RowLayout {
                                    Layout.fillWidth: true; spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: bpv.selModule !== "" ? ("Selected: " + (BarPresets.moduleNames[bpv.selModule] || bpv.selModule)) : "No icon selected"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                    }
                                    GlassButton {
                                        text: "Remove"
                                        implicitHeight: 26
                                        disabled: bpv.selModule === ""
                                        onClicked: page.removeModule(bpv.selModule)
                                    }
                                    GlassButton {
                                        text: "Auto-space"
                                        implicitHeight: 26
                                        disabled: !(page.bar && page.bar.places)
                                        onClicked: page.setB("places", null)
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            SectionLabel { text: "Add" }
                            Flow {
                                Layout.fillWidth: true; spacing: 6
                                Repeater {
                                    model: BarPresets.moduleIds.filter(function (m) { return !page.bar || page.bar.modules.indexOf(m) < 0 })
                                    delegate: GlassButton {
                                        id: chip
                                        required property string modelData
                                        text: "+ " + (BarPresets.moduleNames[modelData] || modelData)
                                        implicitHeight: 28
                                        onClicked: page.addModule(modelData)

                                        // drag it onto the bar in the preview; a short click still just adds it
                                        property point lastScene: Qt.point(0, 0)
                                        DragHandler {
                                            target: null
                                            dragThreshold: 6
                                            grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.ApprovesTakeOverByAnything
                                            cursorShape: Qt.ClosedHandCursor
                                            onActiveChanged: {
                                                if (active) bpv.beginExternal(chip.modelData, centroid.scenePosition)
                                                    else bpv.endExternal(chip.lastScene)
                                            }
                                            onCentroidChanged: {
                                                if (!active) return
                                                    chip.lastScene = centroid.scenePosition
                                                    bpv.updateExternal(centroid.scenePosition)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Item { Layout.preferredHeight: 8 }
                    }
                }
            }
        }
    }
}
