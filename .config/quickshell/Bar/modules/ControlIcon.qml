import QtQuick
import Qt5Compat.GraphicalEffects
import "../../Theme"
import "../../Services"

Item {
    id: root
    // the bar this icon sits in (Bar.qml passes its config); default = the classic bar
    property var cfg: BarSettings
    implicitWidth: cfg.vertical ? cfg.thickness : Math.max(34, contentRow.implicitWidth + 10)
    implicitHeight: cfg.vertical ? Math.max(34, contentRow.implicitHeight + 10) : cfg.thickness
    width: implicitWidth
    height: implicitHeight

    property string glyph: ""
    property string text: ""
    property url iconSource: ""
    // Id of a customisable icon (see IconSettings.slots). "" = not customisable.
    property string iconId: ""
    property int iconSize: 16

    // The file actually drawn: the user's choice for iconId, else iconSource.
    // Slots that currently show text instead of an icon (iconSource empty) stay text.
    readonly property url effectiveSource: (root.iconId === "" || root.iconSource.toString() === "")
    ? root.iconSource : IconSettings.source(root.iconId, root.iconSource)
    readonly property bool customIcon: root.iconId !== "" && IconSettings.customPath(root.iconId) !== ""
    readonly property bool mono: root.iconId !== "" && IconSettings.isMono(root.iconId)
    signal activated()

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusSm
        color: mouse.containsMouse ? Theme.hoverBg : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 4

        Image {
            id: iconImg
            visible: root.effectiveSource.toString().length > 0
            source: root.effectiveSource
            sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
            sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
            width: root.iconSize
            height: root.iconSize
            anchors.verticalCenter: parent.verticalCenter
            smooth: true

            // Monochromize: flat white (dark mode) / black (light mode). Otherwise a built-in
            // icon is tinted with the text colour as before, and a custom image keeps its colours.
            layer.enabled: root.effectiveSource.toString().length > 0 && (root.mono || !root.customIcon)
            layer.smooth: true
            layer.textureSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
            layer.effect: ColorOverlay {
                color: root.mono ? (Theme.effectiveDark ? "#ffffff" : "#000000") : Theme.iconColor
            }
        }
        Text {
            visible: root.effectiveSource.toString().length === 0
            text: root.glyph
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            visible: root.text.length > 0
            text: root.text
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
