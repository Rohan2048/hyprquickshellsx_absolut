import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../Theme"

// One colour of a custom theme. A collapsed row (swatch + summary); click to
// open the picker:
//   Dynamic : one of the 16 wallpaper-palette colours (follows pywal / wallpaper changes)
//   Fixed   : your own colour (hue / saturation / lightness sliders, or a hex code)
// The colour is authored for dark mode; light mode adapts it (see Theme.colorOf).
//
// col = { mode: "dyn", i: 0..15 } | { mode: "fix", hex: "#rrggbb", h, s, l }
// The parent owns `open` (so only one picker is open at a time) and the data:
// this item only emits edited(value) / toggled() / removed().
ColumnLayout {
    id: root

    property var col: ({ mode: "dyn", i: 0 })
    property string label: ""
    property bool open: false
    property bool removable: false
    signal edited(var value)
    signal toggled()
    signal removed()

    spacing: 6

    readonly property bool isDyn: !root.col || root.col.mode !== "fix"
    readonly property color shown: Theme.colorOf(root.col, true, false)
    property int lastDyn: 0
    onColChanged: { if (root.col && root.col.mode === "dyn") root.lastDyn = root.col.i }
    Component.onCompleted: { if (root.col && root.col.mode === "dyn") root.lastDyn = root.col.i }

    readonly property real hue: (root.col && root.col.h !== undefined)
    ? root.col.h : Math.round((root.shown.hslHue < 0 ? 0 : root.shown.hslHue) * 360)
    readonly property real sat: (root.col && root.col.s !== undefined)
    ? root.col.s : Math.round(root.shown.hslSaturation * 100)
    readonly property real lig: (root.col && root.col.l !== undefined)
    ? root.col.l : Math.round(root.shown.hslLightness * 100)

    readonly property string summary: root.isDyn
    ? "Dynamic · colour " + (root.col ? root.col.i : 0)
    : String(root.col && root.col.hex ? root.col.hex : "#808080").toUpperCase()

    function toHex(c) {
        function two(v) { const s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }
        return "#" + two(c.r) + two(c.g) + two(c.b)
    }
    function fixedFromHsl(h, s, l) {
        const c = Qt.hsla(h / 360, s / 100, l / 100, 1)
        return { mode: "fix", hex: root.toHex(c), h: Math.round(h), s: Math.round(s), l: Math.round(l) }
    }
    function fixedFromHex(hex) {
        const c = Qt.color(hex)
        return {
            mode: "fix", hex: hex,
            h: Math.round((c.hslHue < 0 ? 0 : c.hslHue) * 360),
            s: Math.round(c.hslSaturation * 100),
            l: Math.round(c.hslLightness * 100)
        }
    }

    component HslRow: RowLayout {
        id: hr
        property string label: ""
        property real value: 0
        property real max: 100
        signal moved(real v)
        Layout.fillWidth: true
        spacing: 8
        Text {
            text: hr.label
            Layout.preferredWidth: 76
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }
        GlassSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            min: 0
            max: hr.max
            value: hr.value
            onValueCommitted: (v) => hr.moved(v)
        }
        Text {
            text: Math.round(hr.value)
            Layout.preferredWidth: 34
            horizontalAlignment: Text.AlignRight
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
        }
    }

    // ---------------- collapsed row ----------------
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 32
        radius: Theme.radiusSm
        color: headMouse.containsMouse ? Theme.hoverBgStrong : "transparent"
        border.width: 1
        border.color: root.open ? Theme.accentActive : Theme.borderMuted

        MouseArea {
            id: headMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 6
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                radius: 5
                color: root.shown
                border.width: 1
                border.color: Theme.borderMuted
            }
            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.label !== "" ? root.label + "  ·  " + root.summary : root.summary
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
            Text {
                text: root.open ? "Done" : "Edit"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
            Rectangle {
                visible: root.removable
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                radius: Theme.radiusSm
                color: rmMouse.containsMouse ? Theme.hoverBgStrong : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                }
                MouseArea {
                    id: rmMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.removed()
                }
            }
        }
    }

    // ---------------- picker ----------------
    ColumnLayout {
        visible: root.open
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 8

        Row {
            spacing: 6
            GlassButton {
                text: "Dynamic"
                active: root.isDyn
                onClicked: { if (!root.isDyn) root.edited({ mode: "dyn", i: root.lastDyn }) }
            }
            GlassButton {
                text: "Fixed"
                active: !root.isDyn
                onClicked: { if (root.isDyn) root.edited(root.fixedFromHex(root.toHex(root.shown))) }
            }
        }

        // ---- dynamic: the 16 wallpaper palette colours ----
        ColumnLayout {
            visible: root.isDyn
            Layout.fillWidth: true
            spacing: 6

            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: 16
                    delegate: Rectangle {
                        id: sw
                        required property int index
                        readonly property bool sel: !!(root.isDyn && root.col && root.col.i === sw.index)
                        width: 26
                        height: 26
                        radius: 6
                        color: Theme.colorOf({ mode: "dyn", i: sw.index }, true, false)
                        border.width: sw.sel ? 2 : 1
                        border.color: sw.sel ? Theme.accentActive : Theme.borderMuted
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.edited({ mode: "dyn", i: sw.index })
                        }
                    }
                }
            }
            Text {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Follows the wallpaper palette, so it changes with the wallpaper."
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
        }

        // ---- fixed: HSL sliders + hex ----
        ColumnLayout {
            visible: !root.isDyn
            Layout.fillWidth: true
            spacing: 4

            HslRow { label: "Hue"; max: 360; value: root.hue; onMoved: (v) => root.edited(root.fixedFromHsl(v, root.sat, root.lig)) }
            HslRow { label: "Saturation"; max: 100; value: root.sat; onMoved: (v) => root.edited(root.fixedFromHsl(root.hue, v, root.lig)) }
            HslRow { label: "Lightness"; max: 100; value: root.lig; onMoved: (v) => root.edited(root.fixedFromHsl(root.hue, root.sat, v)) }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: "Hex"
                    Layout.preferredWidth: 76
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                }
                TextField {
                    id: hexField
                    Layout.preferredWidth: 110
                    implicitHeight: 28
                    maximumLength: 7
                    selectByMouse: true
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                    validator: RegularExpressionValidator { regularExpression: /^#?[0-9a-fA-F]{0,6}$/ }
                    background: Rectangle {
                        radius: Theme.radiusSm
                        color: "transparent"
                        border.width: 1
                        border.color: hexField.activeFocus ? Theme.accentActive : Theme.borderMuted
                    }
                    onTextEdited: {
                        const m = /^#?([0-9a-fA-F]{6})$/.exec(hexField.text)
                        if (m) root.edited(root.fixedFromHex("#" + m[1].toLowerCase()))
                    }
                }
                Binding {
                    target: hexField
                    property: "text"
                    value: root.col && root.col.hex ? root.col.hex : ""
                    when: !hexField.activeFocus
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
