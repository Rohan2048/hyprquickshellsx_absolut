import QtQuick
import Qt5Compat.GraphicalEffects
import Quickshell
import QtQuick.Layouts
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import "../Theme"
import "../Widgets"
import "../Services"
import "../Popups"
import "./modules"

Item {
    id: root
    // the screen this bar is on, and the config of this bar (Bar/BarConfig.qml). Created by BarHost.
    required property var screenRef
    required property var cfg

    // --- Auto-hide trigger area ---
    PanelWindow {
        id: edgeTrigger
        screen: root.screenRef
        visible: bar.autohide
        WlrLayershell.namespace: "bar-trigger"
        WlrLayershell.layer: WlrLayer.Top
        // Same footprint as the bar's visible pill. The classic bar is centred by the compositor
        // when it does not fill the edge; preset bars are anchored at their start and positioned
        // with a margin (so start / centre / end alignment and several bars per edge all work).
        readonly property bool placed: !bar.cfg.legacy && !bar.fill
        anchors {
            top: bar.edge === "top" || (bar.vertical && (bar.fill || edgeTrigger.placed))
            bottom: bar.edge === "bottom" || (bar.vertical && bar.fill)
            left: bar.edge === "left" || (!bar.vertical && (bar.fill || edgeTrigger.placed))
            right: bar.edge === "right" || (!bar.vertical && bar.fill)
        }
        margins {
            left: (!bar.vertical && edgeTrigger.placed) ? bar.targetMainStart : 0
            top: (bar.vertical && edgeTrigger.placed) ? bar.targetMainStart : 0
        }
        implicitWidth: bar.vertical ? 14 : bar.targetVisualLength
        implicitHeight: bar.vertical ? bar.targetVisualLength : 14
        color: "transparent"
        exclusiveZone: -1

        HoverHandler {
            id: triggerHoverHandler
            onHoveredChanged: bar.pointerUpdate()
        }
    }

    PanelWindow {
        id: bar
        screen: root.screenRef
        WlrLayershell.namespace: "bar-window"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        // --- Config-driven geometry (this bar's BarConfig; the classic bar mirrors BarSettings) ---
        readonly property var cfg: root.cfg
        readonly property string edge: cfg.edge
        readonly property bool vertical: cfg.vertical
        readonly property bool autohide: cfg.autohide
        readonly property bool docked: !autohide
        readonly property bool fill: cfg.sizeMode === "fill"
        // a docked edge-to-edge bar sits flush with the screen edge and is square
        readonly property bool flush: docked && fill
        readonly property real edgeGap: flush ? 0 : Theme.gapSm
        // SCALE: items are laid out at their normal size (baseThickness, unscaled units);
        // the content is then scaled by `sc`. `thickness` is the real pixel thickness.
        readonly property real sc: cfg.scale
        readonly property real baseThickness: cfg.thickness
        readonly property real thickness: baseThickness * sc
        readonly property real crossSize: thickness + edgeGap
        // Anime border streaks ride outside the pill, so while that effect is on the window gets a transparent
        // strip on its inner side to draw in (and the pill stops clipping). The reserved space (crossSize),
        // popup placement and the input region are unchanged: this strip is only room to draw.
        readonly property real fxRoom: (BorderSettings.enabled && BorderSettings.anime) ? 14 : 0
        readonly property real winCross: crossSize + fxRoom
        readonly property real screenLength: screen ? (vertical ? screen.height : screen.width) : 0
        // longest the pill can be
        readonly property real windowLength: fill ? screenLength
        : (cfg.sizeMode === "fixed" ? Math.min(cfg.lengthPx, screenLength) : screenLength - Theme.gapMd * 1.5)
        // The classic bar's window is only as long as it can get and is centred by the compositor.
        // Preset bars use a full-length window and place the pill inside it (mask = the pill).
        readonly property bool fullWindow: fill || !cfg.legacy
        readonly property real winLength: fullWindow ? screenLength : windowLength
        readonly property real windowMainStart: fullWindow ? 0 : (screenLength - windowLength) / 2
        readonly property real slotSpacing: 2

        // Where a pill of length `len` starts inside the window (along the bar).
        function mainPosFor(len) {
            if (cfg.legacy) return (windowLength - len) / 2
                var L = winLength
                var m = cfg.offset + (fill ? 0 : Theme.gapMd * 0.75)
                if (cfg.align === "start") return m
                    if (cfg.align === "end") return Math.max(0, L - len - m)
                        return Math.max(0, (L - len) / 2)
        }
        // absolute screen position the (target-size) pill starts at, for the hover trigger
        readonly property real targetMainStart: windowMainStart + mainPosFor(targetVisualLength)

        // -1 = ignore other surfaces' reserved space. Without it the compositor places a bar that does
        // not reserve INSIDE the space another bar of the same edge reserved, i.e. further from the edge.
        exclusiveZone: cfg.reserves ? crossSize : -1

        implicitWidth: vertical ? winCross : winLength
        implicitHeight: vertical ? winLength : winCross
        anchors {
            top: bar.edge === "top" || (bar.vertical && bar.fullWindow)
            bottom: bar.edge === "bottom" || (bar.vertical && bar.fullWindow)
            left: bar.edge === "left" || (!bar.vertical && bar.fullWindow)
            right: bar.edge === "right" || (!bar.vertical && bar.fullWindow)
        }

        property var barCreationStart: Date.now()
        property bool isHovered: false
        readonly property bool isTriggerHovered: triggerHoverHandler.hovered

        property bool anyPopupOpen: volumePopup.visible || batteryPopup.visible || notificationsPopup.visible
        || wifiPopup.visible || bluetoothPopup.visible || dateTimePopup.visible || musicPopup.visible
        || timerPopup.visible || stopwatchPopup.visible
        || (appsTray.hoveredEntry !== null) || (appsTray.contextMenuEntry !== null)

        readonly property string iconDir: "file://" + Quickshell.env("HOME") + "/.config/icons/"
        property var minimizeWorkspaceMap: ({})
        property var closeQueue: []

        readonly property var batteryMap: ({
            "FULL": "full-battery.svg",
            "ABOVE85": "above85.svg", "ABOVE85_CHG": "above85.svg",
            "HIGH": "high-battery.svg", "HIGH_CHG": "high-battery.svg",
            "MED": "med-battery.svg", "MED_CHG": "med-battery.svg",
            "HALF": "half-battery.svg", "HALF_CHG": "half-battery.svg",
            "BELOW_HALF": "below-half-battery.svg", "BELOW_HALF_CHG": "below-half-battery.svg",
            "LOW": "low-battery.svg", "LOW_CHG": "low-battery.svg",
            "VERY_LOW_CHG": "very-low-battery.svg"
        })

        readonly property bool batteryCharging: [
            "ABOVE85_CHG", "HIGH_CHG", "MED_CHG", "HALF_CHG",
            "BELOW_HALF_CHG", "LOW_CHG", "VERY_LOW_CHG"
        ].includes(Battery.icon)

        readonly property var hyprIndex: {
            var byWayland = new Map()
            var list = Hyprland.toplevels.values
            for (var i = 0; i < list.length; i++) {
                var h = list[i]
                if (h.wayland) {
                    byWayland.set(h.wayland, h)
                }
            }
            return byWayland
        }

        function truncate(s, n) {
            return s.length > n ? s.substring(0, n - 1) + "…" : s
        }

        function findHyprToplevel(toplevel) {
            var hypr = bar.hyprIndex.get(toplevel)
            if (hypr) { return hypr }
            var appId = (toplevel.appId ?? "").toLowerCase()
            var title = toplevel.title ?? ""
            var list = Hyprland.toplevels.values
            for (var i = 0; i < list.length; i++) {
                if ((list[i].class ?? "").toLowerCase() === appId && list[i].title === title) { return list[i] }
            }
            for (var j = 0; j < list.length; j++) {
                if (list[j].title === title) { return list[j] }
            }
            return null
        }

        function isMinimizedFake(toplevel) {
            var hypr = findHyprToplevel(toplevel)
            if (!hypr) { return false }
            var addr = hypr.address.startsWith("0x") ? hypr.address : "0x" + hypr.address
            return addr in minimizeWorkspaceMap
        }

        function activateWindow(toplevel) {
            if (isMinimizedFake(toplevel)) {
                toggleMinimize(toplevel)
            } else {
                toplevel.activate()
            }
        }

        function toggleMinimize(toplevel) {
            var hypr = findHyprToplevel(toplevel)
            if (!hypr) { return }
            var addr = hypr.address.startsWith("0x") ? hypr.address : "0x" + hypr.address
            if (addr in minimizeWorkspaceMap) {
                var origin = minimizeWorkspaceMap[addr] || "1"
                Hyprland.dispatch('hl.dsp.window.move({workspace = "' + origin + '", follow = false, window = "address:' + addr + '"})')
                delete minimizeWorkspaceMap[addr]
                minimizeWorkspaceMap = minimizeWorkspaceMap
                toplevel.activate()
            } else {
                minimizeWorkspaceMap[addr] = hypr.workspace ? hypr.workspace.name : "1"
                minimizeWorkspaceMap = minimizeWorkspaceMap
                Hyprland.dispatch('hl.dsp.window.move({workspace = "special:minimized", follow = false, window = "address:' + addr + '"})')
            }
        }

        Timer {
            id: closeQueueTimer
            interval: 60
            repeat: true
            onTriggered: {
                if (bar.closeQueue.length === 0) {
                    closeQueueTimer.stop()
                } else {
                    var w = bar.closeQueue.shift()
                    try { w.close() } catch (e) {}
                }
            }
        }

        function closeAll(windows) {
            bar.closeQueue = bar.closeQueue.concat(windows.slice())
            if (!closeQueueTimer.running) {
                closeQueueTimer.start()
            }
        }

        // While any bar of a preset has a popup / thumbnail open, every bar of the preset stays shown.
        onAnyPopupOpenChanged: {
            BarPresets.setBusy(bar.cfg.cid, anyPopupOpen)
            if (!anyPopupOpen) {
                bar.isHovered = barHoverHandler.hovered || triggerHoverHandler.hovered
                if (!bar.isHovered) {
                    hideTimer.restart()
                }
            }
        }

        Connections {
            target: BarPresets
            function onAnyBusyChanged() {
                if (!BarPresets.anyBusy && !bar.anyPopupOpen) bar.pointerUpdate()
            }
        }
        Component.onDestruction: BarPresets.setBusy(bar.cfg.cid, false)

        Timer {
            id: hideTimer
            interval: 1000
            onTriggered: {
                if (!bar.anyPopupOpen && !triggerHoverHandler.hovered && !barHoverHandler.hovered) {
                    bar.isHovered = false
                }
            }
        }

        // Single source of truth for pointer-over-bar/strip: reveal immediately,
        // hide only after the delay AND only if the pointer is really gone.
        function pointerUpdate() {
            if (triggerHoverHandler.hovered || barHoverHandler.hovered) {
                bar.isHovered = true
                hideTimer.stop()
            } else {
                hideTimer.restart()
            }
        }

        // ============================================================
        // ITEM ORDER / LAYOUT  (all lengths below are in UNSCALED units
        // unless noted; multiply by `sc` for real pixels)
        // ============================================================
        readonly property var slotMap: ({
            "power": powerSlot, "music": musicSlot, "apps": traySlot,
            "wifi": wifiSlot, "bluetooth": btSlot, "volume": volumeSlot,
            "battery": batterySlot, "clock": clockSlot,
            "stopwatch": stopwatchSlot, "timer": timerSlot, "bell": bellSlot,
            "workspaces": workspacesSlot,
            "launcher": launcherSlot,
            "settings": settingsSlot,
            "lock": lockSlot,
            "commands": commandsSlot,
            "shortcuts": shortcutsSlot,
            "overview": overviewSlot,
            "display": displaySlot,
            "schedule": scheduleSlot
        })

        // Live length (follows each item's own animation, frame by frame).
        function slotLen(s) { return s ? (bar.vertical ? s.height : s.width) : 0 }
        function gapFor(len) { return slotSpacing * Math.min(1, len / 12) }

        // Preset bars that are edge to edge / fixed length centre their modules when there is
        // spare room (the classic bar keeps its layout exactly as it was).
        readonly property real lead: (cfg.legacy || sizeMode_fit || free) ? 0 : Math.max(0, (barContent.mainLength - contentLength) / 2)
        readonly property bool sizeMode_fit: cfg.sizeMode === "fit"

        // ---- free layout (Settings > Bar > Presets: icons placed anywhere along the bar) ----
        // Each icon has its own distance from the content start, so the icons are not tied to either end
        // (edge to edge bars especially). No flowing and no gaps are derived: a slot just sits at its place.
        readonly property var places: cfg.places
        readonly property bool free: places !== null && places !== undefined
        // room along the content for fill / fixed bars (unscaled units); -1 = fit bars grow with their icons
        readonly property real freeLimit: (fill || cfg.sizeMode === "fixed") ? Math.max(0, windowLength / sc - Theme.gapMd * 2) : -1
        function freeStart(id, len) {
            var p = places[id]
            if (p === undefined) return -1
                if (freeLimit >= 0) p = Math.min(p, Math.max(0, freeLimit - len))
                    return Math.max(0, p)
        }
        // far end of the placed icons
        function freeExtent(useTarget) {
            var o = cfg.order
            var end = 0
            for (var i = 0; i < o.length; i++) {
                var s = slotMap[o[i]]
                var l = useTarget ? slotTarget(s) : slotLen(s)
                if (l <= 0) continue
                    var p = freeStart(o[i], l)
                    if (p >= 0) end = Math.max(end, p + l)
            }
            return end
        }

        function slotOffset(id) {
            if (free) {
                var p0 = freeStart(id, slotLen(slotMap[id]))
                return p0 >= 0 ? p0 : freeExtent(false)      // an icon with no place yet goes after the others
            }
            var o = cfg.order
            var pos = 0
            for (var i = 0; i < o.length; i++) {
                var s = slotMap[o[i]]
                var l = slotLen(s)
                var g = l > 0 && pos > 0 ? gapFor(l) : 0
                if (o[i] === id) return lead + pos + g
                    if (l > 0) pos += g + l
            }
            return lead + pos
        }

        // Live total: only used to keep the icons centred while they animate.
        readonly property real contentLength: {
            if (free) return freeExtent(false)
                var o = cfg.order
                var sum = 0
                for (var i = 0; i < o.length; i++) {
                    var s = slotMap[o[i]]
                    var l = slotLen(s)
                    if (l > 0) {
                        var g = sum > 0 ? gapFor(l) : 0
                        sum += g + l
                    }
                }
                return sum
        }

        readonly property real othersLength: {
            var o = cfg.order
            var sum = 0
            for (var i = 0; i < o.length; i++) {
                if (o[i] === "apps") continue
                    var s = slotMap[o[i]]
                    var l = slotLen(s)
                    if (l > 0) {
                        var g = sum > 0 ? gapFor(l) : 0
                        sum += g + l
                    }
            }
            return sum
        }

        // Where a slot is heading (its final length), not where it is mid-animation.
        function slotTarget(s) {
            var c = s ? s.child : null
            if (!c) return 0
                if (c.shown !== undefined && c.contentWidth !== undefined)   // TrayReveal
                    return c.shown ? (bar.vertical ? c.contentHeight : c.contentWidth) : 0
                    if (c.mainLength !== undefined) return c.mainLength            // AppsTray
                        return slotLen(s)
        }

        // Final total length. Changes once per event, so the pill can ease to it
        // with a single animation instead of being recomputed every frame.
        readonly property real contentTarget: {
            if (free) return freeExtent(true)
                var o = cfg.order
                var sum = 0
                for (var i = 0; i < o.length; i++) {
                    var l = slotTarget(slotMap[o[i]])
                    if (l > 0) sum += (sum > 0 ? gapFor(l) : 0) + l
                }
                return sum
        }

        // SCALE: room for the tray is computed in unscaled units (windowLength is pixels).
        readonly property real trayMaxLength: Math.max(0,
                                                       windowLength / sc - Theme.gapMd * 2 - (fill ? 0 : Theme.gapMd * 2) - othersLength)

        // SCALE: real pixel length of the pill.
        readonly property real baseVisualLength: (fill || cfg.sizeMode === "fixed")
        ? windowLength
        : Math.min((contentTarget + Theme.gapMd * 2) * sc, windowLength)

        // ---- popup mode "Merge & expand" ----
        // While one of this bar's popups is open the pill grows to at least the popup's length and
        // the popup sits flush against it, so they read as one shape. Other bars are not affected.
        //
        // Nothing is re-derived while the pill moves. There are two reference states and ONE number
        // that animates between them:
        //   rest     baseVisualLength                         (nothing open)
        //   merged   rest + mergeGrowTarget                   (grown to the popup, measured once)
        //   mergeGrow  0 at rest, mergeGrowTarget when merged  <- the only animated value
        // Everything else (popup position, hover strip, input mask) reads the FINAL numbers
        // (targetVisualLength) and so stays still while the pill eases.
        readonly property real openPopupSize: {
            var list = [volumePopup, batteryPopup, notificationsPopup, wifiPopup, bluetoothPopup,
            dateTimePopup, musicPopup, timerPopup, stopwatchPopup]
            var m = 0
            for (var i = 0; i < list.length; i++)
                if (list[i].visible) m = Math.max(m, bar.vertical ? list[i].implicitHeight : list[i].implicitWidth)
                    return m
        }
        // the popup's length, taken once it has settled (a popup that is still filling in does not
        // restart the animation on every step); 0 while nothing is open, so nothing stale carries over
        property real mergeSize: 0
        Timer { id: mergeSettle; interval: 40; onTriggered: bar.mergeSize = bar.openPopupSize }
        onOpenPopupSizeChanged: {
            if (openPopupSize <= 0) { mergeSettle.stop(); mergeSize = 0 }
            else if (mergeSize <= 0) mergeSize = openPopupSize      // fresh open: use it straight away
                else mergeSettle.restart()                              // resized while open: settle first
        }

        // corners square the moment a popup opens (unchanged)
        readonly property bool mergeOpen: cfg.popupMode === "merge" && openPopupSize > 0
        readonly property real mergeGrowTarget: (cfg.popupMode === "merge" && openPopupSize > 0)
        ? Math.max(0, Math.min(mergeSize, screenLength) - baseVisualLength) : 0
        // where the pill is heading (rest, or merged): a plain number that only changes on events
        readonly property real targetVisualLength: baseVisualLength + mergeGrowTarget

        // rest length keeps its old ease (content changes), merge growth has its own: one animation each
        property real restLength: baseVisualLength
        Behavior on restLength { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
        property real mergeGrow: mergeGrowTarget
        Behavior on mergeGrow { NumberAnimation { duration: 260; easing.type: Easing.OutQuint } }
        readonly property real visualLength: restLength + mergeGrow

        readonly property bool nearOrigin: edge === "top" || edge === "left"
        // (the window grows on its inner side: for a bottom / right bar that is the origin side, so the pill moves down by fxRoom)
        readonly property real shownCross: nearOrigin ? edgeGap : fxRoom
        readonly property real hiddenCross: nearOrigin ? -thickness : winCross

        // Merge & expand: the input region is the pill's FINAL rectangle (a few px more than the pill for
        // the length of the ease), so the compositor is not sent a new input region every frame.
        Item {
            id: maskBox
            visible: false
            readonly property real cross: barClip.shown ? bar.shownCross : bar.hiddenCross
            readonly property real main: bar.mainPosFor(bar.targetVisualLength)
            width: bar.vertical ? bar.thickness : bar.targetVisualLength
            height: bar.vertical ? bar.targetVisualLength : bar.thickness
            x: bar.vertical ? cross : main
            y: bar.vertical ? main : cross
        }
        mask: Region { item: bar.cfg.popupMode === "merge" ? maskBox : barClip }

        Item {
            id: barClip
            width: bar.vertical ? bar.thickness : Math.round(bar.visualLength)
            height: bar.vertical ? Math.round(bar.visualLength) : bar.thickness
            clip: !(BorderSettings.enabled && BorderSettings.anime)   // the border effect needs to draw outside the pill

            readonly property real mainPos: Math.round(bar.mainPosFor(bar.visualLength))
            readonly property bool shown: !bar.autohide || bar.isHovered || bar.anyPopupOpen || (bar.cfg.grouped && BarPresets.anyBusy)
            property real crossPos: shown ? bar.shownCross : bar.hiddenCross
            Behavior on crossPos { NumberAnimation { duration: 300; easing.type: Easing.OutQuart } }

            x: bar.vertical ? crossPos : mainPos
            y: bar.vertical ? mainPos : crossPos

            GlassPanel {
                id: glassPanel
                role: "bar"
                anchors.fill: parent
                animeAllowed: barClip.shown          // an autohide bar that is hidden draws no border effect
                // SCALE: roundness 100% = full pill, 0% = square. Docked is always square.
                bare: bar.cfg.bg === "transparent"
                radius: bar.flush ? 0 : (bar.thickness / 2) * bar.cfg.roundnessPct / 100
                // Merge & expand: the side facing the open popup is square
                topLeftRadius: (bar.mergeOpen && (bar.edge === "bottom" || bar.edge === "right")) ? 0 : radius
                topRightRadius: (bar.mergeOpen && (bar.edge === "bottom" || bar.edge === "left")) ? 0 : radius
                bottomLeftRadius: (bar.mergeOpen && (bar.edge === "top" || bar.edge === "right")) ? 0 : radius
                bottomRightRadius: (bar.mergeOpen && (bar.edge === "top" || bar.edge === "left")) ? 0 : radius

                Item {
                    id: barContent
                    anchors.centerIn: parent
                    opacity: 1

                    // SCALE: laid out unscaled, then scaled about its centre.
                    scale: bar.sc

                    readonly property real mainLength: (bar.fill || bar.cfg.sizeMode === "fixed")
                    ? Math.max(0, bar.visualLength / bar.sc - Theme.gapMd * 2)
                    : bar.contentLength
                    width: bar.vertical ? bar.baseThickness : mainLength
                    height: bar.vertical ? mainLength : bar.baseThickness

                    property real entranceBlur: 0
                    property bool entranceBlurActive: false
                    property real themeBlurProgress: 0
                    property bool themeBlurActive: false
                    readonly property real themeBlurLength: Animations.blurEnvelope(themeBlurProgress) * Animations.wallpaperBlurLength

                    layer.enabled: entranceBlurActive || themeBlurActive
                    layer.effect: DirectionalBlur {
                        angle: barContent.themeBlurActive ? Animations.wallpaperBlurAngle
                        : (bar.vertical ? Animations.slideBlurHorizontalAngle : Animations.slideBlurVerticalAngle)
                        length: barContent.entranceBlur + barContent.themeBlurLength
                        samples: Animations.slideBlurSamples
                    }

                    // ---------------- power ----------------
                    BarSlot {
                        id: powerSlot; owner: bar; slotId: "power"
                        ControlIcon {
                            cfg: bar.cfg
                            iconId: "power"
                            iconSource: bar.iconDir + "power-btn.svg"
                            iconSize: 16
                            onActivated: {
                                Quickshell.execDetached(["bash", Quickshell.env("HOME") + "/.config/rofi/powermenu.sh"])
                            }
                        }
                    }

                    // ---------------- music ----------------
                    BarSlot {
                        id: musicSlot; owner: bar; slotId: "music"
                        TrayReveal {
                            cfg: bar.cfg
                            id: musicReveal
                            active: MusicPlayerService.active
                            ControlIcon {
                                cfg: bar.cfg
                                id: musicIcon
                                iconId: "music"
                                iconSource: bar.vertical ? bar.iconDir + "music-placeholder.png" : ""
                                text: bar.vertical ? "" : bar.truncate(MusicPlayerService.title, 28)
                                onActivated: { musicPopup.toggle() }
                            }
                        }
                    }

                    // ---------------- app tray ----------------
                    BarSlot {
                        id: traySlot; owner: bar; slotId: "apps"
                        AppsTray {
                            id: appsTray
                            bar: bar
                            barScreen: bar.screen
                            maxLength: bar.trayMaxLength
                            tracking: popupTracking
                        }
                    }

                    // ---------------- wifi ----------------
                    BarSlot {
                        id: wifiSlot; owner: bar; slotId: "wifi"
                        ControlIcon {
                            cfg: bar.cfg
                            id: wifiIconItem
                            iconId: Wifi.radioOn ? "wifi" : "wifi-off"
                            iconSource: bar.iconDir + (Wifi.radioOn ? "wifion.svg" : "wifi-off.svg")
                            onActivated: { wifiPopup.toggle() }
                        }
                    }

                    // ---------------- bluetooth ----------------
                    BarSlot {
                        id: btSlot; owner: bar; slotId: "bluetooth"
                        ControlIcon {
                            cfg: bar.cfg
                            id: bluetoothIconItem
                            iconId: Bluetooth.radioOn ? "bluetooth" : "bluetooth-off"
                            iconSource: bar.iconDir + (Bluetooth.radioOn ? "bluetooth-icon.svg" : "bluetooth-off.svg")
                            onActivated: { bluetoothPopup.toggle() }
                        }
                    }

                    // ---------------- volume ----------------
                    BarSlot {
                        id: volumeSlot; owner: bar; slotId: "volume"
                        ControlIcon {
                            cfg: bar.cfg
                            id: volumeIconItem
                            iconId: Volume.muted ? "volume-mute" : "volume"
                            iconSource: bar.iconDir + (Volume.muted ? "sound-mute.svg" : "sound.svg")
                            onActivated: { volumePopup.toggle() }
                        }
                    }

                    // ---------------- battery ----------------
                    BarSlot {
                        id: batterySlot; owner: bar; slotId: "battery"
                        ControlIcon {
                            cfg: bar.cfg
                            id: batteryIconItem
                            iconId: "plug"
                            iconSource: Battery.hasBattery ? "" : bar.iconDir + "plug.svg"
                            implicitWidth: !Battery.hasBattery ? 34
                            : (bar.vertical ? bar.baseThickness : batteryRow.implicitWidth + 16)
                            implicitHeight: !Battery.hasBattery ? (bar.vertical ? 34 : bar.baseThickness)
                            : (bar.vertical ? batteryRow.implicitHeight + 12 : bar.baseThickness)
                            onActivated: { if (Battery.hasBattery) batteryPopup.toggle() }
                            Grid {
                                id: batteryRow
                                anchors.centerIn: parent
                                visible: Battery.hasBattery
                                spacing: 4
                                columns: bar.vertical ? 1 : 3
                                horizontalItemAlignment: Grid.AlignHCenter
                                verticalItemAlignment: Grid.AlignVCenter
                                Item {
                                    id: boltSlot
                                    readonly property bool shown: bar.batteryCharging || boltInner.opacity > 0
                                    width: bar.vertical ? 10 : (shown ? 10 : 0)
                                    height: bar.vertical ? (shown ? 10 : 0) : 10
                                    visible: boltInner.opacity > 0
                                    Behavior on width { NumberAnimation { duration: Animations.scaleDuration(150); easing.type: Animations.slideBlurEasingOut } }
                                    Behavior on height { NumberAnimation { duration: Animations.scaleDuration(150); easing.type: Animations.slideBlurEasingOut } }
                                    Item {
                                        id: boltInner
                                        width: 12; height: 12; opacity: 0; property real shakeX: 0
                                        transform: Translate { x: boltInner.shakeX }
                                        layer.enabled: boltInner.opacity > 0
                                        layer.effect: DirectionalBlur {
                                            angle: Animations.slideBlurHorizontalAngle
                                            length: Math.max((1 - boltInner.opacity) * 15, Math.abs(boltInner.shakeX) * 4)
                                            samples: 12
                                        }
                                        ThemedIcon {
                                            anchors.fill: parent
                                            size: 12
                                            iconId: "battery-charging"
                                            fallback: bar.iconDir + "bolt.svg"
                                        }
                                        Component.onCompleted: { if (bar.batteryCharging) { boltInner.opacity = 1; boltShakeAnim.start() } }
                                        Connections {
                                            target: bar
                                            function onBatteryChargingChanged() {
                                                if (bar.batteryCharging) { boltExitAnim.stop(); boltShakeAnim.stop(); boltInner.shakeX = 0; boltEnterAnim.restart() }
                                                else { boltEnterAnim.stop(); boltShakeAnim.stop(); boltInner.shakeX = 0; boltExitAnim.restart() }
                                            }
                                        }
                                        SequentialAnimation {
                                            id: boltEnterAnim
                                            NumberAnimation { target: boltInner; property: "opacity"; to: 1; duration: Animations.scaleDuration(120); easing.type: Animations.slideBlurEasingOut }
                                            ScriptAction { script: { boltShakeAnim.start() } }
                                        }
                                        SequentialAnimation {
                                            id: boltExitAnim
                                            ScriptAction { script: { boltShakeAnim.start() } }
                                            PauseAnimation { duration: Animations.scaleDuration(275) }
                                            NumberAnimation { target: boltInner; property: "opacity"; to: 0; duration: Animations.scaleDuration(120); easing.type: Animations.slideBlurEasingIn }
                                        }
                                        SequentialAnimation {
                                            id: boltShakeAnim
                                            NumberAnimation { target: boltInner; property: "shakeX"; to: -2.5; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                                            NumberAnimation { target: boltInner; property: "shakeX"; to: 2.5; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                                            NumberAnimation { target: boltInner; property: "shakeX"; to: -1.2; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                                            NumberAnimation { target: boltInner; property: "shakeX"; to: 1.2; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                                            NumberAnimation { target: boltInner; property: "shakeX"; to: 0; duration: Animations.scaleDuration(55); easing.type: Easing.InOutQuad }
                                        }
                                    }
                                }
                                ThemedIcon {
                                    size: 20
                                    iconId: IconSettings.batteryId(Battery.icon)
                                    fallback: bar.iconDir + (bar.batteryMap[Battery.icon] || "very-low-battery.svg")
                                }
                                Text {
                                    text: Battery.capacity + "%"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                                }
                            }
                        }
                    }

                    // ---------------- clock ----------------
                    BarSlot {
                        id: clockSlot; owner: bar; slotId: "clock"
                        ControlIcon {
                            cfg: bar.cfg
                            id: clockBtn
                            implicitWidth: bar.vertical ? bar.baseThickness : clockCol.implicitWidth + 16
                            implicitHeight: bar.vertical ? clockCol.implicitHeight + 12 : bar.baseThickness
                            onActivated: { dateTimePopup.toggle() }
                            Column {
                                id: clockCol; anchors.centerIn: parent; spacing: 0
                                Text { text: Qt.formatTime(clock.date, bar.vertical ? "hh" : "hh:mm"); color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { visible: bar.vertical; text: Qt.formatTime(clock.date, "mm"); color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { text: Qt.formatDate(clock.date, bar.vertical ? "ddd" : "ddd dd MMM"); color: Theme.isDark ? Qt.lighter(Theme.color3,1.5) : Qt.darker(Theme.color3, 2.8); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                                Text { visible: bar.vertical; text: Qt.formatDate(clock.date, "dd"); color: Theme.isDark ? Qt.lighter(Theme.color3,1.5) : Qt.darker(Theme.color3, 2.8); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                            }
                        }
                    }

                    // ---------------- stopwatch ----------------
                    BarSlot {
                        id: stopwatchSlot; owner: bar; slotId: "stopwatch"
                        TrayReveal {
                            cfg: bar.cfg
                            id: stopwatchReveal
                            active: StopwatchService.active
                            TimeChip {
                                cfg: bar.cfg
                                text: StopwatchService.shortText
                                templateText: StopwatchService.shortText.length > 5 ? "00:00:00" : "00:00"
                                onActivated: { stopwatchPopup.toggle() }
                            }
                        }
                    }

                    // ---------------- timer ----------------
                    BarSlot {
                        id: timerSlot; owner: bar; slotId: "timer"
                        TrayReveal {
                            cfg: bar.cfg
                            id: timerReveal
                            active: TimerService.active
                            TimeChip {
                                cfg: bar.cfg
                                chip: true
                                text: TimerService.shortText
                                templateText: TimerService.shortText.length > 5 ? "00:00:00" : "00:00"
                                onActivated: { timerPopup.toggle() }
                            }
                        }
                    }

                    // ---------------- workspaces 0-9 ----------------
                    BarSlot {
                        id: workspacesSlot; owner: bar; slotId: "workspaces"
                        WorkspacesTray { cfg: bar.cfg }
                    }

                    // ---------------- action buttons ----------------
                    BarSlot {
                        id: launcherSlot; owner: bar; slotId: "launcher"
                        ActionButton { cfg: bar.cfg; action: "launcher" }
                    }

                    BarSlot {
                        id: settingsSlot; owner: bar; slotId: "settings"
                        ActionButton { cfg: bar.cfg; action: "settings" }
                    }

                    BarSlot {
                        id: lockSlot; owner: bar; slotId: "lock"
                        ActionButton { cfg: bar.cfg; action: "lock" }
                    }

                    BarSlot {
                        id: commandsSlot; owner: bar; slotId: "commands"
                        ActionButton { cfg: bar.cfg; action: "commands" }
                    }

                    BarSlot {
                        id: shortcutsSlot; owner: bar; slotId: "shortcuts"
                        ActionButton { cfg: bar.cfg; action: "shortcuts" }
                    }

                    BarSlot {
                        id: overviewSlot; owner: bar; slotId: "overview"
                        ActionButton { cfg: bar.cfg; action: "overview" }
                    }

                    BarSlot {
                        id: displaySlot; owner: bar; slotId: "display"
                        ActionButton { cfg: bar.cfg; action: "display" }
                    }

                    BarSlot {
                        id: scheduleSlot; owner: bar; slotId: "schedule"
                        ActionButton { cfg: bar.cfg; action: "schedule" }
                    }

                    // ---------------- bell ----------------
                    BarSlot {
                        id: bellSlot; owner: bar; slotId: "bell"
                        ControlIcon {
                            cfg: bar.cfg
                            id: bellIcon; iconId: "bell"; iconSource: bar.iconDir + "bell.svg"
                            onActivated: { notificationsPopup.toggle() }
                            Rectangle {
                                width: 14; height: 14; radius: 7; color: Theme.color1; anchors { top: parent.top; right: parent.right }
                                visible: Notifications.notificationCount > 0
                                Text { text: Notifications.notificationCount; color: "white"; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(8); font.bold: true; anchors.centerIn: parent }
                            }
                        }
                    }
                }
            }
        }

        Connections {
            target: MusicPlayerService
            function onTitleChanged() { musicReveal.pulse() }
        }

        SystemClock { id: clock; precision: SystemClock.Minutes }

        HoverHandler {
            id: barHoverHandler
            onHoveredChanged: bar.pointerUpdate()
        }

        PopupTracking {
            id: popupTracking
            bar: bar; barClip: barClip; content: barContent
        }

        ParallelAnimation {
            id: barEntranceAnim
            NumberAnimation { target: barContent; property: "opacity"; to: 1; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut }
            NumberAnimation { target: barContent; property: "entranceBlur"; to: 0; duration: Animations.slideBlurDuration; easing.type: Animations.slideBlurEasingOut }
            onStopped: { barContent.entranceBlurActive = false }
        }

        SequentialAnimation {
            id: themeBlurAnim
            PropertyAction { target: barContent; property: "themeBlurActive"; value: true }
            NumberAnimation { target: barContent; property: "themeBlurProgress"; from: 0; to: 1; duration: Animations.wallpaperCrossfadeDuration; easing.type: Animations.wallpaperCrossfadeEasing }
            PropertyAction { target: barContent; property: "themeBlurActive"; value: false }
            PropertyAction { target: barContent; property: "themeBlurProgress"; value: 0 }
        }

        function wirePopup(p, place) {
            p.exclusionMode = ExclusionMode.Ignore
            p.anchors.top = Qt.binding(function () { return popupTracking.anchorTop })
            p.anchors.bottom = Qt.binding(function () { return popupTracking.anchorBottom })
            p.anchors.left = Qt.binding(function () { return popupTracking.anchorLeft })
            p.anchors.right = Qt.binding(function () { return popupTracking.anchorRight })
            p.margins.top = Qt.binding(function () { return place.marginTop })
            p.margins.bottom = Qt.binding(function () { return place.marginBottom })
            p.margins.left = Qt.binding(function () { return place.marginLeft })
            p.margins.right = Qt.binding(function () { return place.marginRight })
        }

        Component.onCompleted: {
            var elapsed = Date.now() - barCreationStart
            if (elapsed > 400) {
                barContent.opacity = 0
                barContent.entranceBlur = Animations.slideBlurVerticalLength
                barContent.entranceBlurActive = true
                barEntranceAnim.start()
            }
            wirePopup(volumePopup, volumePlace)
            wirePopup(batteryPopup, batteryPlace)
            wirePopup(notificationsPopup, notificationsPlace)
            wirePopup(wifiPopup, wifiPlace)
            wirePopup(bluetoothPopup, bluetoothPlace)
            wirePopup(dateTimePopup, dateTimePlace)
            wirePopup(timerPopup, timerPlace)
            wirePopup(stopwatchPopup, stopwatchPlace)
            wirePopup(musicPopup, musicPlace)
            Qt.callLater(warmupPopups)
        }

        function warmupPopups() {
            var popups = [volumePopup, batteryPopup, notificationsPopup, wifiPopup, bluetoothPopup, dateTimePopup, musicPopup, timerPopup, stopwatchPopup]
            for (var i = 0; i < popups.length; i++) {
                var p = popups[i]
                p.visible = true; p.visible = false
                if (p.glassPanel) { p.glassPanel.entranceProgress = 1; p.glassPanel.exitProgress = 1 }
            }
        }

        Connections {
            target: TransitionSync
            function onTransition() { themeBlurAnim.restart() }
        }

        VolumePopup { id: volumePopup; tracking: popupTracking }
        BatteryPopup { id: batteryPopup; tracking: popupTracking }
        NotificationsPopup { id: notificationsPopup; tracking: popupTracking }
        WifiPopup { id: wifiPopup; tracking: popupTracking }
        BluetoothPopup { id: bluetoothPopup; tracking: popupTracking }
        DateTimePopup { id: dateTimePopup; tracking: popupTracking }
        ClockPagePopup {
            id: timerPopup
            pageSource: "../Clock/TimerPage.qml"
            pageActive: TimerService.active
            tracking: popupTracking
        }
        ClockPagePopup {
            id: stopwatchPopup
            pageSource: "../Clock/StopwatchPage.qml"
            pageActive: StopwatchService.active
            tracking: popupTracking
        }
        MusicPopup { id: musicPopup; tracking: popupTracking }

        PopupPlacement { id: volumePlace; tracking: popupTracking; popup: volumePopup; anchorItem: volumeSlot }
        PopupPlacement { id: batteryPlace; tracking: popupTracking; popup: batteryPopup; anchorItem: batterySlot }
        PopupPlacement { id: notificationsPlace; tracking: popupTracking; popup: notificationsPopup; anchorItem: bellSlot }
        PopupPlacement { id: wifiPlace; tracking: popupTracking; popup: wifiPopup; anchorItem: wifiSlot }
        PopupPlacement { id: bluetoothPlace; tracking: popupTracking; popup: bluetoothPopup; anchorItem: btSlot }
        PopupPlacement { id: dateTimePlace; tracking: popupTracking; popup: dateTimePopup; anchorItem: clockSlot }
        PopupPlacement { id: timerPlace; tracking: popupTracking; popup: timerPopup; anchorItem: timerSlot }
        PopupPlacement { id: stopwatchPlace; tracking: popupTracking; popup: stopwatchPopup; anchorItem: stopwatchSlot }
        PopupPlacement { id: musicPlace; tracking: popupTracking; popup: musicPopup; anchorItem: musicSlot }
    }
}
