import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Widgets"
import "../Services"

// One tile on Settings > Theme: a small live picture of a single theme.
//
//  - the tile's bar and popup are drawn with THAT theme's own fills (colour, gradient or image)
//  - the name is drawn in THAT theme's text colour / gradient, the date in its date colour
//  - the Active / Hover chips use THAT theme's own button colours and the text colour on them
//  - Edit / Delete (bottom right) are drawn in the tile's own colours too, and light up
//    with its hover colour
//
// A tile with `def: null` is one of the built-in surfaces ("blur" / "opaque"): same look,
// no Edit / Delete. Click the tile to apply it.
Item {
    id: tile

    property var def: null            // custom theme definition, or null for a built-in surface
    property string builtin: ""       // "blur" | "opaque" (used when def is null)
    property string title: ""
    property bool inUse: false
    property bool armed: false        // Delete has been clicked once ("Sure?")

    signal activated()
    signal editClicked()
    signal deleteClicked()
    signal deleteDisarmed()

    implicitHeight: 142

    // ---------------------------------------------------------------------
    // everything below is resolved from the theme's own definition
    // ---------------------------------------------------------------------
    readonly property bool custom: tile.def !== null
    readonly property bool dark: Theme.effectiveDark
    readonly property bool adapts: tile.custom ? tile.def.adapt !== false : true
    readonly property bool hovered: hov.hovered

    // built-in surfaces, exactly as Theme paints them
    readonly property var builtinFill: {
        const bg = (tile.builtin === "opaque")
        ? Theme._popupSurface(tile.dark)
        : (tile.dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.55))
        return { kind: "solid", color: bg, avg: bg, opacity: 1 }
    }
    readonly property var popupFill: tile.custom ? Theme.resolveFill(tile.def.popup, tile.dark, tile.adapts) : tile.builtinFill
    readonly property var barFill: tile.custom ? Theme.resolveFill(tile.def.bar, tile.dark, tile.adapts) : tile.builtinFill

    // text colour (solid or gradient)
    readonly property var textRes: tile.custom ? Theme.resolveText(tile.def.text, tile.dark, tile.adapts) : null
    readonly property color txt: tile.textRes !== null ? tile.textRes : (tile.dark ? Theme.palette.foreground : "#1a1625")
    readonly property var tgrad: tile.custom ? Theme.resolveTextGradient(tile.def.text, tile.dark, tile.adapts) : null
    readonly property color txtDim: Qt.rgba(tile.txt.r, tile.txt.g, tile.txt.b, 0.6)

    // date colour (the date under the bar clock)
    readonly property var dateDef: (tile.custom && tile.def.date) ? tile.def.date : null
    readonly property bool dateCustom: tile.dateDef !== null && tile.dateDef.auto === false
    readonly property var dateGrad: (tile.dateCustom && tile.dateDef.type === "gradient")
    ? Theme.resolveTextGradient(tile.dateDef, tile.dark, tile.adapts) : null
    readonly property color dateCol: tile.dateCustom
    ? Theme.colorOf(tile.dateDef.type === "gradient" ? (tile.dateDef.stops ? tile.dateDef.stops[0] : null) : tile.dateDef.color, tile.dark, tile.adapts)
    : (tile.dark ? Qt.lighter(Theme.color3, 1.5) : Qt.darker(Theme.color3, 2.8))

    // active / hover button colours and the text on them
    readonly property var accDef: (tile.custom && tile.def.accent) ? tile.def.accent : null
    readonly property bool accCustom: tile.accDef !== null && tile.accDef.auto === false
    readonly property color accA: tile.accCustom ? Theme.colorOf(tile.accDef.active, tile.dark, tile.adapts)
    : Theme.adaptColorFor(Theme.color3, tile.dark)
    readonly property color accH: tile.accCustom ? Theme.colorOf(tile.accDef.hover, tile.dark, tile.adapts)
    : Theme.adaptColorFor(Theme.color1, tile.dark)
    readonly property color accT: !tile.accCustom ? "#000000"
    : (tile.accDef.textAuto === false ? Theme.colorOf(tile.accDef.text, tile.dark, tile.adapts)
    : ((0.299 * tile.accA.r + 0.587 * tile.accA.g + 0.114 * tile.accA.b) > 0.55 ? "#000000" : "#ffffff"))

    // one dim line under the name
    function _kind(f) { return (f && f.type === "gradient") ? "gradient" : ((f && f.type === "pattern") ? "image" : "solid") }
    readonly property string subtitle: tile.custom
    ? ("Popups " + tile._kind(tile.def.popup) + "  \u00b7  Bar " + tile._kind(tile.def.bar))
    : (tile.builtin === "opaque" ? "Solid, wallpaper-tinted" : "Translucent, blur behind")

    // ---------------------------------------------------------------------
    // behaviour
    // ---------------------------------------------------------------------
    transformOrigin: Item.Center
    scale: tile.hovered ? (1 + (Animations.hoverScale - 1) * 0.5) : 1.0
    Behavior on scale { NumberAnimation { duration: Animations.hoverScaleDuration; easing.type: Animations.hoverScaleEasing } }

    HoverHandler {
        id: hov
        onHoveredChanged: if (!hovered && tile.armed) tile.deleteDisarmed()
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: tile.activated()
    }

    // ---------------------------------------------------------------------
    // small pieces (colours are passed in: inline components cannot see the tile's id)
    // ---------------------------------------------------------------------
    component Chip: Rectangle {
        property string text: ""
        property color fillC: "transparent"
        property color textC: "#000000"
        implicitHeight: 20
        implicitWidth: chipLabel.implicitWidth + 16
        radius: Theme.radiusSm
        color: fillC
        Text {
            id: chipLabel
            anchors.centerIn: parent
            text: parent.text
            color: parent.textC
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.bold: true
        }
    }

    component TileBtn: Rectangle {
        id: b
        property string text: ""
        property bool armedState: false
        property color baseC: "#ffffff"      // the tile's text colour
        property color hoverC: "#808080"     // the tile's hover colour
        property color activeC: "#808080"    // the tile's active colour
        property color onAccC: "#000000"     // text on those two
        signal clicked()
        readonly property bool hot: bm.containsMouse
        implicitHeight: 22
        implicitWidth: btnLabel.implicitWidth + 18
        radius: Theme.radiusSm
        color: b.armedState ? b.activeC : (b.hot ? b.hoverC : "transparent")
        border.width: 1
        border.color: (b.hot || b.armedState) ? "transparent" : Qt.rgba(b.baseC.r, b.baseC.g, b.baseC.b, 0.45)
        Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Text {
            id: btnLabel
            anchors.centerIn: parent
            text: b.text
            color: (b.hot || b.armedState) ? b.onAccC : b.baseC
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeXs
            font.bold: true
        }
        MouseArea {
            id: bm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: b.clicked()
        }
    }

    // ---------------------------------------------------------------------
    // the picture
    // ---------------------------------------------------------------------
    GlassPanel {
        id: stage
        themeFill: tile.popupFill
        showBorder: false            // tiles keep their own outline; no border effects on a wall of tiles
        anchors.fill: parent
        radius: Theme.radiusMd
        clip: true

        // ---- mini bar ----
        GlassPanel {
            id: bar
            themeFill: tile.barFill
            showBorder: false
            anchors.top: parent.top
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: parent.right
            anchors.rightMargin: 10
            height: 22
            radius: 11

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                Repeater {
                    model: 3
                    delegate: Rectangle { width: 7; height: 7; radius: 3.5; color: tile.txt; opacity: 0.85 }
                }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "12:34"
                    color: tile.txt
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.bold: true
                }
                GradientText {
                    anchors.verticalCenter: parent.verticalCenter
                    textGrad: tile.dateGrad
                    fallbackColor: tile.dateCol
                    text: "Sun 25 Oct"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                    font.bold: true
                }
            }
        }

        // ---- name, subtitle, chips, Edit / Delete: drawn straight on the tile's own fill ----
        ColumnLayout {
            anchors.top: bar.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                GradientText {
                    Layout.fillWidth: true
                    textGrad: tile.tgrad
                    fallbackColor: tile.txt
                    text: tile.title
                    elide: Text.ElideRight
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize + 1
                    font.bold: true
                }
                Chip {
                    visible: tile.inUse
                    text: "In use"
                    fillC: tile.accA
                    textC: tile.accT
                }
            }

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: tile.subtitle
                color: tile.txtDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Chip { text: "Active"; fillC: tile.accA; textC: tile.accT }
                Chip { text: "Hover"; fillC: tile.accH; textC: tile.accT }

                Item { Layout.fillWidth: true }

                Text {
                    visible: !tile.custom
                    text: "Built-in"
                    color: tile.txtDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeXs
                }
                TileBtn {
                    visible: tile.custom
                    text: "Edit"
                    baseC: tile.txt; hoverC: tile.accH; activeC: tile.accA; onAccC: tile.accT
                    onClicked: tile.editClicked()
                }
                TileBtn {
                    visible: tile.custom
                    text: tile.armed ? "Really delete?" : "Delete"
                    armedState: tile.armed
                    baseC: tile.txt; hoverC: tile.accH; activeC: tile.accA; onAccC: tile.accT
                    onClicked: tile.deleteClicked()
                }
            }
        }
    }

    // outline on top: the tile's own active colour when in use, its hover colour when hovered
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusMd
        color: "transparent"
        border.width: tile.inUse ? 2 : 1
        border.color: tile.inUse ? tile.accA : (tile.hovered ? tile.accH : Theme.borderMuted)
        Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
}
