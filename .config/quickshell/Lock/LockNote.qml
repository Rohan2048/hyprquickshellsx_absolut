import QtQuick
import "../Services"
import "../Theme"

// One note of a lock screen preset: a line of text you wrote, or your handwritten signature
// (Settings > Lock screen > Notes). `spec` is a layout note (see Services/LockPresets.qml).
//
// The item is sized to what it shows, already stretched by spec.sx / spec.sy:
//   message     the text, every character in its own colour along the gradient (crisp, no masks)
//   signature   the strokes, drawn on a canvas of 300 x 120 x (sx, sy)
// baseWidth / baseHeight are the unstretched size (used by the editor's stretch handles).
Item {
    id: root

    property var spec: ({})

    readonly property bool sig: root.spec.kind === "signature"
    readonly property real sxv: root.spec.sx || 1
    readonly property real syv: root.spec.sy || 1
    readonly property real baseWidth: root.sig ? 300 : Math.max(8, msg.implicitWidth)
    readonly property real baseHeight: root.sig ? 120 : Math.max(8, msg.implicitHeight)
    width: root.baseWidth * root.sxv
    height: root.baseHeight * root.syv

    readonly property var grad: LockPresets.specGrad(root.spec.color)
    readonly property color solid: LockPresets.specColor(root.spec.color)

    // ---- message ----
    FontMetrics { id: fm; font: msg.font }
    function _hex(v) { const h = Math.max(0, Math.min(255, Math.round(v * 255))).toString(16); return h.length < 2 ? "0" + h : h }
    function _at(t) {
        const c = root.grad.colors
        if (c.length === 1) return c[0]
            const x = Math.max(0, Math.min(1, t)) * (c.length - 1)
            const i = Math.min(c.length - 2, Math.floor(x))
            const f = x - i
            return Qt.rgba(c[i].r + (c[i + 1].r - c[i].r) * f, c[i].g + (c[i + 1].g - c[i].g) * f, c[i].b + (c[i + 1].b - c[i].b) * f, 1)
    }
    function _esc(ch) { return ch === "&" ? "&amp;" : ch === "<" ? "&lt;" : ch === ">" ? "&gt;" : ch === "\n" ? "<br/>" : ch }
    // the text with each character wrapped in its own gradient colour (plain text when there is no gradient)
    readonly property string html: {
        const s = root.spec.text || ""
        if (!root.grad || s.length === 0) return ""
            const total = Math.max(1, fm.advanceWidth(s))
            let out = ""
            for (let k = 0; k < s.length; k++) {
                const mid = (fm.advanceWidth(s.slice(0, k)) + fm.advanceWidth(s.slice(0, k + 1))) / 2
                const c = root._at(mid / total)
                out += "<font color=\"#" + root._hex(c.r) + root._hex(c.g) + root._hex(c.b) + "\">" + root._esc(s[k]) + "</font>"
            }
            return out
    }
    Text {
        id: msg
        visible: !root.sig
        text: root.grad ? root.html : (root.spec.text || "")
        textFormat: root.grad ? Text.StyledText : Text.PlainText
        color: root.solid
        font.family: Theme.fontFamily
        font.pixelSize: root.spec.size || 40
        font.bold: true
        transform: Scale { xScale: root.sxv; yScale: root.syv }
    }

    // ---- signature ----
    Canvas {
        id: cv
        visible: root.sig
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: root; function onSpecChanged() { cv.requestPaint() } }
        Connections { target: Theme; function onEffectiveDarkChanged() { cv.requestPaint() } }
        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const st = root.spec.strokes || []
            if (!root.sig || st.length === 0) return
                const w = width, h = height
                const g = root.grad
                if (g) {
                    const lg = g.horizontal ? ctx.createLinearGradient(0, 0, w, 0) : ctx.createLinearGradient(0, 0, 0, h)
                    for (let i = 0; i < g.colors.length; i++) lg.addColorStop(g.colors.length === 1 ? 0 : i / (g.colors.length - 1), g.colors[i])
                        ctx.strokeStyle = lg
                        ctx.fillStyle = lg
                } else {
                    ctx.strokeStyle = root.solid
                    ctx.fillStyle = root.solid
                }
                const pen = (root.spec.pen || 3) * Math.min(root.sxv, root.syv)
                ctx.lineWidth = pen
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                for (let s = 0; s < st.length; s++) {
                    const p = st[s]
                    if (p.length < 4) {                                       // a dot
                        ctx.beginPath(); ctx.arc(p[0] * w, p[1] * h, pen / 2, 0, Math.PI * 2); ctx.fill()
                        continue
                    }
                    ctx.beginPath()
                    ctx.moveTo(p[0] * w, p[1] * h)
                    for (let i = 2; i + 3 < p.length; i += 2)                  // smooth through the midpoints
                        ctx.quadraticCurveTo(p[i] * w, p[i + 1] * h, (p[i] + p[i + 2]) / 2 * w, (p[i + 1] + p[i + 3]) / 2 * h)
                        ctx.lineTo(p[p.length - 2] * w, p[p.length - 1] * h)
                        ctx.stroke()
                }
        }
    }
}
