import QtQuick
import "../Theme"
import "../Services"

// Same visual language as GlassButton (hover/active colors, hover-pop scale)
// but sized to a FIXED width instead of growing to fit its text, and clips
// overflow instead of letting it bleed past its own bounds â€” that bleed was
// what made long wifi/bluetooth names look like they were "clipping at one
// side" against the ScrollView they sat inside. Long names auto-scroll
// (MarqueeText) on hover instead of being truncated or left to overflow.
Rectangle {
    id: root
    signal clicked()

    property string text: ""
    property bool active: false
    property bool elevated: false
    property bool disabled: false
    property real borderWidth: 1
    property color inactiveTextColor: Theme.foreground

    readonly property bool hovered: mouse.containsMouse

    property real defaultRadius: Theme.radiusSm
    readonly property var _st: PopupSettings.styleFor(root, root.defaultRadius)
    radius: root._st.r
    clip: true
    border.width: elevated ? (hovered ? 1 : 0) : borderWidth

    color: active ? (hovered ? Theme.accentHover : Theme.accentActive)
    : (hovered ? Theme.hoverBgStrong : "transparent")
    border.color: active ? (hovered ? Theme.accentHover : Theme.accentActive)
    : (hovered ? Theme.accentHover : Theme.borderMuted)
    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }

    transformOrigin: Item.Center
    scale: (hovered && !disabled) ? Animations.hoverScale : 1.0
    Behavior on scale {
        NumberAnimation { duration: Animations.hoverScaleDuration; easing.type: Animations.hoverScaleEasing }
    }

    implicitHeight: 30 * root._st.h
    implicitWidth: 173 * root._st.w
    MarqueeText {
        anchors.fill: parent
        anchors.leftMargin: 10 + root._st.dx
        anchors.rightMargin: 10 - root._st.dx
        anchors.topMargin: root._st.dy
        anchors.bottomMargin: -root._st.dy
        text: root.text
        textColor: root.active ? Theme.textOnAccent : root.inactiveTextColor
        active: root.hovered
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        font.bold: true
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
