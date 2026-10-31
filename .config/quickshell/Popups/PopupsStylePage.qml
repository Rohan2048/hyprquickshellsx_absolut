import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Popups > Popup styles: pick one popup (or "All popups") and set how it looks, with a live preview
// that is drawn with the real buttons, so every change shows at once.
//   Popup          scale and panel corner radius                (not for "All popups")
//   Buttons        corner radius, width, height, text offset   (PopupSettings "buttons"; "All popups" = the
//                  default for every popup, a popup's own value wins over it)
Item {
    id: page

    property string sel: "volume"                      // a popup id, or "all"
    readonly property bool isAll: page.sel === "all"
    readonly property bool hasScale: {
        const l = PopupSettings.popups
        for (let i = 0; i < l.length; i++) if (l[i].id === page.sel) return true
            return false
    }
    readonly property var items: [{ id: "all", label: "All popups" }].concat(PopupSettings.radiusItems)

    function resetThis() {
        PopupSettings.clearButtonStyle(page.sel)
        if (!page.isAll) {
            PopupSettings.setScalePct(page.sel, 100)
            PopupSettings.setRadius(page.sel, PopupSettings.defaultRadius(page.sel))
        }
    }

    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    component SectionLabel: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        Layout.fillWidth: true
        Layout.topMargin: 2
    }

    // "label ---slider--- value [Reset]" for one button setting of the selected popup
    component ValRow: RowLayout {
        id: vr
        property string label: ""
        property string key: ""                         // r w h dx dy
        property string unit: "px"
        property bool signedValue: false
        readonly property var lim: PopupSettings.buttonLimits[vr.key]
        readonly property int cur: PopupSettings.buttonVal(page.sel, vr.key,
                                                           vr.key === "r" ? PopupSettings.defaultButtonRadius : PopupSettings.buttonDefaults[vr.key])
        readonly property bool isSet: PopupSettings.buttonValSet(page.sel, vr.key)
        Layout.fillWidth: true
        spacing: 10

        Text {
            text: vr.label
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            Layout.preferredWidth: 150
            elide: Text.ElideRight
        }
        GlassSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            min: vr.lim[0]
            max: vr.lim[1]
            value: vr.cur
            onValueCommitted: (v) => PopupSettings.setButtonVal(page.sel, vr.key, v)
        }
        Text {
            text: (vr.signedValue && vr.cur > 0 ? "+" : "") + vr.cur + " " + vr.unit
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
        }
        GlassButton {
            text: "Reset"
            implicitHeight: 26
            opacity: vr.isSet ? 1 : 0
            disabled: !vr.isSet
            onClicked: PopupSettings.clearButtonVal(page.sel, vr.key)
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: 14; y: 4
            width: flick.width - 28
            spacing: 12

            Hint { text: "Pick a popup and shape it. The preview uses the real buttons, so it always matches what the popup will look like. \"All popups\" sets the default for every popup's buttons; a popup's own value wins over it." }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: page.items
                    delegate: GlassButton {
                        required property var modelData
                        text: modelData.label
                        active: page.sel === modelData.id
                        onClicked: page.sel = modelData.id
                    }
                }
            }

            // ---- live preview ----
            Rectangle {
                id: stage
                Layout.fillWidth: true
                Layout.preferredHeight: 210
                radius: Theme.radiusMd
                color: Qt.rgba(0, 0, 0, 0.18)
                border.width: 1
                border.color: Theme.borderMuted
                clip: true

                // a stand-in popup: its buttons find their style through `popupId`, exactly as in a real popup
                Rectangle {
                    id: mock
                    property string popupId: page.isAll ? "" : page.sel
                    readonly property real want: page.isAll ? 1 : PopupSettings.scaleOf(page.sel)
                    width: 340
                    height: 150
                    anchors.centerIn: parent
                    scale: Math.min(mock.want, (stage.width - 24) / mock.width, (stage.height - 20) / mock.height)
                    transformOrigin: Item.Center
                    radius: page.isAll ? Theme.radiusMd : PopupSettings.radiusOf(page.sel)
                    color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.07)
                    border.width: 1
                    border.color: Theme.borderMuted

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10
                        Text {
                            text: page.isAll ? "Every popup" : (PopupSettings.radiusItems.filter(function (i) { return i.id === page.sel })[0] ?? { label: page.sel }).label
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }
                        RowLayout {
                            spacing: Theme.gapSm
                            GlassButton { text: "Button" }
                            GlassButton { text: "Active"; active: true }
                            GlassButton { text: "Toggle"; variant: "toggle" }
                        }
                        RowLayout {
                            spacing: Theme.gapSm
                            GlassButton { text: "\u25CF Turbo Mode"; variant: "toggle"; active: true; defaultRadius: Theme.radiusPill }
                            GlassButton { text: "\u25CB Go SBS"; variant: "toggle"; defaultRadius: Theme.radiusPill }
                        }
                    }
                }
            }
            Hint {
                visible: !page.isAll && page.hasScale && mock.want > 1 && mock.scale < mock.want - 0.001
                text: "The preview is shown smaller than the real popup so it fits here."
            }

            // ---- the popup ----
            SectionLabel { visible: !page.isAll; text: "Popup" }
            ScaleRow {
                visible: !page.isAll && page.hasScale
                popupId: page.sel
                label: "Scale"
            }
            RadiusRow {
                visible: !page.isAll
                popupId: page.sel
                label: "Corner radius"
            }

            // ---- its buttons ----
            SectionLabel { text: page.isAll ? "Buttons in every popup" : "Buttons in this popup" }
            ValRow { label: "Corner radius"; key: "r"; unit: "px" }
            ValRow { label: "Width"; key: "w"; unit: "%" }
            ValRow { label: "Height"; key: "h"; unit: "%" }
            ValRow { label: "Text offset, horizontal"; key: "dx"; unit: "px"; signedValue: true }
            ValRow { label: "Text offset, vertical"; key: "dy"; unit: "px"; signedValue: true }
            Hint { text: "Width and height stretch the button (100% = normal size). The text offset moves the label right (+) / left (-) and down (+) / up (-) inside the button. Round buttons such as Turbo Mode and Go SBS stay pill-shaped until you set a radius." }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                GlassButton { text: page.isAll ? "Reset button defaults" : "Reset this popup"; onClicked: page.resetThis() }
            }

            Item { Layout.preferredHeight: 4 }
        }
    }
}
