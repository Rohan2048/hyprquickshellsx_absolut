import QtQuick as QQ
import "../Theme"

// A Text that draws the theme's GRADIENT text colours for real (every character gets its own colour along
// the gradient, drawn as ordinary text, so it stays sharp at any display scale) (Settings > Theme > Text colour / Date colour).
//
// It is an ordinary Text in every way (same properties, signals, enums, Layout.*). Only when the active
// custom theme has a gradient, and this text is coloured with the theme's text colour, is it drawn with
// the gradient instead of a flat colour:
//   - text coloured Theme.foreground / textMuted / textDim (same RGB, any alpha)  -> text gradient
//   - text coloured like the bar's date (colour 3, lighter in dark mode)           -> date colour/gradient
// Any other colour (errors, accents, text on active buttons ...) is left alone. The text's own alpha is kept.
//
// Files that `import "../Widgets"` after `import QtQuick` get this automatically under the name `Text`
// (see Widgets/Text.qml). Files inside Widgets/ use `ThemedText` where they want it.
QQ.Text {
    id: root

    function _near(a, b) {
        return Math.abs(a.r - b.r) < 0.004 && Math.abs(a.g - b.g) < 0.004 && Math.abs(a.b - b.b) < 0.004
    }

    // the date colour the theme asks for: a gradient, or a solid colour as a flat two-stop gradient
    function _dateGrad() {
        const d = Theme.activeTheme.date
        const dark = Theme.effectiveDark
        const adapt = Theme.activeTheme.adapt !== false
        if (d.type === "gradient") return Theme.resolveTextGradient(d, dark, adapt)
            const c = Theme.colorOf(d.color, dark, adapt)
            return { colors: [c, c], horizontal: true }
    }

    // the gradient this text is drawn with, or null for plain text
    readonly property var _g: {
        const c = root.color
        const tg = Theme.textGradient
        if (tg && root._near(c, Theme.foreground)) return tg
            if (Theme.customActive && Theme.activeTheme.date && Theme.activeTheme.date.auto === false
                && root._near(c, Theme.isDark ? Qt.lighter(Theme.color3, 1.5) : Qt.darker(Theme.color3, 2.8)))
                return root._dateGrad()
                return null
    }

    // Rich / styled text brings its own colours: leave it alone. Otherwise the effect below repaints the text
    // character by character in gradient colours; the layer texture itself is never shown, so keep it tiny.
    readonly property bool _plain: root.textFormat === QQ.Text.PlainText
    || (root.textFormat === QQ.Text.AutoText && !/<\/?[a-zA-Z]/.test(root.text))
    layer.enabled: root._g !== null && root._plain
    // The tiny texture is only for OUR gradient layer. A Text that sets its own layer.effect (an entrance
    // blur, say) replaces it, and must get a normal full-size texture: with the 1x1 one left behind, that
    // effect stretched one pixel across the whole text item, which showed up as a box (Wi-Fi / Bluetooth
    // header titles during the entrance animation).
    layer.textureSize: root.layer.effect === gradFxComp ? Qt.size(1, 1) : Qt.size(0, 0)
    layer.effect: gradFxComp
    QQ.Component { id: gradFxComp; GradFx { grad: root._g } }
}
