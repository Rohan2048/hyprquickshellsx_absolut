//Glassbutton.qml
import QtQuick
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
    readonly property bool hovered: mouse.containsMouse
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

    implicitHeight: 30 * root._st.h
    implicitWidth: root.icon !== "" ? 30 * root._st.w : (label.implicitWidth + 24) * root._st.w

    ThemedText {
        id: label
        visible: root.icon === ""
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root._st.dx
        anchors.verticalCenterOffset: root._st.dy
        color: root.disabled
        ? Theme.textDim
        : (root.active ? Theme.textOnAccent : root.inactiveTextColor)
        font.family: Theme.fontFamily
        font.pixelSize: root.fontSize
        font.bold: true
    }

    Image {
        id: iconImg
        visible: false
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: root._st.dx
        anchors.verticalCenterOffset: root._st.dy
        width: root.iconSize
        height: root.iconSize
        source: root.icon
        sourceSize.width: root.iconSize
        sourceSize.height: root.iconSize
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
