import QtQuick

// Layer effect used by ThemedText. It does not paint the layer texture at all: it paints the same text again
// with every character in its own colour taken along the gradient. That is ordinary text rendering, so it is
// as sharp as any other text on any display scale (no texture, no mask, nothing to blur or tint).
// Not used on its own.
Item {
    id: fx

    property var source: null          // the layer's texture provider; its sourceItem is the original Text
    property var grad: null            // { colors: [...], horizontal: bool }

    readonly property var src: fx.source ? fx.source.sourceItem : null
    width: fx.src ? fx.src.width : 0
    height: fx.src ? fx.src.height : 0

    function _hex(v) { const h = Math.max(0, Math.min(255, Math.round(v * 255))).toString(16); return h.length < 2 ? "0" + h : h }
    function _at(t) {
        const c = fx.grad.colors
        if (c.length === 1) return c[0]
            const x = Math.max(0, Math.min(1, t)) * (c.length - 1)
            const i = Math.min(c.length - 2, Math.floor(x))
            const f = x - i
            return Qt.rgba(c[i].r + (c[i + 1].r - c[i].r) * f, c[i].g + (c[i + 1].g - c[i].g) * f,
                           c[i].b + (c[i + 1].b - c[i].b) * f, 1)
    }
    function _esc(ch) { return ch === "&" ? "&amp;" : ch === "<" ? "&lt;" : ch === ">" ? "&gt;" : ch === "\n" ? "<br/>" : ch }

    // the text with each character wrapped in its own colour
    readonly property string html: {
        if (!fx.src || !fx.grad || !fx.grad.colors || fx.grad.colors.length === 0) return ""
            const s = fx.src.text
            if (s.length === 0) return ""
                const total = Math.max(1, fm.advanceWidth(s))
                let out = ""
                for (let k = 0; k < s.length; k++) {
                    const mid = (fm.advanceWidth(s.slice(0, k)) + fm.advanceWidth(s.slice(0, k + 1))) / 2
                    const c = fx._at(mid / total)
                    out += "<font color=\"#" + fx._hex(c.r) + fx._hex(c.g) + fx._hex(c.b) + "\">" + fx._esc(s[k]) + "</font>"
                }
                return out
    }

    FontMetrics { id: fm; font: fx.src ? fx.src.font : Qt.font({}) }

    Text {
        width: fx.width
        height: fx.height
        text: fx.html
        color: (fx.grad && fx.grad.colors && fx.grad.colors.length) ? fx.grad.colors[fx.grad.colors.length - 1] : "transparent"   // the elide dots
        textFormat: Text.StyledText
        opacity: fx.src ? fx.src.color.a : 1          // the text's own transparency (muted / dim text)
        font: fx.src ? fx.src.font : Qt.font({})
        wrapMode: fx.src ? fx.src.wrapMode : Text.NoWrap
        elide: fx.src ? fx.src.elide : Text.ElideNone
        horizontalAlignment: fx.src ? fx.src.horizontalAlignment : Text.AlignLeft
        verticalAlignment: fx.src ? fx.src.verticalAlignment : Text.AlignTop
        maximumLineCount: fx.src ? fx.src.maximumLineCount : 2147483647
        lineHeight: fx.src ? fx.src.lineHeight : 1
        lineHeightMode: fx.src ? fx.src.lineHeightMode : Text.ProportionalHeight
        leftPadding: fx.src ? fx.src.leftPadding : 0
        rightPadding: fx.src ? fx.src.rightPadding : 0
        topPadding: fx.src ? fx.src.topPadding : 0
        bottomPadding: fx.src ? fx.src.bottomPadding : 0
        fontSizeMode: fx.src ? fx.src.fontSizeMode : Text.FixedSize
        minimumPixelSize: fx.src ? fx.src.minimumPixelSize : 12
        renderType: fx.src ? fx.src.renderType : Text.QtRendering
    }
}
