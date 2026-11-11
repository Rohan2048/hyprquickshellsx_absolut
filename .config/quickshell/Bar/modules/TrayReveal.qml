import QtQuick
import Qt5Compat.GraphicalEffects
import "../../Theme"
import "../../Services"

// Appear/disappear wrapper for bar buttons that only exist while "active".
// Width (horizontal bar) or height (vertical bar) grows/collapses
// (220ms OutQuint), opacity fades with the slide-blur timing, and a short
// DirectionalBlur pulse along the bar's axis plays whenever `active` flips
// (or when pulse() is called).
//
// The item and its blur layer stay alive at all times (collapsed = zero size,
// clipped), so a reveal never has to create/destroy scene-graph nodes or
// textures mid-animation.
Item {
    id: root

    property bool active: false
    readonly property bool shown: active
    default property alias content: holder.data

        property var cfg: BarSettings
        readonly property bool vertical: cfg.vertical

        // Wrapped content is sized by its own implicitWidth/Height.
        readonly property real contentWidth: holder.childrenRect.width
        readonly property real contentHeight: holder.childrenRect.height

        implicitWidth: vertical ? contentWidth : (shown ? contentWidth : 0)
        implicitHeight: vertical ? (shown ? contentHeight : 0) : contentHeight
        width: implicitWidth
        height: implicitHeight
        clip: true
        opacity: shown ? 1 : 0

        // Don't let a click land on the button while it is collapsing away.
        enabled: active

        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutQuint } }
        Behavior on opacity {
            NumberAnimation {
                duration: Animations.slideBlurDuration
                easing.type: root.shown ? Animations.slideBlurEasingOut : Animations.slideBlurEasingIn
            }
        }

        property real blurLength: 0
        layer.enabled: true
        layer.effect: DirectionalBlur {
            angle: root.vertical ? Animations.slideBlurVerticalAngle : Animations.slideBlurHorizontalAngle
            length: root.blurLength
            samples: Animations.slideBlurSamples
        }

        Item { id: holder }

        function pulse() { blurPulse.restart() }

        onShownChanged: blurPulse.restart()

        SequentialAnimation {
            id: blurPulse
            NumberAnimation { target: root; property: "blurLength"; to: Animations.slideBlurHorizontalLength * 1.3; duration: Animations.slideBlurDuration * 0.35; easing.type: Animations.slideBlurEasingIn }
            NumberAnimation { target: root; property: "blurLength"; to: 0; duration: Animations.slideBlurDuration * 0.35; easing.type: Animations.slideBlurEasingOut }
        }
}
