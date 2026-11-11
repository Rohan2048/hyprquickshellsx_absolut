import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Widgets"

// Editor for ONE fill of a custom theme (popups, or the bar):
//   Solid colour | Gradient (2 to 6 colours) | Pattern (your own image)
// plus, for every type, Opacity and Brightness. For a pattern the colour is a
// tint laid over the image.
// Brightness is set once (for dark mode); light mode uses the inverse.
//
// Data lives in the parent: this item gets the fill (`fillDef`) and emits
// changed(newFillDef) with a modified copy.
ColumnLayout {
    id: ed

    property var fillDef: ({})
    property string prefix: "popup"          // key prefix for the picker that is open
    property string openKey: ""              // which ColorField is open (owned by the page)
    signal changed(var def)
    signal openToggled(string key)
    signal browseRequested()

    spacing: 10

    readonly property string type: (ed.fillDef && ed.fillDef.type) ? ed.fillDef.type : "solid"
    readonly property int stopCount: (ed.fillDef && ed.fillDef.stops) ? ed.fillDef.stops.length : 0

    function mod(fn) {
        const d = JSON.parse(JSON.stringify(ed.fillDef))
        fn(d)
        ed.changed(d)
    }
    function fileName(p) {
        const i = p.lastIndexOf("/")
        return i >= 0 ? p.slice(i + 1) : p
    }

    component SliderRow: RowLayout {
        id: sr
        property string label: ""
        property real value: 0
        property real from: 0
        property real to: 100
        property bool signedValue: false
        signal moved(real v)
        Layout.fillWidth: true
        spacing: 8
        Text {
            text: sr.label
            Layout.preferredWidth: 76
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
        GlassSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            min: sr.from
            max: sr.to
            value: sr.value
            onValueCommitted: (v) => sr.moved(v)
        }
        Text {
            text: (sr.signedValue && sr.value > 0 ? "+" : "") + Math.round(sr.value) + "%"
            Layout.preferredWidth: 48
            horizontalAlignment: Text.AlignRight
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    // ---------------- type ----------------
    Row {
        spacing: 6
        GlassButton { text: "Solid colour"; active: ed.type === "solid"; onClicked: ed.mod(d => { d.type = "solid" }) }
        GlassButton { text: "Gradient"; active: ed.type === "gradient"; onClicked: ed.mod(d => { d.type = "gradient" }) }
        GlassButton { text: "Pattern"; active: ed.type === "pattern"; onClicked: ed.mod(d => { d.type = "pattern" }) }
    }

    // ---------------- solid ----------------
    ColorField {
        visible: ed.type === "solid"
        Layout.fillWidth: true
        label: "Colour"
        col: ed.fillDef ? ed.fillDef.color : null
        open: ed.openKey === ed.prefix + ".color"
        onToggled: ed.openToggled(ed.prefix + ".color")
        onEdited: (v) => ed.mod(d => { d.color = v })
    }

    // ---------------- gradient ----------------
    ColumnLayout {
        visible: ed.type === "gradient"
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: ed.type === "gradient" ? ed.stopCount : 0
            delegate: ColorField {
                id: stopField
                required property int index
                Layout.fillWidth: true
                label: "Colour " + (stopField.index + 1)
                col: ed.fillDef.stops[stopField.index]
                removable: ed.stopCount > 2
                open: ed.openKey === ed.prefix + ".stop." + stopField.index
                onToggled: ed.openToggled(ed.prefix + ".stop." + stopField.index)
                onEdited: (v) => ed.mod(d => { d.stops[stopField.index] = v })
                onRemoved: ed.mod(d => { d.stops.splice(stopField.index, 1) })
            }
        }

        Row {
            spacing: 6
            GlassButton {
                visible: ed.stopCount < 6
                text: "Add colour"
                onClicked: ed.mod(d => { d.stops.push({ mode: "dyn", i: (d.stops.length * 3 + 1) % 16 }) })
            }
            GlassButton {
                text: "Top to bottom"
                active: !(ed.fillDef && ed.fillDef.horizontal)
                onClicked: ed.mod(d => { d.horizontal = false })
            }
            GlassButton {
                text: "Left to right"
                active: !!(ed.fillDef && ed.fillDef.horizontal === true)
                onClicked: ed.mod(d => { d.horizontal = true })
            }
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "Two to six colours, spread evenly."
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }
    }

    // ---------------- pattern ----------------
    ColumnLayout {
        visible: ed.type === "pattern"
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                Layout.preferredWidth: 72
                Layout.preferredHeight: 44
                radius: Theme.radiusSm
                color: Theme.pillOffBg
                border.width: 1
                border.color: Theme.borderMuted
                clip: true
                Image {
                    anchors.fill: parent
                    source: (ed.fillDef && ed.fillDef.image) ? "file://" + ed.fillDef.image : ""
                    sourceSize: Qt.size(144, 88)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                GlassButton { text: (ed.fillDef && ed.fillDef.image) ? "Change image..." : "Choose image..."; onClicked: ed.browseRequested() }
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: (ed.fillDef && ed.fillDef.image) ? ed.fileName(ed.fillDef.image) : "No image chosen"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
            }
        }

        Row {
            spacing: 6
            GlassButton { text: "Fill"; active: !(ed.fillDef && ed.fillDef.tile); onClicked: ed.mod(d => { d.tile = false }) }
            GlassButton { text: "Tile"; active: !!(ed.fillDef && ed.fillDef.tile === true); onClicked: ed.mod(d => { d.tile = true }) }
        }

        ColorField {
            Layout.fillWidth: true
            label: "Tint"
            col: ed.fillDef ? ed.fillDef.tint : null
            open: ed.openKey === ed.prefix + ".tint"
            onToggled: ed.openToggled(ed.prefix + ".tint")
            onEdited: (v) => ed.mod(d => { d.tint = v })
        }
        SliderRow {
            label: "Tint amount"
            from: 0
            to: 100
            value: ed.fillDef && ed.fillDef.tintAmt !== undefined ? ed.fillDef.tintAmt : 0
            onMoved: (v) => ed.mod(d => { d.tintAmt = Math.round(v) })
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            text: "The image is cropped to fill (or tiled) and laid under everything on the bar / popup. The file is used where it is: if you move or delete it, the tint colour is shown instead."
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }
    }

    // ---------------- every type ----------------
    SliderRow {
        label: "Opacity"
        from: Theme.minOpacity
        to: 100
        value: ed.fillDef && ed.fillDef.opacity !== undefined ? Math.max(Theme.minOpacity, ed.fillDef.opacity) : 100
        onMoved: (v) => ed.mod(d => { d.opacity = Math.round(v) })
    }
    SliderRow {
        label: "Brightness"
        from: -100
        to: 100
        signedValue: true
        value: ed.fillDef && ed.fillDef.brightness !== undefined ? ed.fillDef.brightness : 0
        onMoved: (v) => ed.mod(d => { d.brightness = Math.round(v) })
    }
}
