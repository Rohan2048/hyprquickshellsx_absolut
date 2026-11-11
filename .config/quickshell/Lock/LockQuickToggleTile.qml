import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import "../Widgets"
import "../Theme"

ColumnLayout {
    id: root
    signal iconClicked()
    signal labelClicked()
    property bool active: false
    property string label: ""
    property string sublabel: ""
    property string iconSource: ""
    // id of a customisable icon (Settings > Lock screen > Icons); "" = just iconSource
    property string iconId: ""
    property bool labelIsButton: true      // false for tiles with no sub-flow (e.g. Airplane)

    spacing: 4

    Rectangle {
        id: box
        Layout.preferredWidth: 56
        Layout.preferredHeight: 56
        Layout.alignment: Qt.AlignHCenter
        radius: Theme.radiusSm
        color: root.active
        ? Qt.rgba(Theme.color3.r, Theme.color3.g, Theme.color3.b,  0.55)
        : Qt.rgba(Theme.popupBg.r, Theme.popupBg.g, Theme.popupBg.b, 0.55)
        border.width: 1
        border.color: root.active
        ? Theme.color3
        : (boxArea.containsMouse ? Theme.accentHover : Theme.borderMuted)
        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on border.color { ColorAnimation { duration: 150 } }

        scale: boxArea.containsMouse ? 1.06 : 1.0
        transformOrigin: Item.Center
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        ThemedIcon {
            anchors.centerIn: parent
            iconId: root.iconId
            fallback: root.iconSource
            size: 22
        }

        MouseArea {
            id: boxArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.iconClicked()
        }
    }

    // Fixed-height wrapper so the label row lines up the same whether it's
    // a GlassButton (Wifi/Bluetooth) or plain Text (Airplane) underneath —
    // GlassButton's own implicit sizing doesn't match bare Text's, which
    // was throwing Airplane's row out of vertical alignment with the rest.
    Item {
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: root.labelIsButton ? labelBtn.implicitWidth : labelTxt.implicitWidth
        implicitHeight: 22

        GlassButton {
            id: labelBtn
            anchors.centerIn: parent
            visible: root.labelIsButton
            text: root.label
            fontSize: Theme.fontSizeSm
            implicitHeight: 22
            onClicked: root.labelClicked()
        }

        Text {
            id: labelTxt
            anchors.centerIn: parent
            visible: !root.labelIsButton
            text: root.label
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSm
            font.bold: true
        }
    }

    Text {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: 90
        visible: text.length > 0
        text: root.sublabel
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fs(10)
        elide: Text.ElideRight
    }
}
