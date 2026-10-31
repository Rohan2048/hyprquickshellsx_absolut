import QtQuick
import QtQuick.Effects
import "../Theme"

// Text that can be drawn with the active theme's text GRADIENT. With no gradient (any
// other theme, or a solid text colour) it is an ordinary Text in `fallbackColor`.
// Everything else in the shell is still plain Text coloured with the gradient's average;
// use this item where the gradient should actually show (titles, clock, ...).
Item {
    id: root

    property alias text: label.text
    property alias font: label.font
    property alias wrapMode: label.wrapMode
    property alias elide: label.elide
    property alias horizontalAlignment: label.horizontalAlignment
    property var textGrad: Theme.textGradient
    property color fallbackColor: Theme.foreground

    readonly property bool grad: root.textGrad !== null && root.textGrad !== undefined
    && root.textGrad.colors !== undefined && root.textGrad.colors.length >= 2

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight

    function _n() { return root.grad ? root.textGrad.colors.length : 0 }
    function _c(i) { const n = root._n(); return n === 0 ? "transparent" : root.textGrad.colors[Math.min(i, n - 1)] }
    function _p(i) { const n = root._n(); return n <= 1 ? (i === 0 ? 0 : 1) : (i < n ? i / (n - 1) : 1) }

    Text {
        id: label
        anchors.fill: parent
        visible: !root.grad
        color: root.fallbackColor
    }

    // glyph shape = mask
    Item {
        id: shape
        anchors.fill: parent
        visible: false
        layer.enabled: root.grad
        Text {
            anchors.fill: parent
            color: "black"
            text: label.text
            font: label.font
            wrapMode: label.wrapMode
            elide: label.elide
            horizontalAlignment: label.horizontalAlignment
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.grad
        layer.enabled: root.grad
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: shape
            maskThresholdMin: 0.3
            maskSpreadAtMin: 0.7
        }
        gradient: Gradient {
            orientation: (root.grad && root.textGrad.horizontal) ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: root._p(0); color: root._c(0) }
            GradientStop { position: root._p(1); color: root._c(1) }
            GradientStop { position: root._p(2); color: root._c(2) }
            GradientStop { position: root._p(3); color: root._c(3) }
            GradientStop { position: root._p(4); color: root._c(4) }
            GradientStop { position: root._p(5); color: root._c(5) }
        }
    }
}
