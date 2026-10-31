pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../SBS"

QtObject {
    id: theme

    property bool isDark: true
    function toggleMode() { isDark = !isDark }

    // SBS forces the lock screen (the only Theme consumer still mounted
    // while SBS is active) into dark, without touching the persisted
    // isDark toggle or firing onIsDarkChanged's rofi/system writes.
    readonly property bool effectiveDark: SBSState.active ? true : isDark

    function adaptColor(c) {
        var l = c.hslLightness
        if (effectiveDark) {
            if (l < 0.45) l = 0.45
        } else {
            if (l > 0.5) l = 0.5
        }
        return Qt.hsla(c.hslHue, c.hslSaturation, l, c.a)
    }

    property var palette: ({
        background: "#0d0b16",
        foreground: "#e6e1f0",
            color0: "#0d0b16", color1: "#7c3aed", color2: "#a855f7", color3: "#c026d3",
            color4: "#6366f1", color5: "#8b5cf6", color6: "#d946ef", color7: "#e6e1f0",
            color8: "#4c1d95", color9: "#7c3aed", color10: "#a855f7", color11: "#c026d3",
            color12: "#818cf8", color13: "#a78bfa", color14: "#e879f9", color15: "#f5f3ff"
    })

    readonly property color color0: palette.color0
    readonly property color color1: palette.color1
    readonly property color color2: palette.color2
    readonly property color color3: palette.color3
    readonly property color color4: palette.color4
    readonly property color color5: palette.color5
    readonly property color color6: palette.color6
    readonly property color color7: palette.color7
    readonly property color color8: palette.color8

    // Active / highlighted buttons: the palette's colours, or the custom theme's own
    // (Settings > Theme > Active buttons).
    readonly property var customAccent: (customActive && activeTheme.accent && activeTheme.accent.auto === false)
    ? activeTheme.accent : null
    readonly property color accentActive: customAccent !== null
    ? colorOf(customAccent.active, effectiveDark, activeTheme.adapt !== false) : adaptColor(color3)
    readonly property color accentHover: customAccent !== null
    ? colorOf(customAccent.hover, effectiveDark, activeTheme.adapt !== false) : adaptColor(color1)

    // Text colour of the active custom theme (null = built-in colours below).
    readonly property var customTextColor: customActive
    ? resolveText(activeTheme.text, effectiveDark, activeTheme.adapt !== false) : null

    // Gradient of a custom text colour ({ colors, horizontal }) or null. Only GradientText
    // draws it; everything else uses customTextColor (the gradient's average).
    readonly property var textGradient: customActive
    ? resolveTextGradient(activeTheme.text, effectiveDark, activeTheme.adapt !== false) : null

    readonly property color foreground: customTextColor !== null ? customTextColor : (effectiveDark ? palette.foreground : "#1a1625")
    readonly property color background: effectiveDark ? palette.background : "#f5f3fa"
    readonly property color borderMuted: effectiveDark ? color8 : Qt.rgba(0, 0, 0, 0.12)
    readonly property color textMuted: customTextColor !== null
    ? Qt.rgba(customTextColor.r, customTextColor.g, customTextColor.b, 0.8)
    : (effectiveDark ? color7 : "#4a4458")
    readonly property color textDim: customTextColor !== null
    ? Qt.rgba(customTextColor.r, customTextColor.g, customTextColor.b, 0.55)
    : (effectiveDark ? color8 : "#8a8298")
    // Text on an active button: black as always, or black / white by the custom colour's brightness.
    readonly property color textOnAccent: customAccent === null ? "#000000"
    : (customAccent.textAuto === false ? colorOf(customAccent.text, effectiveDark, activeTheme.adapt !== false)
    : ((0.299 * accentActive.r + 0.587 * accentActive.g + 0.114 * accentActive.b) > 0.55 ? "#000000" : "#ffffff"))

    // ---- Surface style (main shell only) ----
    // "blur"   (default) translucent fills; Hyprland blurs what is behind them.
    // "opaque" solid, wallpaper-tinted fills -- nothing shows through, so the
    //          compositor blur rules have nothing to blur. No hyprland.lua change.
    // Persisted in state/theme-style.json. The lock screen background is drawn
    // in QML (MultiEffect) and never reads this, so it stays blurred either way.
    // A custom theme (Settings > Theme > Create) replaces both of these fills; picking
    // Transparent blur / Opaque again switches back to the built-in surfaces.
    readonly property bool opaque: styleAdapter.surface === "opaque"
    function setSurface(mode) {
        styleAdapter.surface = (mode === "opaque") ? "opaque" : "blur"
        styleAdapter.active = ""
    }
    function toggleSurface() { setSurface(opaque ? "blur" : "opaque") }

    property FileView _styleFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/state/theme-style.json"
        blockLoading: true            // read synchronously so there is no blur->opaque flash at login
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: (err) => writeAdapter()   // first run: create the file
        adapter: JsonAdapter {
            id: styleAdapter
            property string surface: "blur"     // "blur" | "opaque"
            property string active: ""          // "" = built-in surface, else a custom theme id
            property var themes: []             // [{ id, name, adapt, popup, bar, text }]
        }
    }

    // Solid surface tinted by the wallpaper hue. Lightness is pinned so a
    // bright pywal color0 can never produce unreadable text-on-surface.
    function _solid(dark, l) {
        const h = color0.hslHue < 0 ? 0 : color0.hslHue
        return Qt.hsla(h, Math.min(color0.hslSaturation, dark ? 0.35 : 0.30), l, 1)
    }
    function _popupSurface(dark) { return _solid(dark, dark ? 0.11 : 0.96) }
    function _barSurface(dark)   { return _solid(dark, dark ? 0.14 : 0.98) }

    readonly property color barBg: opaque
    ? _barSurface(effectiveDark)
    : (effectiveDark
    ? Qt.rgba(theme.palette.color0.r, theme.palette.color0.g, theme.palette.color0.b, 0.25)
    : Qt.rgba(1, 1, 1, 0.55))
    readonly property color barBorderTop: effectiveDark ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(0, 0, 0, 0.15)
    readonly property color _defaultPopupBg: opaque
    ? _popupSurface(effectiveDark)
    : (effectiveDark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.55))

    // ---- Fills ----
    // popupFill / barPanelFill are descriptions of how a surface is painted
    // (see resolveFill): GlassPanel and ThemeFill draw them. popupBg stays a
    // plain colour for everything that cannot draw a gradient or image (for a
    // gradient/pattern it is the average colour). popupPaintBg is what a
    // surface should fill itself with when ThemeFill paints on top of it.
    readonly property var popupFill: customActive
    ? resolveFill(activeTheme.popup, effectiveDark, activeTheme.adapt !== false)
    : ({ kind: "solid", color: _defaultPopupBg, avg: _defaultPopupBg, opacity: 1 })
    readonly property var barPanelFill: customActive
    ? resolveFill(activeTheme.bar, effectiveDark, activeTheme.adapt !== false)
    : popupFill
    readonly property color popupBg: popupFill.kind === "solid" ? popupFill.color : popupFill.avg
    readonly property color popupPaintBg: popupFill.kind === "solid" ? popupFill.color : "transparent"

    // ---- Custom themes ----
    // Colour = { mode: "dyn", i: 0..15 } (wallpaper palette slot, follows pywal)
    //        | { mode: "fix", hex: "#rrggbb" }
    // Fill   = { type: "solid" | "gradient" | "pattern", opacity: 0..100, brightness: -100..100,
    //            color, stops[2..6], horizontal, image, tile, tint, tintAmt: 0..100 }
    // Theme  = { id, name, adapt, popup: Fill, bar: Fill, text: { auto, color } }
    // Colours and brightness are authored for dark mode. With adapt on, light
    // mode mirrors lightness (1 - L) and flips the brightness sign.
    // Theme being created / edited in Settings. Kept here (not saved to disk) so closing
    // Settings in the middle of editing does not lose it; null when nothing is being edited.
    property var themeDraft: null

    readonly property var customThemes: styleAdapter.themes ? styleAdapter.themes : []
    readonly property var activeTheme: themeById(styleAdapter.active)
    readonly property bool customActive: activeTheme !== null
    readonly property string activeThemeId: customActive ? activeTheme.id : ""

    function themeById(id) {
        if (!id) return null
            const l = styleAdapter.themes ? styleAdapter.themes : []
            for (let i = 0; i < l.length; i++)
                if (l[i] && l[i].id === id) return l[i]
                    return null
    }
    function setActiveTheme(id) { styleAdapter.active = themeById(id) ? id : "" }

    function cloneTheme(def) { return JSON.parse(JSON.stringify(def)) }

    function newTheme() {
        const fill = () => ({
            type: "solid", opacity: 40, brightness: 0,
            color: { mode: "dyn", i: 0 },
            stops: [{ mode: "dyn", i: 1 }, { mode: "dyn", i: 3 }], horizontal: false,
            image: "", tile: false, tint: { mode: "dyn", i: 1 }, tintAmt: 0
        })
        return { id: "", name: "My theme", adapt: true, popup: fill(), bar: fill(),
            text: { auto: true, type: "solid", color: { mode: "dyn", i: 7 },
            stops: [{ mode: "dyn", i: 7 }, { mode: "dyn", i: 3 }], horizontal: true },
            accent: { auto: true, active: { mode: "dyn", i: 3 }, hover: { mode: "dyn", i: 1 },
            textAuto: true, text: { mode: "dyn", i: 0 } } }
    }

    // Inserts or replaces (by id). Returns the id.
    function saveTheme(def) {
        const t = cloneTheme(def)
        t.name = (t.name || "").trim() !== "" ? t.name.trim() : "Custom theme"
        if (!t.id) t.id = "t" + Date.now().toString(36)
            const l = (styleAdapter.themes ? styleAdapter.themes : []).slice()
            let at = -1
            for (let i = 0; i < l.length; i++) if (l[i] && l[i].id === t.id) { at = i; break }
            if (at >= 0) l[at] = t; else l.push(t)
                styleAdapter.themes = l
                return t.id
    }
    function deleteTheme(id) {
        const l = (styleAdapter.themes ? styleAdapter.themes : []).filter(t => t && t.id !== id)
        if (styleAdapter.active === id) styleAdapter.active = ""
            styleAdapter.themes = l
    }

    // Hard floor for fill opacity (%): below this the compositor blur rules stop blurring.
    readonly property int minOpacity: 40

    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
    function _num(v, d) { const n = Number(v); return isFinite(n) ? n : d }
    function _hex(h) { return (typeof h === "string" && /^#[0-9a-fA-F]{6}$/.test(h)) ? h : "#808080" }
    function _hue(c) { return c.hslHue < 0 ? 0 : c.hslHue }
    function _mirror(c) { return Qt.hsla(_hue(c), c.hslSaturation, 1 - c.hslLightness, c.a) }
    function _shade(c, b) {
        if (b === 0) return c
            const l = c.hslLightness
            return Qt.hsla(_hue(c), c.hslSaturation, b < 0 ? l * (1 + b) : l + (1 - l) * b, c.a)
    }

    function colorOf(col, dark, adapt) {
        let c
        if (col && col.mode === "dyn")
            c = Qt.color(palette["color" + _clamp(Math.round(_num(col.i, 0)), 0, 15)])
            else
                c = Qt.color(_hex(col ? col.hex : ""))
                return (!dark && adapt) ? _mirror(c) : c
    }

    function resolveText(t, dark, adapt) {
        if (!t || t.auto !== false) return null
            if (t.type === "gradient") {
                const g = resolveTextGradient(t, dark, adapt)
                if (g !== null) {
                    let r = 0, gg = 0, b = 0
                    for (let i = 0; i < g.colors.length; i++) { r += g.colors[i].r; gg += g.colors[i].g; b += g.colors[i].b }
                    return Qt.rgba(r / g.colors.length, gg / g.colors.length, b / g.colors.length, 1)
                }
            }
            return colorOf(t.color, dark, adapt)
    }

    function resolveTextGradient(t, dark, adapt) {
        if (!t || t.auto !== false || t.type !== "gradient" || !t.stops || t.stops.length < 2) return null
            const cols = []
            for (let i = 0; i < t.stops.length && i < 6; i++) cols.push(colorOf(t.stops[i], dark, adapt))
                return { colors: cols, horizontal: t.horizontal !== false }
    }

    // def -> what ThemeFill / GlassPanel paint. `dark` and `adapt` let the
    // preview show either mode regardless of the shell's current one.
    function resolveFill(def, dark, adapt) {
        const d = def || {}
        const kind = (d.type === "gradient" || d.type === "pattern") ? d.type : "solid"
        const op = _clamp(_num(d.opacity, 100), minOpacity, 100) / 100
        let b = _clamp(_num(d.brightness, 0), -100, 100) / 100
        if (!dark && adapt) b = -b
            const out = {
                kind: kind, opacity: op, horizontal: d.horizontal === true, tile: d.tile === true,
                image: (typeof d.image === "string") ? d.image : "", tintAmt: 0
            }
            if (kind === "solid") {
                const c = _shade(colorOf(d.color, dark, adapt), b)
                out.color = Qt.rgba(c.r, c.g, c.b, op)
                out.avg = out.color
                return out
            }
            if (kind === "gradient") {
                const src = (d.stops && d.stops.length >= 2) ? d.stops : [{ mode: "dyn", i: 1 }, { mode: "dyn", i: 3 }]
                const cols = []
                let r = 0, g = 0, bl = 0
                for (let i = 0; i < src.length && i < 6; i++) {
                    const c = _shade(colorOf(src[i], dark, adapt), b)
                    cols.push(c)
                    r += c.r; g += c.g; bl += c.b
                }
                out.colors = cols
                out.avg = Qt.rgba(r / cols.length, g / cols.length, bl / cols.length, op)
                return out
            }
            out.tintAmt = _clamp(_num(d.tintAmt, 0), 0, 100) / 100
            out.tint = colorOf(d.tint, dark, adapt)
            out.shade = b < 0 ? Qt.rgba(0, 0, 0, -b) : Qt.rgba(1, 1, 1, b)
            const base = out.tintAmt > 0 ? out.tint : (dark ? Qt.hsla(0, 0, 0.1, 1) : Qt.hsla(0, 0, 0.95, 1))
            const bc = _shade(base, b)
            out.avg = Qt.rgba(bc.r, bc.g, bc.b, op)
            return out
    }

    readonly property color hoverBg: effectiveDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.06)
    readonly property color hoverBgSoft: effectiveDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.045)
    readonly property color hoverBgStrong: effectiveDark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.08)
    readonly property color pillOffBg: effectiveDark ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.04)

    readonly property color iconColor: foreground

    readonly property int radiusSm: 6
    readonly property int radiusMd: 12
    readonly property int radiusPill: 20
    readonly property int barHeight: 28
    readonly property int gapSm: 6
    readonly property int gapMd: 10
    // ---- Shell font stack (main shell only; SBS hardcodes its own families) ----
    readonly property string defaultFont: "Satoshi Variable"

    // Bumped whenever a font file registers, so the availability checks re-run.
    property int _fontRev: 0
    function _has(f) { void theme._fontRev; return Qt.fontFamilies().indexOf(f) >= 0 }

    // default-default: Satoshi if installed, else the system sans-serif (fontconfig).
    readonly property string baseFont: _has(defaultFont) ? defaultFont : "sans-serif"
    readonly property string baseLabel: _has(defaultFont) ? defaultFont : "System Default"

    // Saved font if its file still loads, otherwise baseFont. A moved/deleted
    // font file therefore never leaves the shell with a broken font.
    property string fontFamily: {
        const f = fontAdapter.family
        return (f !== "" && _has(f)) ? f : baseFont
    }

    readonly property var fontStack: [{ family: baseFont, label: baseLabel, path: "", builtin: true }]
    .concat((fontAdapter.fonts || []).map(f => ({ family: f.family, label: f.family, path: f.path, builtin: false })))

    property FileView _fontFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/state/shell_font.json"
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        onLoadFailed: (err) => writeAdapter()   // first run: create the file
        adapter: JsonAdapter {
            id: fontAdapter
            property string family: ""          // "" = default
            property var fonts: []              // [{ family, path }]
            property real scale: 1.0            // UI-wide font scale
        }
    }

    // Re-registers every saved font file on each shell start.
    property Instantiator _fontLoaders: Instantiator {
        model: fontAdapter.fonts
        delegate: FontLoader {
            required property var modelData
            source: modelData && modelData.path ? "file://" + modelData.path : ""
            onStatusChanged: theme._fontRev++
        }
    }

    // Fresh probe per call so re-adding the same file always re-fires status.
    property Component _fontProbe: Component { FontLoader {} }

    function setFont(family) { fontAdapter.family = (family === theme.baseFont) ? "" : family }

    function addFont(path) {
        const l = theme._fontProbe.createObject(theme, { source: "file://" + path })
        if (!l) return
            function done() {
                if (l.status === FontLoader.Ready) {
                    l.statusChanged.disconnect(done)
                    const fam = l.name
                    if (!fontAdapter.fonts.some(f => f.family === fam))
                        fontAdapter.fonts = fontAdapter.fonts.concat([{ family: fam, path: path }])
                        theme._fontRev++
                        theme.setFont(fam)
                        l.destroy()
                } else if (l.status === FontLoader.Error) {
                    l.statusChanged.disconnect(done)
                    l.destroy()
                }
            }
            l.statusChanged.connect(done)
            done()
    }

    function removeFont(family) {
        if (family === theme.baseFont) return
            if (fontAdapter.family === family) fontAdapter.family = ""
                fontAdapter.fonts = fontAdapter.fonts.filter(f => f.family !== family)
    }

    // ---- Font scale (shell UI + rofi) ----
    readonly property real fontScaleMin: 0.7
    readonly property real fontScaleMax: 1.6
    readonly property real fontScale: {
        const s = Number(fontAdapter.scale)
        return (isFinite(s) && s > 0) ? Math.max(fontScaleMin, Math.min(fontScaleMax, s)) : 1.0
    }
    function setFontScale(v) {
        fontAdapter.scale = Math.round(Math.max(fontScaleMin, Math.min(fontScaleMax, v)) * 100) / 100
    }
    // Scale a base pixel size. Use for any literal font.pixelSize.
    function fs(n) { return Math.max(1, Math.round(n * theme.fontScale)) }

    readonly property int fontSize: fs(13)
    readonly property int fontSizeSm: fs(10)
    readonly property int fontSizeXs: fs(9)
    readonly property int fontSizeLg: fs(17)
    readonly property int fontSizeXl: fs(27)

    // ---- Rofi font sync ----
    // Rofi reads ~/.cache/rofi/font.rasi (generated by apply-rofi-font.sh).
    // Pango/fontconfig can't see FontLoader-registered files, so the script
    // also links the chosen font file into ~/.local/share/fonts.
    function _fontPathFor(family) {
        const f = (fontAdapter.fonts || []).find(x => x.family === family)
        return f ? f.path : ""
    }
    function _writeRofiFont() { _rofiFontDebounce.restart() }
    property Timer _rofiFontDebounce: Timer {
        interval: 400
        repeat: false
        onTriggered: Quickshell.execDetached(["bash",
                                             Quickshell.env("HOME") + "/.config/quickshell/scripts/apply-rofi-font.sh",
                                             theme.fontFamily, theme._fontPathFor(theme.fontFamily), String(theme.fontScale)])
    }
    onFontFamilyChanged: theme._writeRofiFont()
    onFontScaleChanged: theme._writeRofiFont()

    readonly property string rofiColorsPath: Quickshell.env("HOME") + "/.cache/rofi/colors.rasi"
    function _rgba(c) {
        return `rgba(${Math.round(c.r*255)}, ${Math.round(c.g*255)}, ${Math.round(c.b*255)}, ${c.a.toFixed(2)})`
    }

    function _neutralGray(l) {
        return Qt.hsla(0, 0, l, 1)
    }

    // While SBS is active, rofi's background is forced fully opaque black
    // instead of the usual semi-transparent dark palette color -- SBS's
    // own shell is flat black/white with no blur anywhere, and an opaque
    // window has nothing for a compositor blur rule to show through, so
    // this makes the rofi blur windowrule a non-issue without needing to
    // touch hyprland.lua.
    function _rofiVariant(dark) {
        const forceBlack = dark && SBSState.active

        const bg = forceBlack ? Qt.rgba(0, 0, 0, 1) : adaptColorFor(color0, dark)
        const fg =  dark ? Qt.color(palette.foreground) : Qt.color("#1a1625")
        const tMuted = adaptColorFor(color8, dark)
        const aActive = adaptColorFor(color3, dark)
        const aHover = adaptColorFor(color7, dark)

        const pBg = forceBlack
        ? Qt.rgba(0, 0, 0, 1)
        : (opaque ? _popupSurface(dark)
        : (dark ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.55)))

        const elementBg = dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.045)
        const selectedBg = Qt.rgba(255,255,255,0.15)

        const grayMuted = _neutralGray(0.55)
        const onAccent = Qt.color("#000000")

        return "* {\\n" +
        "    background: " + _rgba(bg) + ";\\n" +
        "    popup-bg: " + _rgba(pBg) + ";\\n" +
        "    foreground: " + _rgba(fg) + ";\\n" +
        "    accent-active: " + _rgba(aActive) + ";\\n" +
        "    accent-hover: " + _rgba(aHover) + ";\\n" +
        "    border-muted: " + _rgba(grayMuted) + ";\\n" +
        "    text-muted: " + _rgba(tMuted) + ";\\n" +
        "    text-dim: " + _rgba(grayMuted) + ";\\n" +
        "    element-bg: " + _rgba(elementBg) + ";\\n" +
        "    selected-bg: " + _rgba(selectedBg) + ";\\n" +
        "    text-on-accent: " + _rgba(onAccent) + ";\\n" +
        "}\\n"
    }
    function adaptColorFor(c, dark) {
        var l = c.hslLightness
        if (dark) {
            if (l < 0.45) l = 0.45
        } else {
            if (l > 0.5) l = 0.5
        }
        return Qt.hsla(c.hslHue, c.hslSaturation, l, c.a)
    }

    // _writeRofiColors() is triggered from several places at startup
    // (Component.onCompleted, SBS state load, the pywal palette load) and on
    // every theme/wallpaper change, each one spawning a bash that rewrites the
    // same two files. Coalesce a burst into a single run with the final state.
    function _writeRofiColors() {
        _rofiDebounce.restart()
    }
    property Timer _rofiDebounce: Timer {
        interval: 150
        repeat: false
        onTriggered: theme._doWriteRofiColors()
    }

    function _doWriteRofiColors() {
        const darkContent = _rofiVariant(true)
        const lightContent = _rofiVariant(false)
        // Symlink by effectiveDark, not raw isDark -- SBS forces dark
        // regardless of the persisted isDark toggle, so colors.rasi must
        // follow effectiveDark or it can point at the light variant while
        // the shell itself is rendering dark.
        const target = effectiveDark ? "colors-dark.rasi" : "colors-light.rasi"

        Quickshell.execDetached(["bash", "-c",
                                "mkdir -p ~/.cache/rofi && " +
                                "printf '%b' \"" + darkContent.replace(/"/g, '\\"') + "\" > ~/.cache/rofi/colors-dark.rasi && " +
                                "printf '%b' \"" + lightContent.replace(/"/g, '\\"') + "\" > ~/.cache/rofi/colors-light.rasi && " +
                                "ln -sf ~/.cache/rofi/" + target + " ~/.cache/rofi/colors.rasi"])
    }

    onIsDarkChanged: {
        theme._writeRofiColors()
        theme._writeSystemTheme()
    }
    // Catches SBS enabling/disabling (SBSState.active flips this even
    // when isDark itself never changes) as well as ordinary isDark
    // changes -- either way rofi's colors need regenerating.
    onEffectiveDarkChanged: theme._writeRofiColors()
    onPaletteChanged: theme._writeRofiColors()
    onOpaqueChanged: theme._writeRofiColors()

    // qs ipc call theme surface blur|opaque|toggle
    property IpcHandler _ipc: IpcHandler {
        target: "theme"
        function surface(mode: string): string {
            if (mode === "toggle") theme.toggleSurface()
                else if (mode === "blur" || mode === "opaque") theme.setSurface(mode)
                    else return "use: blur | opaque | toggle"
                        return theme.opaque ? "opaque" : "blur"
        }
    }

    // effectiveDark only re-derives a boolean (dark/light); it does NOT
    // change value when SBS turns off while isDark was already true, or
    // turns on while isDark was already true. But _rofiVariant()'s output
    // still depends directly on SBSState.active via forceBlack (opaque
    // black vs. normal semi-transparent dark bg) -- so effectiveDark
    // alone isn't a sufficient trigger. This watches SBSState.active
    // itself so the SBS<->main-shell transition regenerates colors.rasi
    // even when effectiveDark's value doesn't move, instead of only
    // resolving on the next Quickshell restart's Component.onCompleted.
    readonly property bool sbsActive: SBSState.active
    onSbsActiveChanged: theme._writeRofiColors()

    Component.onCompleted: {
        theme._writeRofiColors()
        theme._writeRofiFont()
        theme._writeSystemTheme()
    }

    function _writeSystemTheme() {
        const mode = isDark ? "dark" : "light"
        Quickshell.execDetached(["bash", "-c",
                                "mkdir -p ~/.cache/quickshell && printf '%s' '" + mode + "' > ~/.cache/quickshell/theme_mode && " +
                                "~/.config/hypr/apply-theme.sh " + mode])
    }

    property string walPath: Quickshell.env("HOME") + "/.cache/wal/colors.json"

    property FileView _walFile: FileView {
        id: walFileView
        path: theme.walPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: theme._applyWal(text())
        onLoadFailed: (error) => {
            console.warn("Theme: no pywal cache yet at", theme.walPath, "- using fallback palette")
        }
    }

    property FileView _themeTrigger: FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell/theme_trigger"
        watchChanges: true
        onFileChanged: walFileView.reload()
    }

    function _applyWal(raw) {
        try {
            const data = JSON.parse(raw)

            const special = data.special || {}
            const colors = data.colors || {}
            const p = {}

            p.background = special.background || palette.background
            p.foreground = special.foreground || palette.foreground

            for (let i = 0; i <= 15; i++) {
                const key = "color" + i
                p[key] = colors[key] || palette[key]
            }

            if (JSON.stringify(p) === JSON.stringify(palette))
                return

                palette = p
        } catch (e) {
            console.warn("Theme: failed to parse pywal colors.json:", e)
        }
    }
}
