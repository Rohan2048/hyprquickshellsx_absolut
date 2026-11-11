import QtQuick
import "../Theme"

// Battery line graph, shared by Settings > Battery and the Battery popup.
//   mode "level"   battery percentage (0..100)
//   mode "power"   power draw in watts (scales to the peak)
//   mode "energy"  energy used so far, in Wh, adding up as the window goes on
//   today: false = the last 24 h ending now;  true = this calendar day, midnight to midnight
// Charging periods get a green band. Holes in the data (shutdown, suspend, shell off) are bridged with a
// solid line in the highlight colour between the last sample before and the first after. Nothing is
// estimated for them: hovering a hole says "inactive", and for "energy" the line stays flat across it
// (no Wh is invented for time the shell was not logging). A hole that crosses the start of the window
// begins at the edge.
// `points` and `now` come from BatteryInfo.hist (points: { t, p, w, s }).
Item {
    id: ch

    property var points: []
    property real now: 0
    property string mode: "level"
    property bool today: false
    property bool compact: false          // smaller type and height, for the popup
    property bool interactive: true       // hover shows the exact value
    property var hover: null              // the sample (or interpolated gap point) under the pointer

    readonly property real span: 24 * 3600
    readonly property real gapS: 900      // a hole longer than this is bridged with an estimated line
    readonly property real t0: {
        if (!ch.today || ch.now <= 0) return ch.now - ch.span
            const d = new Date(ch.now * 1000)
            d.setHours(0, 0, 0, 0)
            return d.getTime() / 1000
    }
    // the samples inside the window, each with the value this graph draws.
    // g: true marks a sample that ends an inactive (bridged) stretch.
    readonly property var samples: {
        const src = ch.points || []
        const GAP = ch.gapS

        const out = []
        let wh = 0
        for (let i = 0; i < src.length; i++) {
            const p = src[i]
            if (p.t < ch.t0) continue
                const a = i > 0 ? src[i - 1] : null
                const gap = a !== null && p.t - a.t > GAP

                if (out.length === 0) {
                    if (gap) {
                        // the window starts inside a hole: begin the line at the window edge
                        const full = p.t - a.t
                        const u = (ch.t0 - a.t) / full
                        const ep = a.p + (p.p - a.p) * u
                        const ew = a.w + (p.w - a.w) * u
                        out.push({ t: ch.t0, v: ch.mode === "level" ? ep : (ch.mode === "power" ? ew : 0),
                            s: "u", p: Math.round(ep), w: ew, g: false })
                        wh = 0
                    }
                } else if (gap) {
                    // inactive: no Wh is added
                } else {
                    const dt = p.t - a.t
                    if (ch.mode === "energy" && dt > 0 && a.s === "d") wh += a.w * dt / 3600
                }
                out.push({ t: p.t, v: ch.mode === "level" ? p.p : (ch.mode === "power" ? p.w : wh),
                    s: p.s, p: p.p, w: p.w, g: gap })
        }
        return out
    }
    readonly property real peak: {
        let m = 0
        for (let i = 0; i < samples.length; i++) m = Math.max(m, samples[i].v)
            return m
    }
    readonly property real yMax: ch.mode === "level" ? 100
    : (ch.mode === "power" ? Math.max(5, Math.ceil(peak / 5) * 5)
    : Math.max(5, Math.ceil(peak / 5) * 5))
    readonly property string unit: ch.mode === "level" ? "%" : (ch.mode === "power" ? " W" : " Wh")
    readonly property int fs: ch.compact ? Theme.fontSizeXs - 1 : Theme.fontSizeXs
    readonly property color lineCol: Theme.accentActive

    // highlight for estimated stretches: dynamic colour 3
    readonly property color estCol: Theme.color7
    readonly property color gapLineCol: Qt.rgba(ch.estCol.r, ch.estCol.g, ch.estCol.b, 0.95)
    readonly property color gapAreaCol: Qt.rgba(ch.estCol.r, ch.estCol.g, ch.estCol.b, 0.14)

    readonly property color areaCol: Qt.rgba(Theme.accentActive.r, Theme.accentActive.g, Theme.accentActive.b, 0.18)
    readonly property color bandCol: Qt.rgba(0.25, 0.78, 0.45, 0.16)
    readonly property color gridCol: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.12)
    readonly property int leftPad: ch.compact ? 30 : 40

    implicitHeight: ch.compact ? 84 : 128

    function hoverText() {
        const p = ch.hover
        if (!p) return ""
            if (p.est === true)
                return Qt.formatDateTime(new Date(p.t * 1000), ch.compact ? "HH:mm" : "ddd HH:mm") + "  \u00B7  inactive"
                const est = ""
                if (ch.mode === "energy")
                    return Qt.formatDateTime(new Date(p.t * 1000), "HH:mm") + "  \u00B7  " + Number(p.v).toFixed(1) + " Wh used" + est
                    const st = ({ c: "charging", d: "on battery", f: "full", n: "not charging" })[p.s] ?? ""
                    return Qt.formatDateTime(new Date(p.t * 1000), ch.compact ? "HH:mm" : "ddd HH:mm") + "  \u00B7  " + p.p + "%  \u00B7  "
                    + Number(p.w).toFixed(1) + " W" + (st !== "" && !ch.compact ? "  \u00B7  " + st : "") + est
    }

    onSamplesChanged: { ch.hover = null; cv.requestPaint() }
    onYMaxChanged: cv.requestPaint()
    onNowChanged: cv.requestPaint()
    onHoverChanged: cv.requestPaint()
    onLineColChanged: cv.requestPaint()
    onEstColChanged: cv.requestPaint()
    Connections { target: Theme; function onIsDarkChanged() { cv.requestPaint() } }

    component Lbl: Text {
        color: Theme.foreground
        opacity: 0.6
        font.family: Theme.fontFamily
        font.pixelSize: ch.fs
    }

    Lbl { x: 0; y: 0; text: ch.mode === "level" ? "100%" : Math.round(ch.yMax) + ch.unit }
    Lbl { x: 0; y: cv.y + cv.height - height; text: "0" + ch.unit }
    Lbl {
        x: cv.x; y: ch.height - height
        text: ch.now > 0 ? Qt.formatDateTime(new Date(ch.t0 * 1000), ch.today ? "HH:mm" : "ddd HH:mm") : ""
    }
    Lbl {
        visible: !ch.compact
        x: cv.x + (cv.width - width) / 2; y: ch.height - height
        text: ch.now > 0 ? Qt.formatDateTime(new Date((ch.t0 + ch.span / 2) * 1000), ch.today ? "HH:mm" : "ddd HH:mm") : ""
    }
    Lbl {
        x: cv.x + cv.width - width; y: ch.height - height
        text: ch.today ? "00:00" : "now"
    }
    // value under the pointer
    Text {
        x: cv.x + cv.width - width; y: 0
        text: ch.hoverText()
        color: ch.hover && ch.hover.est === true ? ch.estCol : Theme.foreground
        font.family: Theme.fontFamily; font.pixelSize: ch.fs; font.bold: true
    }

    Canvas {
        id: cv
        x: ch.leftPad; y: ch.compact ? 11 : 14
        width: ch.width - ch.leftPad
        height: ch.height - y - (ch.compact ? 12 : 16)
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const w = width, h = height
            const pts = ch.samples

            ctx.lineWidth = 1
            ctx.strokeStyle = ch.gridCol
            for (let g = 0; g <= 4; g++) {
                const gy = Math.round(h * g / 4) + 0.5
                ctx.beginPath(); ctx.moveTo(0, gy); ctx.lineTo(w, gy); ctx.stroke()
            }
            if (pts.length < 2 || ch.now <= 0) return

                const X = (t) => (t - ch.t0) / ch.span * w
                const Y = (v) => h - Math.max(0, Math.min(1, v / ch.yMax)) * h

                // charging bands (measured stretches only)
                ctx.fillStyle = ch.bandCol
                for (let i = 0; i < pts.length - 1; i++) {
                    const a = pts[i], b = pts[i + 1]
                    if (a.s !== "c" || b.g === true) continue
                        ctx.fillRect(X(a.t), 0, Math.max(1, X(b.t) - X(a.t)), h)
                }

                // walk the samples in groups of segments that are all measured or all estimated
                ctx.lineJoin = "round"
                const lw = ch.compact ? 1.5 : 2
                let i = 0
                while (i < pts.length - 1) {
                    const est = pts[i + 1].g === true
                    let end = i + 1
                    while (end < pts.length - 1 && (pts[end + 1].g === true) === est) end++

                        // area under the group
                        ctx.beginPath()
                        ctx.moveTo(X(pts[i].t), Y(pts[i].v))
                        for (let k = i + 1; k <= end; k++) ctx.lineTo(X(pts[k].t), Y(pts[k].v))
                            ctx.lineTo(X(pts[end].t), h)
                            ctx.lineTo(X(pts[i].t), h)
                            ctx.closePath()
                            ctx.fillStyle = est ? ch.gapAreaCol : ch.areaCol
                            ctx.fill()

                            // the line itself (solid; estimated stretches in colour 3)
                            ctx.lineWidth = est ? lw + 0.5 : lw
                            ctx.strokeStyle = est ? ch.gapLineCol : ch.lineCol
                            ctx.beginPath()
                            ctx.moveTo(X(pts[i].t), Y(pts[i].v))
                            for (let k = i + 1; k <= end; k++) ctx.lineTo(X(pts[k].t), Y(pts[k].v))
                                ctx.stroke()

                                i = end
                }

                if (ch.hover) {
                    const p = ch.hover
                    const col = p.est === true ? ch.estCol : ch.lineCol
                    ctx.strokeStyle = col
                    ctx.lineWidth = 1
                    ctx.beginPath(); ctx.moveTo(X(p.t) + 0.5, 0); ctx.lineTo(X(p.t) + 0.5, h); ctx.stroke()
                    ctx.fillStyle = col
                    ctx.beginPath(); ctx.arc(X(p.t), Y(p.v), 3, 0, Math.PI * 2); ctx.fill()
                }
        }

        MouseArea {
            anchors.fill: parent
            enabled: ch.interactive
            hoverEnabled: true
            onExited: ch.hover = null
            onPositionChanged: (m) => {
                const t = ch.t0 + m.x / Math.max(1, cv.width) * ch.span
                const s = ch.samples
                let hv = null
                for (let i = 0; i < s.length - 1; i++) {
                    const a = s[i], b = s[i + 1]
                    if (t < a.t || t > b.t) continue
                        if (b.g === true) {
                            // inside an estimated stretch: show the interpolated value
                            const u = (t - a.t) / Math.max(1, b.t - a.t)
                            hv = { t: t, v: a.v + (b.v - a.v) * u, p: Math.round(a.p + (b.p - a.p) * u),
                                w: a.w + (b.w - a.w) * u, s: "", est: true }
                        } else {
                            hv = (t - a.t) <= (b.t - t) ? a : b
                        }
                        break
                }
                ch.hover = hv
            }
        }
    }
}
