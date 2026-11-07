import QtQuick
import QtQuick.Shapes
import "../Theme"
import "../Services"

// "Anime streaks": a border effect in the spirit of NFS Unbound's hand-animated look, drawn on top of the
// normal border by Widgets/PanelBorder.qml (only while the effect is on).
//   - it is animated "on twos or threes": everything is redrawn only when the frame number changes
//     (Settings > Theme > Border > Frame rate, 5-15 fps), never in between, so it steps instead of gliding
//   - speed streaks: short lines that run round the border in jumps, some on the line, some a little off it,
//     one now and then dropping out for a frame
//   - some streaks go wavy and ride a little outside the border (still visible, just beyond the line)
//   - artefacts: tiny paint specks beside the border, an occasional small cross (x) or circle (o) drawn near
//     it, and now and then a ghost copy of the outline that is slightly out of register, like a misprinted cel
// Pure vector drawing from a seeded random of the frame number (no textures, no timers of its own). The
// frame number comes from the shared Services/BorderClock, so every panel is on the same frame.
Item {
    id: a

    property real tl: 12
    property real tr: 12
    property real bl: 12
    property real br: 12
    property real t: 1                 // border thickness
    property int step: 0               // frame number
    // free space outside each side of the panel in its own units (PanelBorder measures it, window edges and
    // clipping parents included); big by default = unlimited
    property real roomL: 60
    property real roomT: 60
    property real roomR: 60
    property real roomB: 60
    // how far outside we may draw at a point whose outward normal is (nx, ny); with no room the effect sits
    // just inside the border instead
    function reachAt(nx, ny) {
        const ax = Math.abs(nx), ay = Math.abs(ny)
        const sum = ax + ay
        if (sum < 0.0001) return 0
            const rx = nx > 0 ? a.roomR : a.roomL
            const ry = ny > 0 ? a.roomB : a.roomT
            return Math.max(0, (ax * rx + ay * ry) / sum - 1)
    }
    // `out`: how far outside we would like to be, `size`: how far the shape reaches from its centre.
    // Returns the offset along the outward normal (negative = inside the panel).
    function lane(out, size, nx, ny) {
        const reach = a.reachAt(nx, ny)
        if (reach >= out + size) return out
            if (reach >= size + 2) return reach - size
                return -(Math.min(out, 8) + size)
    }

    // each panel gets its own sequence
    readonly property real salt: Math.round(a.width * 13 + a.height * 7)
    function rnd(n) {
        const x = Math.sin(n * 12.9898 + a.salt * 0.0371 + 78.233) * 43758.5453
        return x - Math.floor(x)
    }

    // Light / dark theme: a dark theme gets the lighter version of the colours, a light theme the darker
    // one, so the streaks, specks and x / o marks stay readable on either background.
    readonly property bool dark: Theme.effectiveDark
    function tone(c, k) { return a.dark ? Qt.lighter(c, k) : Qt.darker(c, k) }
    readonly property color c1: a.tone(BorderSettings.colorType === "gradient" ? BorderSettings.gradientColors[0] : BorderSettings.baseColor, 1.25)
    readonly property color c2: BorderSettings.colorType === "gradient"
    ? a.tone(BorderSettings.gradientColors[BorderSettings.gradientColors.length - 1], 1.25)
    : a.tone(BorderSettings.baseColor, 1.7)

    // ---- the border's centre line, as pieces we can walk along (clockwise from the top) ----
    readonly property var segs: {
        const w = a.width, h = a.height, t = a.t
        if (w < 12 || h < 12) return []
            const x0 = t / 2, y0 = t / 2, x1 = w - t / 2, y1 = h - t / 2
            const lim = Math.min(x1 - x0, y1 - y0) / 2
            const rr = function (r) { return Math.max(0, Math.min(r - t / 2, lim)) }
            const rtl = rr(a.tl), rtr = rr(a.tr), rbr = rr(a.br), rbl = rr(a.bl)
            const q = Math.PI / 2
            const L = function (n) { return Math.max(0, n) }
            return [
                { k: 0, len: L((x1 - rtr) - (x0 + rtl)), x: x0 + rtl, y: y0, dx: 1, dy: 0, nx: 0, ny: -1 },           // top
                { k: 1, len: q * rtr, cx: x1 - rtr, cy: y0 + rtr, r: rtr, a0: -q },                                    // top right
                { k: 0, len: L((y1 - rbr) - (y0 + rtr)), x: x1, y: y0 + rtr, dx: 0, dy: 1, nx: 1, ny: 0 },            // right
                { k: 1, len: q * rbr, cx: x1 - rbr, cy: y1 - rbr, r: rbr, a0: 0 },                                     // bottom right
                { k: 0, len: L((x1 - rbr) - (x0 + rbl)), x: x1 - rbr, y: y1, dx: -1, dy: 0, nx: 0, ny: 1 },           // bottom
                { k: 1, len: q * rbl, cx: x0 + rbl, cy: y1 - rbl, r: rbl, a0: q },                                     // bottom left
                { k: 0, len: L((y1 - rbl) - (y0 + rtl)), x: x0, y: y1 - rbl, dx: 0, dy: -1, nx: -1, ny: 0 },          // left
                { k: 1, len: q * rtl, cx: x0 + rtl, cy: y0 + rtl, r: rtl, a0: Math.PI }                                // top left
            ]
    }
    readonly property real total: {
        let s = 0
        for (let i = 0; i < a.segs.length; i++) s += a.segs[i].len
            return s
    }
    // point, and the outward normal, at distance `s` along the border
    function pointAt(s) {
        const segs = a.segs
        let d = ((s % a.total) + a.total) % a.total
        for (let i = 0; i < segs.length; i++) {
            const g = segs[i]
            if (d <= g.len || i === segs.length - 1) {
                const u = g.len > 0 ? Math.min(1, d / g.len) : 0
                if (g.k === 0) return { x: g.x + g.dx * g.len * u, y: g.y + g.dy * g.len * u, nx: g.nx, ny: g.ny }
                const ang = g.a0 + u * Math.PI / 2
                return { x: g.cx + g.r * Math.cos(ang), y: g.cy + g.r * Math.sin(ang), nx: Math.cos(ang), ny: Math.sin(ang) }
            }
            d -= g.len
        }
        return { x: 0, y: 0, nx: 0, ny: -1 }
    }

    // ---- this frame ----
    // speed streaks: two paths (two colours / two weights)
    readonly property var streaks: {
        const out = { a: "", b: "" }
        const total = a.total
        if (total <= 0) return out
            const n = BorderSettings.animeStreaks
            const f = a.step
            for (let i = 0; i < n; i++) {
                if (a.rnd(f * 7.3 + i * 91.7) < 0.2) continue                      // dropped out for this frame
                    const dir = a.rnd(i * 5.1) < 0.25 ? -1 : 1                          // most run the same way
                    const v = 0.045 + a.rnd(i * 3.7) * 0.07                             // share of the border per frame
                    const head = (a.rnd(i * 17.3) + dir * f * v) * total
                    const len = total * (0.05 + a.rnd(i * 2.9) * 0.1) * (0.7 + a.rnd(f * 1.9 + i) * 0.6)
                    // now and then a streak turns wavy and rides outside the border, wave and all
                    const wavy = a.rnd(f * 3.9 + i * 21.7) < 0.35
                    const amp = wavy ? 1.5 + a.rnd(i * 6.3 + f * 0.7) * 2.5 : 0
                    const lam = 14 + a.rnd(i * 8.9) * 14
                    const ph = a.rnd(f * 1.3 + i * 4.7) * 6.2832
                    const ext = a.rnd(f * 4.1 + i * 13.3) - 0.35
                    const wantOut = a.t + amp + 1 + a.rnd(f * 2.2 + i * 9.1) * 2                        // wavy: outside the line, whole wave
                    const pts = Math.max(2, Math.round(len / (wavy ? 3 : 6)))
                    let d = ""
                    for (let k = 0; k <= pts; k++) {
                        const along = len * (k / pts)
                        const p = a.pointAt(head - dir * along)
                        const base = wavy ? a.lane(wantOut, amp, p.nx, p.ny)                             // (inside the line if there is no room on that side)
                        : Math.min(ext * a.t * 3, a.reachAt(p.nx, p.ny))               // on the line, inside it, or just off it
                        const o = base + (wavy ? amp * Math.sin(6.2832 * along / lam + ph) : 0)
                        d += (k === 0 ? "M " : " L ") + (p.x + p.nx * o).toFixed(1) + " " + (p.y + p.ny * o).toFixed(1)
                    }
                    if (i % 2 === 0) out.a += d + " "
                        else out.b += d + " "
            }
            return out
    }
    // paint specks beside the border
    readonly property string specks: {
        const total = a.total
        if (total <= 0) return ""
            const n = Math.round(BorderSettings.animeGlitch * 0.8)
            const f = a.step
            let d = ""
            for (let i = 0; i < n; i++) {
                if (a.rnd(f * 5.9 + i * 3.3) < 0.35) continue
                    const p = a.pointAt(a.rnd(f * 2.7 + i * 19.1) * total)
                    const sz = 2 + Math.floor(a.rnd(i * 11.7 + f * 0.3) * 3)
                    const out = a.lane(a.t * 0.5 + 1 + a.rnd(f * 8.3 + i * 7.7) * (3 + a.t * 2), sz / 2, p.nx, p.ny)
                    d += "M " + (p.x + p.nx * out - sz / 2).toFixed(1) + " " + (p.y + p.ny * out - sz / 2).toFixed(1)
                    + " h " + sz + " v " + sz + " h " + (-sz) + " Z "
            }
            return d
    }
    // an occasional cross (x) or circle (o) drawn near the border; each one stays for two frames
    readonly property string marks: {
        const total = a.total
        const g = BorderSettings.animeGlitch
        if (total <= 0 || g <= 0) return ""
            const f = Math.floor(a.step / 2)
            if (a.rnd(f * 4.7 + 3) > 0.15 + g * 0.05) return ""
                const n = 1 + Math.floor(a.rnd(f * 8.1 + 7) * 2)
                let d = ""
                for (let i = 0; i < n; i++) {
                    const p = a.pointAt(a.rnd(f * 2.3 + i * 31.9) * total)
                    const z = 2.5 + a.rnd(f * 3.1 + i * 12.7) * 2.5
                    const out = a.lane(a.t + 5 + a.rnd(f * 6.7 + i * 5.3) * 6, z, p.nx, p.ny)
                    const cx = p.x + p.nx * out
                    const cy = p.y + p.ny * out
                    if (a.rnd(f * 9.9 + i * 2.1) < 0.5)
                        d += "M " + (cx - z).toFixed(1) + " " + (cy - z).toFixed(1) + " L " + (cx + z).toFixed(1) + " " + (cy + z).toFixed(1)
                        + " M " + (cx - z).toFixed(1) + " " + (cy + z).toFixed(1) + " L " + (cx + z).toFixed(1) + " " + (cy - z).toFixed(1) + " "
                        else
                            d += "M " + (cx + z).toFixed(1) + " " + cy.toFixed(1)
                            + " A " + z.toFixed(1) + " " + z.toFixed(1) + " 0 1 0 " + (cx - z).toFixed(1) + " " + cy.toFixed(1)
                            + " A " + z.toFixed(1) + " " + z.toFixed(1) + " 0 1 0 " + (cx + z).toFixed(1) + " " + cy.toFixed(1) + " "
                }
                return d
    }
    // a ghost copy of the outline, out of register for a frame or two
    readonly property bool ghostOn: BorderSettings.animeGlitch > 0 && a.rnd(a.step * 6.1 + 99) < 0.1 + BorderSettings.animeGlitch * 0.03
    readonly property real ghostX: (a.rnd(a.step * 9.7 + 5) - 0.5) * 2 * (1.5 + BorderSettings.animeGlitch * 0.25)
    readonly property real ghostY: (a.rnd(a.step * 3.3 + 17) - 0.5) * 1.4 * (1.5 + BorderSettings.animeGlitch * 0.25)

    Rectangle {
        visible: a.ghostOn
        x: a.ghostX
        y: a.ghostY
        width: a.width
        height: a.height
        color: "transparent"
        border.width: Math.max(1, a.t * 0.8)
        border.color: a.c2
        opacity: 0.5
        topLeftRadius: a.tl
        topRightRadius: a.tr
        bottomLeftRadius: a.bl
        bottomRightRadius: a.br
    }

    Shape {
        anchors.fill: parent
        asynchronous: false

        ShapePath {
            strokeColor: a.c1
            strokeWidth: Math.max(1, a.t * 1.4)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathSvg { path: a.streaks.a === "" ? "M 0 0" : a.streaks.a }
        }
        ShapePath {
            strokeColor: a.c2
            strokeWidth: Math.max(1, a.t * 0.8)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathSvg { path: a.streaks.b === "" ? "M 0 0" : a.streaks.b }
        }
        ShapePath {
            strokeWidth: -1
            fillColor: a.c2
            PathSvg { path: a.specks === "" ? "M 0 0" : a.specks }
        }
        ShapePath {
            strokeColor: a.c1
            strokeWidth: Math.max(1, a.t * 0.9)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathSvg { path: a.marks === "" ? "M 0 0" : a.marks }
        }
    }
}
