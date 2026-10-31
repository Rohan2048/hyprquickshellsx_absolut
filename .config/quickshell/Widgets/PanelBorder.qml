import QtQuick
import QtQuick.Shapes
import "../Theme"
import "../Services"

// The border of one panel (GlassPanel puts one on every panel). All of it comes from BorderSettings:
//   off             nothing is drawn
//   plain           one solid colour, no effect: an ordinary Rectangle border (cheapest, crispest)
//   anime           on top of either of the above: stepped (5-15 fps) speed streaks, line jitter and glitch
//                   artefacts, inspired by NFS Unbound (Widgets/BorderAnime.qml)
//   gradient/effect a ring (outer rounded rectangle minus inner one) filled with a conical gradient; the
//                   gradient's start angle turns for the rotation effects, the whole ring's opacity breathes
//                   for the pulse. Pure vector drawing: no textures, no masks, no blur.
// The effects run on Services/BorderClock (one shared, rate-capped timer) and only while this border is
// really on screen: window mapped, and no parent hidden or faded out. A window that stays mapped but
// transparent between uses (Music / Font / Settings) therefore costs nothing.
// tl / tr / bl / br are the panel's corner radii (a popup merged into the bar has two square corners).
Item {
    id: b

    property real tl: 12
    property real tr: 12
    property real bl: 12
    property real br: 12
    property bool shown: true             // false = draw nothing (a bare / transparent bar)
    // false = no anime streaks on this border (the bar sets it while an autohide bar is hidden: it is off screen
    // but its transparent window strip is not, and nothing should be drawn or animated for a hidden bar)
    property bool animeAllowed: true
    readonly property bool animeOn: BorderSettings.anime && b.animeAllowed

    readonly property real t: BorderSettings.thickness
    readonly property bool on: BorderSettings.enabled
    readonly property bool plain: BorderSettings.colorType !== "gradient" && !BorderSettings.rotate

    anchors.fill: parent
    visible: b.on && b.shown

    // Is this border visible to the user right now? Reads the window and every ancestor's visible /
    // opacity / scale, so the binding re-evaluates the moment any of them changes (a panel that is fading
    // out stops animating once it is practically gone).
    readonly property bool onScreen: {
        const w = b.Window.window
        if (!w || !w.visible || b.width < 1 || b.height < 1) return false
            let p = b.parent
            while (p) {
                if (!p.visible || p.opacity < 0.02 || p.scale < 0.02) return false
                    p = p.parent
            }
            return true
    }
    // an effect is on AND somebody can see it
    readonly property bool live: b.on && b.shown && (BorderSettings.rotate || BorderSettings.pulse || b.animeOn) && b.onScreen

    // ---- anime: the frame number (changes only 5-15 times a second) and the line jitter that goes with it ----
    readonly property int animeStep: Math.floor(BorderClock.t / (1000 / BorderSettings.animeFps))
    function _r(n) {
        const x = Math.sin(n * 12.9898 + (b.width * 13 + b.height * 7) * 0.0371 + 78.233) * 43758.5453
        return x - Math.floor(x)
    }
    // How much room there is outside each side of this panel, in the panel's OWN units (so it already accounts
    // for a scaled popup or window): the window edge and every clipping parent cut drawing off. The anime effect
    // rides outside the border where that room exists. Measured once per frame, only while the effect runs.
    property real roomL: 0
    property real roomT: 0
    property real roomR: 0
    property real roomB: 0
    function _measure() {
        const w = b.Window.window
        if (b.width < 1 || b.height < 1) return
            let l = 1e9, t = 1e9, r = 1e9, bt = 1e9
            // `item` = null is the window; every distance is divided by the scale between the panel and that item
            const take = function (item, iw, ih) {
                const p0 = b.mapToItem(item, 0, 0)
                const p1 = b.mapToItem(item, b.width, b.height)
                let kx = (p1.x - p0.x) / b.width
                let ky = (p1.y - p0.y) / b.height
                if (Math.abs(kx) < 0.01) kx = 1
                    if (Math.abs(ky) < 0.01) ky = 1
                        l = Math.min(l, p0.x / kx)
                        t = Math.min(t, p0.y / ky)
                        r = Math.min(r, (iw - p1.x) / kx)
                        bt = Math.min(bt, (ih - p1.y) / ky)
            }
            if (w) take(null, w.width, w.height)
                let it = b.parent
                while (it) {
                    if (it.clip === true) take(it, it.width, it.height)
                        it = it.parent
                }
                const c = function (v) { return Math.max(0, Math.min(v, 60)) }
                b.roomL = c(l); b.roomT = c(t); b.roomR = c(r); b.roomB = c(bt)
    }
    onAnimeStepChanged: { if (b.animeOn && b.live) b._measure() }

    readonly property bool jitter: b.animeOn && b.live
    readonly property real jx: b.jitter ? (b._r(b.animeStep * 3.1) - 0.5) * 1.6 : 0
    readonly property real jy: b.jitter ? (b._r(b.animeStep * 5.3 + 41) - 0.5) * 1.6 : 0

    // count ourselves in/out of the shared clock
    property bool _counted: false
    function _syncUse() {
        if (b.live === b._counted) return
            b._counted = b.live
            BorderClock.users += b.live ? 1 : -1
    }
    onLiveChanged: { b._syncUse(); if (b.live && b.animeOn) b._measure() }
    Component.onCompleted: { b._syncUse(); if (b.animeOn) b._measure() }
    Component.onDestruction: { if (b._counted) BorderClock.users -= 1 }

    // ---- pulse: 1 -> 0.15 -> 1 every pulseMs, a cosine of the shared clock ----
    Binding {
        target: b
        property: "opacity"
        when: b.live && BorderSettings.pulse
        value: 0.575 + 0.425 * Math.cos(2 * Math.PI * ((BorderClock.t % BorderSettings.pulseMs) / BorderSettings.pulseMs))
    }

    // the outline itself (it shifts a pixel or so per frame while the anime effect is on, like a redrawn line)
    Item {
        id: ring
        width: b.width
        height: b.height
        x: b.jx
        y: b.jy

        // ---- plain ----
        Loader {
            anchors.fill: parent
            active: b.on && b.plain
            sourceComponent: Rectangle {
                color: "transparent"
                border.width: b.t
                border.color: BorderSettings.baseColor
                topLeftRadius: b.tl
                topRightRadius: b.tr
                bottomLeftRadius: b.bl
                bottomRightRadius: b.br
            }
        }

        // ---- gradient / rotating ----
        Loader {
            anchors.fill: parent
            active: b.on && !b.plain
            sourceComponent: Shape {
                id: shape
                preferredRendererType: Shape.CurveRenderer
                asynchronous: true           // the path is built off the main thread: no hitch when a popup opens

                // the conical gradient's start angle (degrees); the rotation effect turns it. Only follows the
                // shared clock while the border is on screen; otherwise it keeps still (and costs nothing).
                property real angle: 0
                Binding {
                    target: shape
                    property: "angle"
                    when: b.live && BorderSettings.rotate
                    value: (BorderSettings.rotateDir === "ccw" ? 360 : -360) * ((BorderClock.t % BorderSettings.turnMs) / BorderSettings.turnMs)
                }

                // [{ pos, color }] around the circle, 0..1
                readonly property var ramp: {
                    const base = BorderSettings.colorType === "gradient" ? BorderSettings.gradientColors : [BorderSettings.baseColor, BorderSettings.baseColor]
                    const out = []
                    if (BorderSettings.rotate && BorderSettings.rotateMode === "streak") {
                        // a bright head that fades into a dim track over `streakPct` % of the border
                        const s = BorderSettings.streakPct / 100
                        const track = Qt.rgba(base[0].r, base[0].g, base[0].b, 0.22)
                        for (let i = 0; i < base.length; i++) out.push({ pos: i / base.length * s, color: base[i] })
                            out.push({ pos: s, color: track })
                            out.push({ pos: 1, color: track })
                            if (BorderSettings.rotateDir === "ccw") {          // mirror, so the head leads the other way
                                const m = out.map(function (e) { return { pos: 1 - e.pos, color: e.color } })
                                m.reverse()
                                return m
                            }
                            return out
                    }
                    // a plain gradient (or the whole gradient turning): the colours around the circle, seamless
                    for (let i = 0; i < base.length; i++) out.push({ pos: i / base.length, color: base[i] })
                        out.push({ pos: 1, color: base[0] })
                        return out
                }
                function pos(i) { return shape.ramp.length === 0 ? 0 : (i < shape.ramp.length ? shape.ramp[i].pos : 1) }
                function col(i) { return shape.ramp.length === 0 ? "transparent" : shape.ramp[Math.min(i, shape.ramp.length - 1)].color }

                // outer rounded rectangle + inner one, filled between them
                function rr(x, y, w, h, a, c, d, e) {   // a tl, c tr, d br, e bl
                    return "M " + (x + a) + " " + y + " H " + (x + w - c)
                    + " A " + c + " " + c + " 0 0 1 " + (x + w) + " " + (y + c)
                    + " V " + (y + h - d) + " A " + d + " " + d + " 0 0 1 " + (x + w - d) + " " + (y + h)
                    + " H " + (x + e) + " A " + e + " " + e + " 0 0 1 " + x + " " + (y + h - e)
                    + " V " + (y + a) + " A " + a + " " + a + " 0 0 1 " + (x + a) + " " + y + " Z "
                }
                readonly property string ring: {
                    const w = shape.width, h = shape.height, t = b.t
                    if (w < 2 * t + 1 || h < 2 * t + 1) return ""
                        const m = function (r) { return Math.max(0, Math.min(r, Math.min(w, h) / 2)) }
                        const n = function (r) { return Math.max(0, Math.min(r - t, (Math.min(w, h) - 2 * t) / 2)) }
                        return shape.rr(0, 0, w, h, m(b.tl), m(b.tr), m(b.br), m(b.bl))
                        + shape.rr(t, t, w - 2 * t, h - 2 * t, n(b.tl), n(b.tr), n(b.br), n(b.bl))
                }

                ShapePath {
                    strokeWidth: -1
                    fillRule: ShapePath.OddEvenFill
                    fillGradient: ConicalGradient {
                        centerX: shape.width / 2
                        centerY: shape.height / 2
                        angle: shape.angle
                        GradientStop { position: shape.pos(0); color: shape.col(0) }
                        GradientStop { position: shape.pos(1); color: shape.col(1) }
                        GradientStop { position: shape.pos(2); color: shape.col(2) }
                        GradientStop { position: shape.pos(3); color: shape.col(3) }
                        GradientStop { position: shape.pos(4); color: shape.col(4) }
                        GradientStop { position: shape.pos(5); color: shape.col(5) }
                        GradientStop { position: shape.pos(6); color: shape.col(6) }
                        GradientStop { position: shape.pos(7); color: shape.col(7) }
                    }
                    PathSvg { path: shape.ring }
                }
            }
        }
    }

    // ---- anime streaks and artefacts (nothing is created unless it is on) ----
    Loader {
        anchors.fill: parent
        active: b.on && b.shown && b.animeOn
        sourceComponent: BorderAnime {
            tl: b.tl; tr: b.tr; bl: b.bl; br: b.br
            t: b.t
            step: b.animeStep
            roomL: b.roomL; roomT: b.roomT; roomR: b.roomR; roomB: b.roomB
        }
    }
}
