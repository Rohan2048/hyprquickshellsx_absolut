//Glassbutton.qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import "../Theme"
import "../Services"
Rectangle {
    id: root
    signal clicked()
    signal middleClicked()
    property alias text: label.text
    property string icon: ""
    property int iconSize: 20
    property bool active: false
    property bool disabled: false
    property string variant: "button"
    property bool elevated: false
    property color inactiveTextColor: Theme.foreground
    property color hoverBorderColor: Theme.accentHover
    property int borderWidth: elevated ? 0 : 1
    // Settings > Popup styles draws a button that always looks hovered, to show that state next to the others
    property bool forceHover: false
    // lets Widgets/PopupArrange find every button of a popup
    readonly property bool isGlassButton: true
    // Settings > Popups > Popup styles remembers a button's place under its label. A button whose label changes ("Clear all" /
    // "Really clear all?", Grid view / List view) sets a fixed name here, so it stays the same object and keeps its place.
    property string arrangeId: ""
    readonly property bool hovered: mouse.containsMouse || root.forceHover
    property int fontSize: Theme.fontSize - 1
    property alias hoverEnabled: mouse.hoverEnabled
    // When true, color/border.color changes apply immediately with no
    // ColorAnimation. Set this just before removal (e.g. alongside
    // hoverEnabled = false) so an in-flight hover color isn't left
    // animating into a parent's exit blur/layer effect.
    property bool instantColor: false
    property real defaultRadius: Theme.radiusSm      // a button that is round by design sets this
    // corner radius, size and text offset from Settings > Popups > Popup styles
    readonly property var _st: PopupSettings.styleFor(root, root.defaultRadius)
    // a button that is given its own radius (the lock screen's, Settings > Lock screen) ignores the popup styles
    property real radiusOverride: -1
    radius: root.radiusOverride >= 0 ? root.radiusOverride : root._st.r
    clip: true
    border.width: elevated ? (hovered ? 1 : 0) : borderWidth
    opacity: disabled ? 0.5 : 1.0
    Behavior on opacity { NumberAnimation { duration: 180 } }

    color: {
        if (disabled) return Theme.pillOffBg
            if (active) return hovered ? Theme.accentHover : Theme.accentActive
                if (hovered) return Theme.hoverBgStrong
                    return variant === "toggle" ? Theme.pillOffBg : "transparent"
    }
    border.color: {
        // elevated buttons stay borderless at rest (shadow carries the 3D look),
        // but pick up a thin hover ring so hover state is still legible
        if (elevated) return hovered ? hoverBorderColor : "transparent"
            if (disabled) return Theme.borderMuted
                if (active) return hovered ? Theme.accentHover : Theme.accentActive
                    if (hovered) return hoverBorderColor
                        return Theme.borderMuted
    }
    Behavior on color {
        enabled: !root.instantColor
        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    Behavior on border.color {
        enabled: !root.instantColor
        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    layer.enabled: elevated
    layer.effect: MultiEffect {
        shadowEnabled: true
        autoPaddingEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.65
        shadowBlur: 1.0
        shadowVerticalOffset: 4
        shadowHorizontalOffset: 0
        shadowScale: 1.03
    }

    transformOrigin: Item.Center
    scale: (hovered && !disabled) ? Animations.hoverScale : 1.0
    Behavior on scale {
        NumberAnimation { duration: Animations.hoverScaleDuration; easing.type: Animations.hoverScaleEasing }
    }

    readonly property real _contentW: root.icon !== "" ? 30 : label.implicitWidth + 24
    implicitHeight: 30 * root._st.h
    implicitWidth: root._contentW * root._st.w

    // A popup that gives its button an implicitWidth / implicitHeight of its own (a 26 px tick, a 38 px list row)
    // replaces the two lines above, and then the popup style's width / height never reached it. Those buttons are
    // detected here and the style is applied on top of their own size, so Width / Height react for every button.
    readonly property bool _ownW: Math.abs(root.implicitWidth - root._contentW * root._st.w) > 0.5
    readonly property bool _ownH: Math.abs(root.implicitHeight - 30 * root._st.h) > 0.5
    // what is still to be applied on top of the button's own size: the Settings stretch (+ the popup style, own size only)
    readonly property real _fw: root.stretchW * (root._ownW ? root._st.w : 1)
    readonly property real _fh: root.stretchH * (root._ownH ? root._st.h : 1)
    readonly property bool _pinW: Math.abs(root._fw - 1) > 0.001
    readonly property bool _pinH: Math.abs(root._fh - 1) > 0.001

    // A fill-width / fill-height button is as wide as its share of the row, not as wide as its implicit size, so a
    // stretch has to be a fraction of that share. It is noted whenever the button is not stretched.
    property real _slotW: 0
    property real _slotH: 0
    Connections {
        target: root
        function onWidthChanged() { if (!root._pinW && root.width > 0) root._slotW = root.width }
        function onHeightChanged() { if (!root._pinH && root.height > 0) root._slotH = root.height }
    }
    readonly property real _baseW: (Layout.fillWidth && root._slotW > 0) ? root._slotW : (Layout.preferredWidth >= 0 ? Layout.preferredWidth : root.implicitWidth)
    readonly property real _baseH: (Layout.fillHeight && root._slotH > 0) ? root._slotH : (Layout.preferredHeight >= 0 ? Layout.preferredHeight : root.implicitHeight)
    // the size this button is meant to have; a wrapper that sizes itself after its button uses these
    readonly property real styledWidth: root._baseW * root._fw
    readonly property real styledHeight: root._baseH * root._fh

    // a stretched button keeps its stretched size even where a layout would make it fill the row
    // (outside a layout, Widgets/PopupArrange sets the width / height itself)
    Layout.minimumWidth: root._pinW ? root.styledWidth : 0
    Layout.maximumWidth: root._pinW ? root.styledWidth : Number.POSITIVE_INFINITY
    Layout.minimumHeight: root._pinH ? root.styledHeight : 0
    Layout.maximumHeight: root._pinH ? root.styledHeight : Number.POSITIVE_INFINITY

    // where the label sits in a button that is wider than its text: Qt.AlignHCenter (default), Qt.AlignLeft or
    // Qt.AlignRight -- set per piece in Settings > Popups > Popup styles
    property int labelAlign: Qt.AlignHCenter
    // set per button in Settings > Popups > Popup styles (all default = the button as drawn): stretch the BUTTON (the
    // label keeps its size), scale the label's font, and move the label inside the button
    property real stretchW: 1.0
    property real stretchH: 1.0
    property real fontScale: 1.0
    property real textDx: 0
    property real textDy: 0
    ThemedText {
        id: label
        visible: root.icon === ""
        anchors.verticalCenter: parent.verticalCenter
        x: (root.labelAlign === Qt.AlignLeft ? 12 : (root.labelAlign === Qt.AlignRight ? root.width - width - 12 : (root.width - width) / 2)) + root._st.dx + root.textDx
        anchors.verticalCenterOffset: root._st.dy + root.textDy
        color: root.disabled
        ? Theme.textDim
        : (root.active ? Theme.textOnAccent : root.inactiveTextColor)
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize * root.fontScale
        font.bold: true
    }

    Image {
        id: iconImg
        visible: false
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root._st.dx + root.textDx
        anchors.verticalCenterOffset: root._st.dy + root.textDy
        width: root.iconSize * root.fontScale          // A- / A+ in the layout editor size an icon button's icon too
        height: root.iconSize * root.fontScale
        source: root.icon
        sourceSize.width: root.iconSize * root.fontScale
        sourceSize.height: root.iconSize * root.fontScale
        smooth: true
        fillMode: Image.PreserveAspectFit
    }

    MultiEffect {
        anchors.fill: iconImg
        visible: root.icon !== ""
        source: iconImg
        colorization: 1.0
        colorizationColor: root.disabled
        ? Theme.textDim
        : (root.active ? Theme.textOnAccent : root.inactiveTextColor)
        brightness: 0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (event) => {
            if (event.button === Qt.MiddleButton)
                root.middleClicked()
                else
                    root.clicked()
        }
    }
}
