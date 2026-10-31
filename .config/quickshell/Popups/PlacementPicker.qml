import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Widgets"

// A mock screen with a card where the popup will appear, and a 3x3 grid of buttons to
// pick the spot. `value` is "<top|center|bottom>-<left|center|right>"; `options` is the
// list of allowed values (the middle cell is left empty when "center-center" is not allowed).
ColumnLayout {
    id: pk

    property string value: "center-right"
    property var options: []
    // card size in virtual 1280x720 screen pixels, and the gap it keeps from the edge
    property real cardW: 220
    property real cardH: 280
    property real gap: 12
    signal picked(string v)

    readonly property var cells: [
        "top-left", "top-center", "top-right",
        "center-left", "center-center", "center-right",
        "bottom-left", "bottom-center", "bottom-right"
    ]
    readonly property string pv: pk.value.split("-")[0]
    readonly property string ph: pk.value.split("-")[1]

    spacing: 8

    Rectangle {
        id: mock
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 300
        Layout.preferredHeight: 300 * 720 / 1280
        radius: 8
        color: Theme.pillOffBg
        border.width: 1
        border.color: Theme.borderMuted
        clip: true

        readonly property real f: width / 1280

        Rectangle {
            width: pk.cardW * mock.f
            height: pk.cardH * mock.f
            radius: Theme.radiusMd * mock.f * 2
            color: Theme.popupBg
            border.width: 1
            border.color: Theme.accentActive
            x: pk.ph === "left" ? pk.gap * mock.f
               : (pk.ph === "right" ? mock.width - width - pk.gap * mock.f : (mock.width - width) / 2)
            y: pk.pv === "top" ? pk.gap * mock.f
               : (pk.pv === "bottom" ? mock.height - height - pk.gap * mock.f : (mock.height - height) / 2)
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            // three dots, stacked in a tall card and in a row in a wide one
            Grid {
                anchors.centerIn: parent
                spacing: 3
                columns: pk.cardW > pk.cardH ? 3 : 1
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        width: 5
                        height: 5
                        radius: 2.5
                        color: Theme.foreground
                        opacity: 0.5
                    }
                }
            }
        }
    }

    Grid {
        Layout.alignment: Qt.AlignHCenter
        columns: 3
        spacing: 6
        Repeater {
            model: pk.cells
            delegate: Item {
                required property string modelData
                readonly property bool allowed: pk.options.indexOf(modelData) >= 0
                width: 92
                height: 30
                GlassButton {
                    anchors.fill: parent
                    visible: parent.allowed
                    text: {
                        const p = parent.modelData.split("-")
                        return p[0] === "center" && p[1] !== "center" ? "Middle " + p[1]
                             : p[0].charAt(0).toUpperCase() + p[0].slice(1) + " " + p[1]
                    }
                    fontSize: Theme.fontSizeSm
                    active: pk.value === parent.modelData
                    onClicked: pk.picked(parent.modelData)
                }
            }
        }
    }
}
