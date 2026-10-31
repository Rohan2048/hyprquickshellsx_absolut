import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../Theme"
import "../Widgets"

// "Theme" page of SettingsPopup.
//
//  main    : one tile per theme (Transparent blur, Opaque, your own) with Edit / Delete on
//            each tile; Create sits in the page header (SettingsPopup).
//  edit    : name, Popups fill, Bar fill, text colour, light-mode behaviour.
//            [Preview] [Save & apply] [Cancel]
//  preview : a mock Bar, Popup and Notification drawn with the theme being edited.
//            The only place with a Back button.
//  browse  : image picker for a Pattern fill.
//
// The theme being edited is a draft; nothing touches the shell until Save & apply.
// The draft is also parked in Theme.themeDraft, so closing Settings mid-edit and
// reopening it brings you back to the same unsaved theme.
Item {
    id: page

    property string view: "main"            // "main" | "edit" | "preview" | "browse"
    property var draft: null
    property bool previewDark: Theme.effectiveDark
    property string openKey: ""             // the colour picker that is open
    property string browseFor: "popup"      // which fill the image browser is picking for
    property string deleteArm: ""

    readonly property bool adapts: page.draft ? page.draft.adapt !== false : true
    readonly property var dPopup: page.draft ? page.draft.popup : ({})
    readonly property var dBar: page.draft ? page.draft.bar : ({})
    readonly property var dText: page.draft ? page.draft.text : ({ auto: true })
    readonly property var dDate: (page.draft && page.draft.date) ? page.draft.date
    : ({ auto: true, type: "solid", color: { mode: "dyn", i: 3 }, stops: [{ mode: "dyn", i: 3 }, { mode: "dyn", i: 7 }], horizontal: true })
    // a theme saved before "Date colour" existed has no `date`: give it the default
    function ensureDate(t) {
        if (!t.date) t.date = { auto: true, type: "solid", color: { mode: "dyn", i: 3 },
            stops: [{ mode: "dyn", i: 3 }, { mode: "dyn", i: 7 }], horizontal: true }
    }
    readonly property var dAccent: (page.draft && page.draft.accent) ? page.draft.accent
    : ({ auto: true, active: { mode: "dyn", i: 3 }, hover: { mode: "dyn", i: 1 }, textAuto: true, text: { mode: "dyn", i: 0 } })
    function ensureAccent(t) {
        if (!t.accent) t.accent = { auto: true, active: { mode: "dyn", i: 3 }, hover: { mode: "dyn", i: 1 } }
        if (t.accent.textAuto === undefined) t.accent.textAuto = true
            if (!t.accent.text) t.accent.text = { mode: "dyn", i: 0 }
    }
    // text colour on an active button as the draft would draw it (the preview chips)
    function accentTextFor(c) {
        if (page.dAccent.textAuto === false) return Theme.colorOf(page.dAccent.text, page.previewDark, page.adapts)
            return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.55 ? "#000000" : "#ffffff"
    }

    Component.onCompleted: {
        if (Theme.themeDraft) { page.draft = Theme.themeDraft; page.view = "edit" }
    }

    function setDraft(d) { page.draft = d; Theme.themeDraft = d }
    function mutate(fn) {
        const d = Theme.cloneTheme(page.draft)
        fn(d)
        page.setDraft(d)
    }
    function startNew() { page.openKey = ""; page.setDraft(Theme.newTheme()); page.view = "edit" }
    function startEdit(id) {
        const t = Theme.themeById(id)
        if (!t) return
            page.openKey = ""
            page.setDraft(Theme.cloneTheme(t))
            page.view = "edit"
    }
    function closeEditor() {
        page.view = "main"
        page.openKey = ""
        page.draft = null
        Theme.themeDraft = null
    }
    function saveDraft() {
        const id = Theme.saveTheme(page.draft)
        Theme.setActiveTheme(id)
        page.closeEditor()
    }
    function toggleOpen(key) { page.openKey = (page.openKey === key) ? "" : key }

    // Esc steps back out of preview / browse; elsewhere it falls through (closes Settings).
    function handleKey(event) {
        if (event.key !== Qt.Key_Escape) return false
            if (page.view === "preview" || page.view === "browse") { page.view = "edit"; return true }
            return false
    }

    component SectionLabel: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        Layout.preferredWidth: 130
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

    Loader { anchors.fill: parent; active: page.view === "main"; sourceComponent: mainView }
    // stays alive behind preview / browse so scroll position and open pickers survive
    Loader { anchors.fill: parent; active: page.draft !== null; visible: page.view === "edit"; sourceComponent: editView }
    Loader { anchors.fill: parent; active: page.view === "preview" && page.draft !== null; sourceComponent: previewView }
    Loader { anchors.fill: parent; active: page.view === "browse"; sourceComponent: browseView }

    // =====================================================================
    // MAIN
    // =====================================================================
    Component {
        id: mainView

        SmoothFlickable {
            anchors.fill: parent; anchors.leftMargin: -14; anchors.rightMargin: -14
            id: mflick
            clip: true
            contentWidth: width
            contentHeight: mcol.implicitHeight + 8
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: mcol
                x: 14; y: 4
                width: mflick.width - 28
                spacing: 16

                // ---- themes: one tile per theme (built-in surfaces + your own) ----
                // Click a tile to apply it. Each tile is drawn with that theme's own colours.
                // Create lives in the page header (SettingsPopup); Edit / Delete are on each tile.
                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 520 ? 2 : 1
                    columnSpacing: 12
                    rowSpacing: 12

                    ThemeTile {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: implicitHeight
                        builtin: "blur"
                        title: "Transparent blur"
                        inUse: !Theme.customActive && !Theme.opaque
                        onActivated: Theme.setSurface("blur")
                    }
                    ThemeTile {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 100
                        Layout.preferredHeight: implicitHeight
                        builtin: "opaque"
                        title: "Opaque"
                        inUse: !Theme.customActive && Theme.opaque
                        onActivated: Theme.setSurface("opaque")
                    }

                    Repeater {
                        model: Theme.customThemes
                        delegate: ThemeTile {
                            id: ttile
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 100
                            Layout.preferredHeight: implicitHeight
                            def: ttile.modelData
                            title: ttile.modelData.name
                            inUse: Theme.activeThemeId === ttile.modelData.id
                            armed: page.deleteArm === ttile.modelData.id
                            onActivated: { page.deleteArm = ""; Theme.setActiveTheme(ttile.modelData.id) }
                            onEditClicked: { page.deleteArm = ""; page.startEdit(ttile.modelData.id) }
                            onDeleteClicked: {
                                if (page.deleteArm === ttile.modelData.id) {
                                    page.deleteArm = ""
                                    Theme.deleteTheme(ttile.modelData.id)
                                } else {
                                    page.deleteArm = ttile.modelData.id
                                }
                            }
                            onDeleteDisarmed: { if (page.deleteArm === ttile.modelData.id) page.deleteArm = "" }
                        }
                    }
                }

                Hint {
                    text: Theme.customThemes.length === 0
                    ? "Click a tile to apply it. Blur and Opaque follow your wallpaper colours. Press Create (top right) to make your own colours, gradient or image for the bar and popups."
                    : "Click a tile to apply it. Blur and Opaque follow your wallpaper colours; the tiles show each theme's own fills, text, date and button colours."
                }

                // ---- border (one setting for every theme) ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    SectionLabel { text: "Border" }
                    BorderSettingsSection { Layout.fillWidth: true }
                }

                Item { Layout.preferredHeight: 4 }
            }
        }
    }

    // =====================================================================
    // EDIT
    // =====================================================================
    Component {
        id: editView

        ColumnLayout {
            spacing: 10

            SmoothFlickable {
                id: eflick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: -14; Layout.rightMargin: -14   // horizontal gutter only (hover-scaled buttons); top/bottom clip at the real edge
                clip: true
                contentWidth: width
                contentHeight: ecol.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: ecol
                    x: 14; y: 4
                    width: eflick.width - 28
                    spacing: 18

                    // ---- name ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Name" }
                        TextField {
                            id: nameField
                            Layout.fillWidth: true
                            implicitHeight: 30
                            maximumLength: 32
                            selectByMouse: true
                            placeholderText: "Theme name"
                            color: Theme.foreground
                            placeholderTextColor: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            background: Rectangle {
                                radius: Theme.radiusSm
                                color: "transparent"
                                border.width: 1
                                border.color: nameField.activeFocus ? Theme.accentActive : Theme.borderMuted
                            }
                            onTextEdited: page.mutate(t => { t.name = nameField.text })
                        }
                        Binding {
                            target: nameField
                            property: "text"
                            value: page.draft ? page.draft.name : ""
                            when: !nameField.activeFocus
                        }
                    }

                    // ---- popups ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Popups" }
                        ThemeFillEditor {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            prefix: "popup"
                            fillDef: page.dPopup
                            openKey: page.openKey
                            onChanged: (d) => page.mutate(t => { t.popup = d })
                            onOpenToggled: (k) => page.toggleOpen(k)
                            onBrowseRequested: { page.browseFor = "popup"; page.view = "browse" }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

                    // ---- bar ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Bar" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 10
                            ThemeFillEditor {
                                Layout.fillWidth: true
                                prefix: "bar"
                                fillDef: page.dBar
                                openKey: page.openKey
                                onChanged: (d) => page.mutate(t => { t.bar = d })
                                onOpenToggled: (k) => page.toggleOpen(k)
                                onBrowseRequested: { page.browseFor = "bar"; page.view = "browse" }
                            }
                            Row {
                                GlassButton {
                                    text: "Same as popups"
                                    onClicked: page.mutate(t => { t.bar = JSON.parse(JSON.stringify(t.popup)) })
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

                    // ---- text ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Text colour" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 8
                            Row {
                                spacing: 6
                                GlassButton {
                                    text: "Default"
                                    active: page.dText.auto !== false
                                    onClicked: page.mutate(t => { t.text.auto = true })
                                }
                                GlassButton {
                                    text: "Solid"
                                    active: page.dText.auto === false && page.dText.type !== "gradient"
                                    onClicked: page.mutate(t => { t.text.auto = false; t.text.type = "solid" })
                                }
                                GlassButton {
                                    text: "Gradient"
                                    active: page.dText.auto === false && page.dText.type === "gradient"
                                    onClicked: page.mutate(t => {
                                        t.text.auto = false
                                        t.text.type = "gradient"
                                        if (!t.text.stops || t.text.stops.length < 2)
                                            t.text.stops = [{ mode: "dyn", i: 7 }, { mode: "dyn", i: 3 }]
                                            if (t.text.horizontal === undefined) t.text.horizontal = true
                                    })
                                }
                            }
                            ColorField {
                                visible: page.dText.auto === false && page.dText.type !== "gradient"
                                Layout.fillWidth: true
                                label: "Text"
                                col: page.dText.color ? page.dText.color : null
                                open: page.openKey === "text"
                                onToggled: page.toggleOpen("text")
                                onEdited: (v) => page.mutate(t => { t.text.color = v })
                            }
                            Repeater {
                                model: (page.dText.auto === false && page.dText.type === "gradient" && page.dText.stops) ? page.dText.stops.length : 0
                                delegate: ColorField {
                                    id: tstop
                                    required property int index
                                    Layout.fillWidth: true
                                    label: "Colour " + (tstop.index + 1)
                                    col: page.dText.stops[tstop.index]
                                    removable: page.dText.stops.length > 2
                                    open: page.openKey === "text.stop." + tstop.index
                                    onToggled: page.toggleOpen("text.stop." + tstop.index)
                                    onEdited: (v) => page.mutate(t => { t.text.stops[tstop.index] = v })
                                    onRemoved: page.mutate(t => { t.text.stops.splice(tstop.index, 1) })
                                }
                            }
                            Row {
                                visible: page.dText.auto === false && page.dText.type === "gradient"
                                spacing: 6
                                GlassButton {
                                    visible: !!(page.dText.stops && page.dText.stops.length < 6)
                                    text: "Add colour"
                                    onClicked: page.mutate(t => { t.text.stops.push({ mode: "dyn", i: (t.text.stops.length * 3 + 1) % 16 }) })
                                }
                                GlassButton {
                                    text: "Left to right"
                                    active: page.dText.horizontal !== false
                                    onClicked: page.mutate(t => { t.text.horizontal = true })
                                }
                                GlassButton {
                                    text: "Top to bottom"
                                    active: page.dText.horizontal === false
                                    onClicked: page.mutate(t => { t.text.horizontal = false })
                                }
                            }
                            Hint {
                                visible: page.dText.auto === false && page.dText.type === "gradient"
                                text: "A gradient is drawn across all text that uses the text colour: the clock, titles, labels and buttons. Text with its own colour (errors, the text on an active button) keeps it."
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

                    // ---- date (the date under the bar clock) ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Date colour" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 8
                            Row {
                                spacing: 6
                                GlassButton {
                                    text: "Default"
                                    active: page.dDate.auto !== false
                                    onClicked: page.mutate(t => { page.ensureDate(t); t.date.auto = true })
                                }
                                GlassButton {
                                    text: "Solid"
                                    active: page.dDate.auto === false && page.dDate.type !== "gradient"
                                    onClicked: page.mutate(t => { page.ensureDate(t); t.date.auto = false; t.date.type = "solid" })
                                }
                                GlassButton {
                                    text: "Gradient"
                                    active: page.dDate.auto === false && page.dDate.type === "gradient"
                                    onClicked: page.mutate(t => { page.ensureDate(t);
                                        t.date.auto = false
                                        t.date.type = "gradient"
                                        if (!t.date.stops || t.date.stops.length < 2)
                                            t.date.stops = [{ mode: "dyn", i: 3 }, { mode: "dyn", i: 7 }]
                                            if (t.date.horizontal === undefined) t.date.horizontal = true
                                    })
                                }
                            }
                            ColorField {
                                visible: page.dDate.auto === false && page.dDate.type !== "gradient"
                                Layout.fillWidth: true
                                label: "Date"
                                col: page.dDate.color ? page.dDate.color : null
                                open: page.openKey === "date"
                                onToggled: page.toggleOpen("date")
                                onEdited: (v) => page.mutate(t => { page.ensureDate(t); t.date.color = v })
                            }
                            Repeater {
                                model: (page.dDate.auto === false && page.dDate.type === "gradient" && page.dDate.stops) ? page.dDate.stops.length : 0
                                delegate: ColorField {
                                    id: tstop
                                    required property int index
                                    Layout.fillWidth: true
                                    label: "Colour " + (tstop.index + 1)
                                    col: page.dDate.stops[tstop.index]
                                    removable: page.dDate.stops.length > 2
                                    open: page.openKey === "date.stop." + tstop.index
                                    onToggled: page.toggleOpen("date.stop." + tstop.index)
                                    onEdited: (v) => page.mutate(t => { page.ensureDate(t); t.date.stops[tstop.index] = v })
                                    onRemoved: page.mutate(t => { page.ensureDate(t); t.date.stops.splice(tstop.index, 1) })
                                }
                            }
                            Row {
                                visible: page.dDate.auto === false && page.dDate.type === "gradient"
                                spacing: 6
                                GlassButton {
                                    visible: !!(page.dDate.stops && page.dDate.stops.length < 6)
                                    text: "Add colour"
                                    onClicked: page.mutate(t => { page.ensureDate(t); t.date.stops.push({ mode: "dyn", i: (t.date.stops.length * 3 + 1) % 16 }) })
                                }
                                GlassButton {
                                    text: "Left to right"
                                    active: page.dDate.horizontal !== false
                                    onClicked: page.mutate(t => { page.ensureDate(t); t.date.horizontal = true })
                                }
                                GlassButton {
                                    text: "Top to bottom"
                                    active: page.dDate.horizontal === false
                                    onClicked: page.mutate(t => { page.ensureDate(t); t.date.horizontal = false })
                                }
                            }
                            Hint {
                                visible: page.dDate.auto === false && page.dDate.type === "gradient"
                                text: "The date shown under the clock in the bar. Default is the wallpaper's colour 3. A gradient is drawn across the date text itself."
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

                    // ---- active / highlighted buttons ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Active buttons" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 8
                            Row {
                                spacing: 6
                                GlassButton {
                                    text: "Default"
                                    active: page.dAccent.auto !== false
                                    onClicked: page.mutate(t => { page.ensureAccent(t); t.accent.auto = true })
                                }
                                GlassButton {
                                    text: "Custom"
                                    active: page.dAccent.auto === false
                                    onClicked: page.mutate(t => { page.ensureAccent(t); t.accent.auto = false })
                                }
                            }
                            ColorField {
                                visible: page.dAccent.auto === false
                                Layout.fillWidth: true
                                label: "Active"
                                col: page.dAccent.active
                                open: page.openKey === "accent.active"
                                onToggled: page.toggleOpen("accent.active")
                                onEdited: (v) => page.mutate(t => { page.ensureAccent(t); t.accent.active = v })
                            }
                            ColorField {
                                visible: page.dAccent.auto === false
                                Layout.fillWidth: true
                                label: "Hover"
                                col: page.dAccent.hover
                                open: page.openKey === "accent.hover"
                                onToggled: page.toggleOpen("accent.hover")
                                onEdited: (v) => page.mutate(t => { page.ensureAccent(t); t.accent.hover = v })
                            }
                            Row {
                                visible: page.dAccent.auto === false
                                spacing: 6
                                GlassButton {
                                    text: "Text: automatic"
                                    active: page.dAccent.textAuto !== false
                                    onClicked: page.mutate(t => { page.ensureAccent(t); t.accent.textAuto = true })
                                }
                                GlassButton {
                                    text: "Text: custom"
                                    active: page.dAccent.textAuto === false
                                    onClicked: page.mutate(t => { page.ensureAccent(t); t.accent.textAuto = false })
                                }
                            }
                            ColorField {
                                visible: page.dAccent.auto === false && page.dAccent.textAuto === false
                                Layout.fillWidth: true
                                label: "Text on active"
                                col: page.dAccent.text
                                open: page.openKey === "accent.text"
                                onToggled: page.toggleOpen("accent.text")
                                onEdited: (v) => page.mutate(t => { page.ensureAccent(t); t.accent.text = v })
                            }
                            Row {
                                visible: page.dAccent.auto === false
                                spacing: 8
                                Repeater {
                                    model: [{ l: "Active", k: "active" }, { l: "Hover", k: "hover" }]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 90; height: 28; radius: Theme.radiusSm
                                        readonly property color c: Theme.colorOf(page.dAccent[modelData.k], page.previewDark, page.adapts)
                                        color: c
                                        Text {
                                            anchors.centerIn: parent
                                            text: parent.modelData.l
                                            color: page.accentTextFor(parent.c)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSm
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                            Hint { text: "The colour of the button that is switched on (the highlighted tab, the chosen option) and of buttons you hover. Default uses your wallpaper colours. The text on active buttons is automatic (black or white, whichever reads better) or a colour you pick." }
                        }
                    }

                    // ---- light mode ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Light mode" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignTop
                            spacing: 6
                            Row {
                                spacing: 6
                                GlassButton {
                                    text: "Adapt"
                                    active: page.adapts
                                    onClicked: page.mutate(t => { t.adapt = true })
                                }
                                GlassButton {
                                    text: "Same as dark"
                                    active: !page.adapts
                                    onClicked: page.mutate(t => { t.adapt = false })
                                }
                            }
                            Hint { text: "Everything above is what you see in dark mode. Adapt: in light mode every colour keeps its hue but its lightness is mirrored, and the brightness you set is inverted (darker becomes lighter), so text stays readable on the surface. Same as dark: colours and brightness are used exactly as set in both modes." }
                            Hint { text: "Opacity can't go below 40%, so text never floats on nothing. Preview cannot show the blur itself." }
                        }
                    }

                    Item { Layout.preferredHeight: 4 }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                GlassButton { text: "Preview"; onClicked: { page.openKey = ""; page.view = "preview" } }
                GlassButton { text: "Save & apply"; active: true; onClicked: page.saveDraft() }
                GlassButton { text: "Cancel"; onClicked: page.closeEditor() }
                Item { Layout.fillWidth: true }
            }
        }
    }

    // =====================================================================
    // PREVIEW
    // =====================================================================
    Component {
        id: previewView

        ColumnLayout {
            id: pv
            spacing: 10

            readonly property var popupFill: Theme.resolveFill(page.dPopup, page.previewDark, page.adapts)
            readonly property var barFill: Theme.resolveFill(page.dBar, page.previewDark, page.adapts)
            readonly property var textRes: Theme.resolveText(page.dText, page.previewDark, page.adapts)
            readonly property color txt: pv.textRes !== null
            ? pv.textRes
            : (page.previewDark ? Theme.palette.foreground : "#1a1625")
            readonly property var tgrad: Theme.resolveTextGradient(page.dText, page.previewDark, page.adapts)
            // the date's colour as this draft would draw it: a gradient, a solid colour, or the default (colour 3)
            readonly property bool dateCustom: page.dDate.auto === false
            readonly property var dateGrad: pv.dateCustom && page.dDate.type === "gradient"
            ? Theme.resolveTextGradient(page.dDate, page.previewDark, page.adapts) : null
            readonly property color dateCol: pv.dateCustom
            ? Theme.colorOf(page.dDate.type === "gradient" ? (page.dDate.stops ? page.dDate.stops[0] : null) : page.dDate.color, page.previewDark, page.adapts)
            : (page.previewDark ? Qt.lighter(Theme.color3, 1.5) : Qt.darker(Theme.color3, 2.8))
            readonly property color txtDim: Qt.rgba(pv.txt.r, pv.txt.g, pv.txt.b, 0.6)
            // active / hover button colours and the text on them, as this draft would draw them
            readonly property bool accCustom: page.dAccent.auto === false
            readonly property color accA: pv.accCustom ? Theme.colorOf(page.dAccent.active, page.previewDark, page.adapts)
            : Theme.adaptColorFor(Theme.color3, page.previewDark)
            readonly property color accH: pv.accCustom ? Theme.colorOf(page.dAccent.hover, page.previewDark, page.adapts)
            : Theme.adaptColorFor(Theme.color1, page.previewDark)
            readonly property color accT: !pv.accCustom ? "#000000"
            : (page.dAccent.textAuto === false ? Theme.colorOf(page.dAccent.text, page.previewDark, page.adapts)
            : ((0.299 * pv.accA.r + 0.587 * pv.accA.g + 0.114 * pv.accA.b) > 0.55 ? "#000000" : "#ffffff"))

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                GlassButton { text: "Back"; onClicked: page.view = "edit" }
                Text {
                    Layout.fillWidth: true
                    text: "Preview"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }
                GlassButton { text: "Dark"; active: page.previewDark; onClicked: page.previewDark = true }
                GlassButton { text: "Light"; active: !page.previewDark; onClicked: page.previewDark = false }
            }

            Rectangle {
                id: stage
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.radiusMd
                clip: true
                border.width: 1
                border.color: Theme.borderMuted

                // stand-in wallpaper, so translucency is visible
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Theme.colorOf({ mode: "dyn", i: 4 }, page.previewDark, false) }
                    GradientStop { position: 0.5; color: Theme.colorOf({ mode: "dyn", i: 1 }, page.previewDark, false) }
                    GradientStop { position: 1.0; color: Theme.colorOf({ mode: "dyn", i: 3 }, page.previewDark, false) }
                }

                // ---- bar ----
                GlassPanel {
                    id: mockBar
                    themeFill: pv.barFill
                    anchors.top: parent.top
                    anchors.topMargin: 20
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width - 48, 460)
                    height: 40
                    radius: 20

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Repeater {
                            model: 4
                            delegate: Rectangle { width: 14; height: 14; radius: 7; color: pv.txt; opacity: 0.85 }
                        }
                    }
                    GradientText {
                        anchors.centerIn: parent
                        textGrad: pv.tgrad
                        fallbackColor: pv.txt
                        text: "Bar"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }
                    Column {
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.right: parent.right
                            text: "12:34"
                            color: pv.txt
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                            font.bold: true
                        }
                        GradientText {
                            anchors.right: parent.right
                            textGrad: pv.dateGrad
                            fallbackColor: pv.dateCol
                            text: "Sun 25 Oct"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeXs
                            font.bold: true
                        }
                    }
                }

                // ---- popup ----
                GlassPanel {
                    id: mockPopup
                    themeFill: pv.popupFill
                    anchors.left: parent.left
                    anchors.leftMargin: 24
                    anchors.top: mockBar.bottom
                    anchors.topMargin: 28
                    width: Math.max(170, (parent.width - 72) * 0.45)
                    height: 168

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 8
                        GradientText {
                            textGrad: pv.tgrad
                            fallbackColor: pv.txt
                            text: "Popup"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeLg
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: "Body text on this surface."
                            color: pv.txt
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                        Text {
                            text: "Secondary text"
                            color: pv.txtDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 8
                            radius: 4
                            color: Qt.rgba(pv.txt.r, pv.txt.g, pv.txt.b, 0.2)
                            Rectangle { width: parent.width * 0.6; height: parent.height; radius: 4; color: pv.accA }
                        }
                        Item { Layout.fillHeight: true }
                        Row {
                            spacing: 8
                            Repeater {
                                model: [{ l: "Active", hov: false }, { l: "Hovered", hov: true }]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 86; height: 26
                                    radius: Theme.radiusSm
                                    color: modelData.hov ? pv.accH : pv.accA
                                    Text {
                                        anchors.centerIn: parent
                                        text: parent.modelData.l
                                        color: pv.accT
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeSm
                                        font.bold: true
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- notification ----
                GlassPanel {
                    id: mockToast
                    themeFill: pv.popupFill
                    anchors.right: parent.right
                    anchors.rightMargin: 24
                    anchors.top: mockBar.bottom
                    anchors.topMargin: 28
                    width: Math.max(180, (parent.width - 72) * 0.55)
                    height: 84

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 4
                        GradientText {
                            textGrad: pv.tgrad
                            fallbackColor: pv.txt
                            text: "Notification"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: "Something happened. This is how a notification card looks."
                            color: pv.txtDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSm
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }

    // =====================================================================
    // IMAGE BROWSER
    // =====================================================================
    Component {
        id: browseView

        ImageBrowser {
            onPicked: (f) => {
                page.mutate(t => { t[page.browseFor].image = f })
                page.view = "edit"
            }
            onCancelled: page.view = "edit"
        }
    }
}
