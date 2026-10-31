import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import "../Services"
import "../Widgets"
import "../Theme"
import "../Bar/modules"

// Shell settings. Left column: categories. Right column: that category's
// attributes. Open with:  qs ipc call settings toggle   (bound to Super+Shift+A)
//
// To add a category (e.g. Toast): append to `categories`, add a Component
// below, and return it from pageFor().
PanelWindow {
    id: popup

    property bool shown: false
    property string currentCategory: "bar"
    readonly property int fadeMs: Animations.panelFadeDuration

    // ---- this window's own scale (Settings > Popups > General > Settings window) ----
    readonly property real baseW: 854
    readonly property real baseH: 684
    readonly property real wantScale: PopupSettings.scaleOf("settings")
    // biggest scale that still fits on this screen
    readonly property real fitScale: popup.screen
    ? Math.min((popup.screen.width - 8) / baseW, (popup.screen.height - 8) / baseH) : 1
    // The scale in use. It follows the slider only after you let go of it, so the window never changes
    // size under your pointer while you are still dragging.
    property real uiScale: 1
    // true for a moment after a resize: the focus grab may drop while the surface is re-configured, and
    // that must not close the window (see ClickAwayCloser below)
    property bool _resizeGuard: false
    property bool _grabOn: true
    property bool _regrabbing: false

    function _applyScale() {
        if (PopupSettings.scaleDragging) { scaleTimer.restart(); return }
        const s = Math.max(0.5, Math.min(popup.wantScale, popup.fitScale))
        if (Math.abs(s - popup.uiScale) < 0.001) return
            popup._resizeGuard = true
            guardTimer.restart()
            popup.uiScale = s
    }
    function _regrab() {
        popup._regrabbing = true
        popup._grabOn = false
        regrabTimer.restart()
    }
    onWantScaleChanged: scaleTimer.restart()
    onFitScaleChanged: scaleTimer.restart()
    Component.onCompleted: popup._applyScale()
    Timer { id: scaleTimer; interval: 450; onTriggered: popup._applyScale() }
    Timer { id: guardTimer; interval: 1500; onTriggered: popup._resizeGuard = false }
    Timer { id: regrabTimer; interval: 60; onTriggered: { popup._grabOn = true; popup._regrabbing = false } }
    Connections {
        target: PopupSettings
        function onScaleDraggingChanged() { if (!PopupSettings.scaleDragging) scaleTimer.restart() }
    }

    // Battery only exists on machines that have one
    readonly property var categories: allCategories.filter(function (c) { return c.id !== "battery" || BatteryInfo.hasBattery })
    readonly property var allCategories: [
        { id: "bar", label: "Bar" },
        { id: "theme", label: "Theme" },
        { id: "toast", label: "Toast" },
        { id: "keybinds", label: "Keybindings" },
        { id: "font", label: "Font" },
        { id: "display", label: "Display" },
        { id: "icons", label: "Icons" },
        { id: "popups", label: "Popups" },
        { id: "lock", label: "Lock screen" },
        { id: "cursor", label: "Cursor" },
        { id: "sounds", label: "Sounds" },
        { id: "battery", label: "Battery" }
    ]

    readonly property var iconNames: ({
        "power": "Power", "music": "Music", "apps": "App tray", "wifi": "Wi-Fi",
        "bluetooth": "Bluetooth", "volume": "Volume", "battery": "Battery",
        "clock": "Clock", "stopwatch": "Stopwatch", "timer": "Timer", "bell": "Notifications",
        "launcher": "App launcher", "settings": "Settings", "lock": "Lock", "commands": "Commands",
        "shortcuts": "Shortcuts", "overview": "Overview", "display": "Display toggle", "schedule": "Power schedule",
        "workspaces": "Workspaces 0-9"
    })

    function pageFor(id) {
        if (id === "bar") return barTabsPage
            if (id === "theme") return themePage
                if (id === "toast") return toastPage
                    if (id === "keybinds") return keybindsPage
                        if (id === "font") return fontPage
                            if (id === "display") return displayPage
                                if (id === "icons") return iconsPage
                                    if (id === "popups") return popupsPage
                                        if (id === "lock") return lockTabsPage
                                            if (id === "cursor") return cursorPage
                                                if (id === "sounds") return soundsPage
                                                    if (id === "battery") return batteryPage
                                                        return null
    }

    color: "transparent"
    exclusiveZone: 0
    // No anchors: the compositor centres the window on the screen.
    // 12px margin on every side (room for the spring overshoot), same as MusicPickerPopup.
    implicitWidth: baseW * uiScale
    implicitHeight: baseH * uiScale

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:settings"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    // Same scheme as MusicPickerPopup: after a short startup delay the window
    // stays mapped, fully transparent and input-transparent (empty mask), and
    // open/close only fade + spring-scale the panel -- no window teardown, no
    // GL context rebuild per open. The page tree itself is only built while
    // the popup is open (or fading out) so nothing idles in RAM.
    property bool keepMapped: true
    property bool _ready: false
    property bool _forceMap: false
    property bool _closing: false
    visible: shown || _forceMap || (keepMapped && _ready)
    mask: shown ? null : emptyMask
    Region { id: emptyMask }

    function open() {
        hideTimer.stop()
        _closing = false
        if (popup.visible) {
            shown = true
        } else {
            // Opened before the startup map: let the surface commit its first
            // frame before the fade starts.
            _forceMap = true
            showTimer.restart()
        }
    }
    function close() {
        showTimer.stop()
        shown = false
        _closing = true
        hideTimer.restart()
    }
    function toggle() { shown ? close() : open() }

    Timer { id: readyTimer; interval: 7500; running: true; onTriggered: popup._ready = true }
    Timer { id: showTimer; interval: 32; onTriggered: popup.shown = true }
    Timer {
        id: hideTimer
        interval: popup.fadeMs + 60
        onTriggered: { popup._forceMap = false; popup._closing = false }
    }

    ClickAwayCloser {
        targetWindows: [popup]
        active: popup.shown && popup._grabOn
        onDismissed: {
            // The grab can drop by itself while the window is being resized: take it again, do not close.
            if (popup._resizeGuard || popup._regrabbing) {
                if (!popup._regrabbing && popup.shown) popup._regrab()
            } else {
                popup.close()
            }
        }
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { popup.toggle() }
        function open(): void { popup.open() }
        function close(): void { popup.close() }
    }

    // ---------------- reusable bits ----------------
    component SectionLabel: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        Layout.preferredWidth: 130
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: 6
    }

    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    // Full preview: a mock screen with a dummy of the REAL bar on it (same
    // glass panel, icons, order, scale, radius, fill behaviour). With auto-hide
    // ON it is fully static (changes snap, nothing slides or eases). With
    // auto-hide OFF (docked) size changes are allowed to animate.
    component BarPreview: Item {
        id: pv
        implicitHeight: 314

        readonly property string dir: "file://" + Quickshell.env("HOME") + "/.config/icons/"
        readonly property string edge: BarSettings.edge
        readonly property bool vert: BarSettings.vertical
        readonly property bool docked: !BarSettings.autohide
        readonly property bool fill: BarSettings.fillScreen || docked
        readonly property real sc: BarSettings.scale
        readonly property real baseT: BarSettings.thickness
        readonly property real thick: baseT * sc
        readonly property real edgeGap: docked ? 0 : Theme.gapSm

        // Virtual 1280x720 screen shown on a 540x304 mock (bigger bar than before).
        readonly property real vw: 1280
        readonly property real vh: 720
        readonly property real f: mock.width / vw
        readonly property real uLen: vert ? vh : vw
        readonly property real winLen: fill ? uLen : uLen - Theme.gapMd * 1.5

        // Same math as the real bar: fill spans the screen, fit hugs the content.
        readonly property real naturalLen: vert ? lay.implicitHeight : lay.implicitWidth
        readonly property real panelLen: fill ? winLen
        : Math.min((naturalLen + Theme.gapMd * 2) * sc, winLen)
        readonly property real contentMain: fill
        ? Math.max(0, panelLen / sc - Theme.gapMd * 2)
        : naturalLen

        function compFor(id) {
            switch (id) {
                case "power": return cPower
                case "music": return cMusic
                case "apps": return cApps
                case "wifi": return cWifi
                case "bluetooth": return cBt
                case "volume": return cVol
                case "battery": return cBat
                case "clock": return cClock
                case "stopwatch": return cStop
                case "timer": return cTimer
                case "bell": return cBell
                case "workspaces": return cWs
            }
            return BarSettings.extraIds.indexOf(id) >= 0 ? cAction : null
        }

        Rectangle {
            id: mock
            width: 540
            height: width * pv.vh / pv.vw
            anchors.centerIn: parent
            radius: 8
            color: Theme.pillOffBg
            border.width: 1
            border.color: Theme.borderMuted
            clip: true

            // Positions the (scaled) bar on its edge, exactly like the real window.
            Item {
                id: place
                width: dummy.width * pv.f
                height: dummy.height * pv.f
                x: pv.edge === "left" ? pv.edgeGap * pv.f
                : (pv.edge === "right" ? mock.width - width - pv.edgeGap * pv.f
                : (mock.width - width) / 2)
                y: pv.edge === "top" ? pv.edgeGap * pv.f
                : (pv.edge === "bottom" ? mock.height - height - pv.edgeGap * pv.f
                : (mock.height - height) / 2)

                Item {
                    id: dummy
                    anchors.centerIn: parent
                    width: pv.vert ? pv.thick : pv.panelLen
                    height: pv.vert ? pv.panelLen : pv.thick
                    scale: pv.f

                    Behavior on width { enabled: pv.docked; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on height { enabled: pv.docked; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

                    GlassPanel {
                        role: "bar"
                        anchors.fill: parent
                        radius: pv.docked ? 0 : (pv.thick / 2) * BarSettings.roundnessPct / 100

                        Item {
                            anchors.centerIn: parent
                            width: pv.vert ? pv.baseT : pv.contentMain
                            height: pv.vert ? pv.contentMain : pv.baseT
                            scale: pv.sc

                            GridLayout {
                                id: lay
                                anchors.fill: parent
                                columns: pv.vert ? 1 : Math.max(1, BarSettings.order.length)
                                rowSpacing: 2
                                columnSpacing: 2
                                Repeater {
                                    model: BarSettings.order
                                    delegate: Loader {
                                        required property string modelData
                                        Layout.alignment: Qt.AlignCenter
                                        Layout.fillWidth: modelData === "apps" && !pv.vert && pv.fill
                                        Layout.fillHeight: modelData === "apps" && pv.vert && pv.fill
                                        sourceComponent: pv.compFor(modelData)
                                        onLoaded: { if (item && item.action !== undefined) item.action = modelData }
                                    }
                                }
                            }
                        }
                    }

                    // Swallow hover/clicks: it is only a picture.
                    MouseArea { anchors.fill: parent }
                }
            }
        }

        Component { id: cPower; ControlIcon { iconId: "power"; iconSource: pv.dir + "power-btn.svg"; iconSize: 16 } }
        // the optional buttons (launcher, lock, ...): the real button, only a picture here
        Component { id: cAction; ActionButton { } }
        Component {
            id: cMusic
            ControlIcon {
                iconId: "music"
                iconSource: pv.vert ? pv.dir + "music-placeholder.png" : ""
                text: pv.vert ? "" : "Now playing"
            }
        }
        // App tray: grows to take the free space in edge-to-edge mode, like the real one.
        Component {
            id: cApps
            Item {
                implicitWidth: pv.vert ? pv.baseT : appsGrid.implicitWidth + 6
                implicitHeight: pv.vert ? appsGrid.implicitHeight + 6 : pv.baseT
                Grid {
                    id: appsGrid
                    anchors.left: pv.vert ? undefined : parent.left
                    anchors.top: pv.vert ? parent.top : undefined
                    anchors.horizontalCenter: pv.vert ? parent.horizontalCenter : undefined
                    anchors.verticalCenter: pv.vert ? undefined : parent.verticalCenter
                    anchors.leftMargin: 3
                    anchors.topMargin: 3
                    columns: pv.vert ? 1 : 4
                    spacing: 4
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            width: 30; height: 30
                            radius: Theme.radiusSm
                            color: Theme.hoverBg
                            Rectangle {
                                anchors.centerIn: parent
                                width: 16; height: 16; radius: 3
                                color: Theme.foreground
                                opacity: 0.55
                            }
                        }
                    }
                }
            }
        }
        Component { id: cWifi; ControlIcon { iconId: "wifi"; iconSource: pv.dir + "wifion.svg" } }
        Component { id: cBt; ControlIcon { iconId: "bluetooth"; iconSource: pv.dir + "bluetooth-icon.svg" } }
        Component { id: cVol; ControlIcon { iconId: "volume"; iconSource: pv.dir + "sound.svg" } }
        Component {
            id: cBat
            ControlIcon {
                iconId: "battery-high"
                iconSource: pv.dir + "high-battery.svg"
                iconSize: 20
                text: "80%"
            }
        }
        Component {
            id: cClock
            Item {
                implicitWidth: pv.vert ? pv.baseT : clockCol.implicitWidth + 16
                implicitHeight: pv.vert ? clockCol.implicitHeight + 12 : pv.baseT
                Column {
                    id: clockCol
                    anchors.centerIn: parent
                    spacing: 0
                    Text { text: pv.vert ? "12" : "12:00"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { visible: pv.vert; text: "00"; color: Theme.foreground; font.family: Theme.fontFamily; font.pixelSize: Theme.fs(11); font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: pv.vert ? "Sat" : "Sat 17 Oct"; color: Theme.isDark ? Qt.lighter(Theme.color3, 1.5) : Qt.darker(Theme.color3, 2.8); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { visible: pv.vert; text: "17"; color: Theme.isDark ? Qt.lighter(Theme.color3, 1.5) : Qt.darker(Theme.color3, 2.8); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeXs; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
        }
        Component { id: cStop; TimeChip { text: "00:00"; templateText: "00:00" } }
        Component { id: cTimer; TimeChip { chip: true; text: "05:00"; templateText: "00:00" } }
        Component { id: cBell; ControlIcon { iconId: "bell"; iconSource: pv.dir + "bell.svg" } }
        Component { id: cWs; WorkspacesTray { } }
    }

    // Mock screen showing where notification toasts will appear (a stack of
    // three cards, like the real stacked look). Static: placement changes snap.
    component ToastPreview: Item {
        id: tp
        implicitHeight: 314

        readonly property real vw: 1280
        readonly property real vh: 720
        readonly property real f: tmock.width / vw
        readonly property real cardW: 220
        readonly property real cardH: 76
        readonly property real side: 14
        readonly property real edgeY: 5

        Rectangle {
            id: tmock
            width: 540
            height: width * tp.vh / tp.vw
            anchors.centerIn: parent
            radius: 8
            color: Theme.pillOffBg
            border.width: 1
            border.color: Theme.borderMuted
            clip: true

            Repeater {
                model: 3   // 0 = oldest (back) ... 2 = front card
                delegate: Rectangle {
                    required property int index
                    readonly property int depth: 2 - index
                    readonly property real cs: tp.f * (1 - depth * 0.045)
                    readonly property real fullW: tp.cardW * tp.f
                    readonly property real fullH: tp.cardH * tp.f
                    readonly property real leftX: ToastSettings.atLeft ? tp.side * tp.f
                    : (ToastSettings.atRight ? tmock.width - fullW - tp.side * tp.f
                    : (tmock.width - fullW) / 2)
                    readonly property real frontY: ToastSettings.atBottom
                    ? tmock.height - tp.edgeY * tp.f - fullH
                    : tp.edgeY * tp.f
                    readonly property real topY: ToastSettings.atBottom
                    ? frontY - depth * 8 * tp.f
                    : frontY + depth * 8 * tp.f

                    width: tp.cardW * cs
                    height: tp.cardH * cs
                    x: leftX + (fullW - width) / 2
                    y: topY + (fullH - height) / 2
                    z: -depth
                    radius: Theme.radiusMd * cs
                    color: Theme.popupBg
                    opacity: depth === 0 ? 1 : Math.max(0.22, 1 - depth * 0.22)
                    border.width: 1
                    border.color: Theme.borderMuted

                    Column {
                        visible: depth === 0
                        anchors.centerIn: parent
                        spacing: 6 * cs
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 110 * cs; height: 8 * cs; radius: height / 2; color: Theme.foreground; opacity: 0.85 }
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 170 * cs; height: 6 * cs; radius: height / 2; color: Theme.foreground; opacity: 0.45 }
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 130 * cs; height: 6 * cs; radius: height / 2; color: Theme.foreground; opacity: 0.45 }
                    }
                }
            }
        }
    }

    // ---------------- window content ----------------
    // Everything lays out at its normal 854 x 684 size inside `unscaled`, which is scaled from the
    // top-left corner to the window's real size.
    Item {
        id: scaler
        anchors.fill: parent

        Item {
            id: unscaled
            property string popupId: "settings"     // the buttons in here use Settings > Popups > Button corner radius > Settings window
            width: scaler.width / popup.uiScale
            height: scaler.height / popup.uiScale
            scale: popup.uiScale
            transformOrigin: Item.TopLeft

            Item {
                id: content
                anchors.fill: parent
                anchors.margins: 12
                focus: popup.shown

                // Same motion as MusicPickerPopup / WorkspaceOverview: fade + small
                // spring scale on one permanent texture.
                opacity: popup.shown ? 1 : 0
                scale: popup.shown ? 1 : 0.94
                layer.enabled: true
                layer.smooth: true
                Behavior on opacity { NumberAnimation { duration: popup.fadeMs } }
                Behavior on scale {
                    SpringAnimation {
                        spring: Animations.panelSlideSpring
                        damping: Animations.panelSlideDamping
                        mass: Animations.panelSlideMass
                    }
                }

                // The active page gets first refusal (the Font page uses arrows /
                // typing); anything it leaves unhandled falls through, and Esc closes.
                Keys.onPressed: (event) => {
                    const pg = pageLoader.item
                    if (pg && pg.handleKey && pg.handleKey(event)) { event.accepted = true; return }
                    if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true }
                }

                GlassPanel {
                    anchors.fill: parent
                    radius: PopupSettings.radiusOf("settings")
                    showBorder: false      // drawn by the border item below `content` (outside this layer)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // ---- left column: categories ----
                        ColumnLayout {
                            Layout.preferredWidth: 160
                            Layout.maximumWidth: 160
                            Layout.fillHeight: true
                            spacing: 6

                            GradientText {
                                text: "Settings"
                                font.family: Theme.fontFamily
                                font.bold: true
                                font.pixelSize: Theme.fontSizeLg
                                Layout.bottomMargin: 4
                            }

                            Repeater {
                                model: popup.categories
                                delegate: GlassButton {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    implicitHeight: 34
                                    text: modelData.label
                                    active: popup.currentCategory === modelData.id
                                    onClicked: popup.currentCategory = modelData.id
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }

                        Rectangle { Layout.fillHeight: true; width: 1; color: Theme.borderMuted }

                        // ---- right column: fixed header + page ----
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 10

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: headerTitle.implicitHeight   // the button never changes the header's height

                                GradientText {
                                    id: headerTitle
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: {
                                        for (var i = 0; i < popup.categories.length; i++)
                                            if (popup.categories[i].id === popup.currentCategory) return popup.categories[i].label
                                                return ""
                                    }
                                    font.family: Theme.fontFamily
                                    font.bold: true
                                    font.pixelSize: Theme.fontSizeLg
                                }

                                // Theme page: Create sits at the right of the header (only on the tile list,
                                // not while a theme is being edited / previewed)
                                GlassButton {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: popup.currentCategory === "theme" && pageLoader.item !== null
                                    && pageLoader.item.view === "main"
                                    text: "Create"
                                    onClicked: pageLoader.item.startNew()
                                }
                            }

                            Loader {
                                id: pageLoader
                                active: popup.shown || popup._closing
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                sourceComponent: popup.pageFor(popup.currentCategory)
                            }
                        }
                    }
                }
            }

            // Border: on / off, thickness, colour, effects and radius all from Settings > Theme > Border.
            // It sits NEXT to `content`, not inside it: `content` is rendered as one texture (layer.enabled)
            // and a texture cuts off everything drawn outside the panel's edge -- where the wavy streaks and
            // the x / o marks go. This item copies content's fade + scale so it moves with it.
            Item {
                anchors.fill: content
                opacity: content.opacity
                scale: content.scale
                PanelBorder {
                    readonly property real r: BorderSettings.radiusFor(PopupSettings.radiusOf("settings"))
                    tl: r; tr: r; bl: r; br: r
                }
            }
        }   // unscaled
    }   // scaler

    // ============================================================
    // BAR PAGE
    // ============================================================
    // Bar category: the classic settings, and Presets (your own bar layouts)
    Component {
        id: barTabsPage

        ColumnLayout {
            spacing: 8
            property string tab: "bar"
            Row {
                spacing: 6
                GlassButton { text: "Bar"; active: parent.parent.tab === "bar"; onClicked: parent.parent.tab = "bar" }
                GlassButton { text: "Presets"; active: parent.parent.tab === "presets"; onClicked: parent.parent.tab = "presets" }
            }
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: parent.tab === "presets" ? barPresetsPage : barPage
            }
        }
    }
    Component { id: barPresetsPage; BarPresetsPage {} }

    // Lock screen category: layouts (with a live preview) and the lock screen's icons
    Component {
        id: lockTabsPage

        ColumnLayout {
            spacing: 8
            property string tab: "layout"
            Row {
                spacing: 6
                GlassButton { text: "Layout"; active: parent.parent.tab === "layout"; onClicked: parent.parent.tab = "layout" }
                GlassButton { text: "Icons"; active: parent.parent.tab === "icons"; onClicked: parent.parent.tab = "icons" }
            }
            Loader {
                Layout.fillWidth: true
                Layout.fillHeight: true
                sourceComponent: parent.tab === "icons" ? lockIconsPage : lockLayoutPage
            }
        }
    }
    Component { id: lockLayoutPage; LockScreenPage {} }
    Component { id: cursorPage; CursorSettingsPage {} }
    Component { id: soundsPage; SoundsSettingsPage {} }
    Component { id: batteryPage; BatterySettingsPage {} }
    Component { id: lockIconsPage; IconsSettingsPage { group: "lock" } }

    Component {
        id: barPage

        ColumnLayout {
            spacing: 8

            // A preset from Settings > Bar > Presets is in use: these classic settings do not apply
            readonly property var activePreset: BarPresets.presetById(BarPresets.active)
            readonly property bool presetInUse: activePreset !== null && activePreset !== undefined

            Text {
                visible: parent.presetInUse
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                text: parent.presetInUse
                ? "The preset \"" + parent.activePreset.name + "\" is being used, so the settings below do not apply. Choose Default in the Presets tab to use them again."
                : ""
            }

            // Fixed (does not scroll)
            BarPreview { visible: !parent.presetInUse; Layout.fillWidth: true }
            BarPresetPreview {
                visible: parent.presetInUse
                Layout.fillWidth: true
                bars: parent.presetInUse ? parent.activePreset.bars : []
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: -14; Layout.rightMargin: -14   // horizontal gutter only (hover-scaled buttons); top/bottom clip at the real edge
                clip: true
                contentWidth: width
                contentHeight: col.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds
                enabled: !parent.presetInUse
                opacity: parent.presetInUse ? 0.35 : 1

                ColumnLayout {
                    id: col
                    x: 14; y: 4
                    width: flick.width - 28
                    spacing: 16

                    // ---- position ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Position" }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: [
                                    { label: "Bottom", value: "bottom-center" },
                                    { label: "Top", value: "top-center" },
                                    { label: "Left", value: "left-center" },
                                    { label: "Right", value: "right-center" }
                                ]
                                delegate: GlassButton {
                                    required property var modelData
                                    text: modelData.label
                                    active: BarSettings.position === modelData.value
                                    onClicked: BarSettings.setPosition(modelData.value)
                                }
                            }
                        }
                    }

                    // ---- autohide ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Auto-hide" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Row {
                                spacing: 6
                                GlassButton { text: "On"; active: BarSettings.autohide; onClicked: BarSettings.setAutohide(true) }
                                GlassButton { text: "Off"; active: !BarSettings.autohide; onClicked: BarSettings.setAutohide(false) }
                            }
                            Hint { text: "On: floating pill that hides until hovered. Off: bar is docked flush to the screen edge, full length, and reserves its space." }
                        }
                    }

                    // ---- width ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Size" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Row {
                                spacing: 6
                                GlassButton { text: "Fit to content"; disabled: !BarSettings.autohide; active: !BarSettings.fillScreen; onClicked: if (BarSettings.autohide) BarSettings.setFill(false) }
                                GlassButton { text: "Edge to edge"; disabled: !BarSettings.autohide; active: BarSettings.fillScreen; onClicked: if (BarSettings.autohide) BarSettings.setFill(true) }
                            }
                            Hint { visible: !BarSettings.autohide; text: "Only applies while auto-hide is on. A docked bar is always edge to edge." }
                        }
                    }

                    // ---- scale ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Scale" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                GlassSlider {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    min: 70
                                    max: 160
                                    value: BarSettings.scalePct
                                    onValueCommitted: (v) => BarSettings.setScale(v)
                                }
                                Text {
                                    text: BarSettings.scalePct + "%"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    Layout.preferredWidth: 44
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                            Hint { text: "Scales the whole bar: height/width, icons and text." }
                        }
                    }

                    // ---- corner radius (floating pill only) ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        opacity: BarSettings.autohide ? 1 : 0.4
                        SectionLabel { text: "Corner radius" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10
                                GlassSlider {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    enabled: BarSettings.autohide
                                    min: 0
                                    max: 100
                                    value: BarSettings.roundnessPct
                                    onValueCommitted: (v) => { if (BarSettings.autohide) BarSettings.setRoundness(v) }
                                }
                                Text {
                                    text: BarSettings.roundnessPct + "%"
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    Layout.preferredWidth: 44
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                            Hint { text: BarSettings.autohide ? "0% = square corners, 100% = full pill." : "Only applies while auto-hide is on. A docked bar is always square." }
                        }
                    }

                    // ---- extra buttons (the same optional buttons a preset bar can hold) ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Extra buttons" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Hint { text: "Optional buttons for the bar. A button you switch on joins the end of the bar; drag it where you want it in Icon order below. Both previews update, and the spacing follows the bar's own rules, edge to edge or fitted to its content." }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: BarSettings.extraIds
                                    delegate: GlassButton {
                                        required property string modelData
                                        text: popup.iconNames[modelData] ?? modelData
                                        active: BarSettings.extras.indexOf(modelData) >= 0
                                        onClicked: BarSettings.setExtra(modelData, !active)
                                    }
                                }
                            }
                        }
                    }

                    // ---- icon order (drag the icons on a mock bar) ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "Icon order" }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Hint { text: "Drag the icons to reorder them. This strip is a fixed-size stand-in for the bar (scale does not affect it); the preview above updates when you drop." }

                            Item {
                                id: orderBox
                                Layout.fillWidth: true
                                Layout.preferredHeight: 58

                                readonly property string dir: "file://" + Quickshell.env("HOME") + "/.config/icons/"
                                readonly property int n: BarSettings.activeIds.length
                                readonly property real pad: 8
                                readonly property real gap: 4
                                readonly property real tile: Math.max(24, Math.min(42, (width - pad * 2 - gap * (n - 1)) / n))
                                readonly property real step: tile + gap

                                // Working copy while dragging; committed on release.
                                property var working: BarSettings.order.slice()
                                property string dragId: ""
                                property string hoverId: ""

                                function iconFile(id) {
                                    switch (id) {
                                        case "power": return "power-btn.svg"
                                        case "wifi": return "wifion.svg"
                                        case "bluetooth": return "bluetooth-icon.svg"
                                        case "volume": return "sound.svg"
                                        case "battery": return "high-battery.svg"
                                        case "bell": return "bell.svg"
                                        case "settings": return "settings.svg"
                                    }
                                    return ""
                                }
                                function textFor(id) {
                                    switch (id) {
                                        case "music": return "♪"
                                        case "clock": return "12:00"
                                        case "stopwatch": return "00:00"
                                        case "timer": return "05:00"
                                        case "launcher": return "App"
                                        case "lock": return "Lck"
                                        case "commands": return "Cmd"
                                        case "shortcuts": return "Key"
                                        case "overview": return "Ovw"
                                        case "display": return "Dsp"
                                        case "schedule": return "Sch"
                                        case "workspaces": return "0-9"
                                    }
                                    return ""
                                }

                                Connections {
                                    target: BarSettings
                                    function onOrderChanged() {
                                        if (orderBox.dragId === "") orderBox.working = BarSettings.order.slice()
                                    }
                                }

                                GlassPanel {
                                    role: "bar"
                                    anchors.fill: parent
                                    radius: height / 2
                                }

                                Item {
                                    id: tiles
                                    x: orderBox.pad
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: orderBox.n * orderBox.step - orderBox.gap
                                    height: orderBox.tile

                                    Repeater {
                                        model: BarSettings.activeIds
                                        delegate: Rectangle {
                                            id: tileItem
                                            required property string modelData
                                            readonly property int slot: orderBox.working.indexOf(modelData)
                                            readonly property bool dragging: orderBox.dragId === modelData
                                            readonly property string iconFile: orderBox.iconFile(modelData)
                                            readonly property string label: orderBox.textFor(modelData)
                                            property real dragX: 0

                                            width: orderBox.tile
                                            height: orderBox.tile
                                            x: dragging ? dragX : slot * orderBox.step
                                            z: dragging ? 10 : 1
                                            scale: dragging ? 1.1 : 1
                                            opacity: dragging ? 0.92 : 1
                                            radius: Theme.radiusSm
                                            color: dragging ? Theme.hoverBgStrong
                                            : (orderBox.hoverId === modelData ? Theme.hoverBg : "transparent")
                                            border.width: dragging ? 1 : 0
                                            border.color: Theme.accentActive

                                            Behavior on x { enabled: !tileItem.dragging; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                            Behavior on scale { NumberAnimation { duration: 120 } }

                                            // icon
                                            Image {
                                                visible: tileItem.iconFile !== ""
                                                anchors.centerIn: parent
                                                source: tileItem.iconFile !== "" ? orderBox.dir + tileItem.iconFile : ""
                                                width: 18
                                                height: 18
                                                sourceSize.width: Math.round(18 * Screen.devicePixelRatio)
                                                sourceSize.height: Math.round(18 * Screen.devicePixelRatio)
                                                smooth: true
                                                layer.enabled: visible
                                                layer.smooth: true
                                                layer.effect: ColorOverlay { color: Theme.iconColor }
                                            }
                                            // text glyphs (music / clock / stopwatch / timer)
                                            Rectangle {
                                                visible: tileItem.label !== ""
                                                anchors.centerIn: parent
                                                width: Math.min(parent.width - 4, lbl.implicitWidth + 8)
                                                height: lbl.implicitHeight + 6
                                                radius: height / 2
                                                color: "transparent"
                                                border.width: tileItem.modelData === "timer" ? 1 : 0
                                                border.color: Theme.foreground
                                                Text {
                                                    id: lbl
                                                    anchors.centerIn: parent
                                                    text: tileItem.label
                                                    color: Theme.foreground
                                                    font.family: Theme.fontFamily
                                                    font.bold: true
                                                    font.pixelSize: tileItem.modelData === "music" ? Theme.fontSizeLg : (BarSettings.extraIds.indexOf(tileItem.modelData) >= 0 ? 9 : 10)
                                                }
                                            }
                                            // app tray: 2x2 tiles
                                            Grid {
                                                visible: tileItem.modelData === "apps"
                                                anchors.centerIn: parent
                                                columns: 2
                                                spacing: 3
                                                Repeater {
                                                    model: 4
                                                    delegate: Rectangle { width: 8; height: 8; radius: 2; color: Theme.foreground; opacity: 0.6 }
                                                }
                                            }

                                            MouseArea {
                                                id: grab
                                                anchors.fill: parent
                                                preventStealing: true
                                                hoverEnabled: true
                                                cursorShape: tileItem.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                                property real grabX: 0

                                                function finish() {
                                                    if (orderBox.dragId !== tileItem.modelData) return
                                                        orderBox.dragId = ""
                                                        if (JSON.stringify(orderBox.working) !== JSON.stringify(BarSettings.order))
                                                            BarSettings.setOrder(orderBox.working)
                                                }

                                                onEntered: orderBox.hoverId = tileItem.modelData
                                                onExited: if (orderBox.hoverId === tileItem.modelData) orderBox.hoverId = ""
                                                onPressed: (m) => {
                                                    grabX = m.x
                                                    tileItem.dragX = tileItem.slot * orderBox.step
                                                    orderBox.dragId = tileItem.modelData
                                                }
                                                onPositionChanged: (m) => {
                                                    if (!pressed || orderBox.dragId !== tileItem.modelData) return
                                                        var px = mapToItem(tiles, m.x, m.y).x
                                                        var maxX = (orderBox.working.length - 1) * orderBox.step
                                                        tileItem.dragX = Math.max(0, Math.min(maxX, px - grabX))
                                                        var target = Math.max(0, Math.min(orderBox.working.length - 1,
                                                                                          Math.round(tileItem.dragX / orderBox.step)))
                                                        if (target !== tileItem.slot) {
                                                            var w = orderBox.working.filter(function (x) { return x !== tileItem.modelData })
                                                            w.splice(target, 0, tileItem.modelData)
                                                            orderBox.working = w
                                                        }
                                                }
                                                onReleased: finish()
                                                onCanceled: finish()
                                            }
                                        }
                                    }
                                }
                            }

                            // Name of the hovered / dragged icon (fixed height so nothing jumps).
                            Text {
                                readonly property string shown: orderBox.dragId !== "" ? orderBox.dragId : orderBox.hoverId
                                text: shown === "" ? " " : (popup.iconNames[shown] ?? shown)
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // ---- reset ----
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        SectionLabel { text: "" }
                        GlassButton { text: "Reset bar settings"; onClicked: BarSettings.reset() }
                    }

                    Item { Layout.preferredHeight: 4 }
                }
            }
        }
    }

    // ============================================================
    // TOAST PAGE
    // ============================================================
    Component {
        id: toastPage

        ColumnLayout {
            spacing: 8

            // Fixed preview
            ToastPreview { Layout.fillWidth: true }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 10
                SectionLabel { text: "Placement" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Grid {
                        columns: 3
                        spacing: 6
                        Repeater {
                            model: [
                                { label: "Top left", value: "top-left" },
                                { label: "Top center", value: "top-center" },
                                { label: "Top right", value: "top-right" },
                                { label: "Bottom left", value: "bottom-left" },
                                { label: "Bottom center", value: "bottom-center" },
                                { label: "Bottom right", value: "bottom-right" }
                            ]
                            delegate: GlassButton {
                                required property var modelData
                                text: modelData.label
                                active: ToastSettings.placement === modelData.value
                                onClicked: ToastSettings.setPlacement(modelData.value)
                            }
                        }
                    }
                    Hint { text: "Where notification toasts appear on screen. Older toasts stack behind the newest one, away from the screen edge." }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 10
                SectionLabel { text: "Try it" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    GlassButton { text: "Send test notification"; onClicked: ToastSettings.sendTest() }
                    Hint { text: "Sends a real notification. It will not show while Do Not Disturb is on." }
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ============================================================
    // KEYBINDINGS PAGE
    // ============================================================
    Component {
        id: keybindsPage

        ColumnLayout {
            id: kb
            spacing: 8

            // ---- inline editor state ----
            property string editingId: ""
            property var draftMods: []
            property string draftKey: ""
            property string error: ""
            readonly property var editingDef: editingId === "" ? null : Keybinds.def(editingId)
            readonly property bool editingIsMod: editingDef ? editingDef.kind === "mod" : false

            function startEdit(id) {
                var p = Keybinds.parse(Keybinds.effective(id))
                editingId = id
                draftMods = p.mods
                draftKey = p.key
                error = ""
            }
            function cancelEdit() { editingId = ""; error = "" }
            function toggleMod(m) {
                var a = draftMods.slice()
                var i = a.indexOf(m)
                if (i >= 0) a.splice(i, 1); else a.push(m)
                    draftMods = Keybinds.sortMods(a)
                    error = ""
            }
            function currentCombo() {
                return editingIsMod ? draftMods.join(" + ") : Keybinds.compose(draftMods, draftKey)
            }
            function save() {
                var msg = Keybinds.setCombo(editingId, currentCombo())
                if (msg === "") cancelEdit(); else error = msg
            }
            function unbind() {
                Keybinds.setCombo(editingId, "")
                cancelEdit()
            }

            // The popup offers key events to the active page first. While a row
            // is being edited this swallows them: modifiers toggle chips, any
            // other key becomes the bound key, Esc cancels the edit.
            function handleKey(event) {
                if (editingId === "") return false
                    if (event.key === Qt.Key_Escape) { cancelEdit(); return true }
                    if (Keybinds.isModifierKey(event.key)) {
                        var m = Keybinds.modOfKey(event.key)
                        if (m !== "" && draftMods.indexOf(m) < 0) draftMods = Keybinds.sortMods(draftMods.concat([m]))
                            return true
                    }
                    if (editingIsMod) return true
                        var name = Keybinds.keyName(event.key)
                        if (name === "") { error = "That key can't be bound here."; return true }
                        var mods = draftMods.slice()
                        if ((event.modifiers & Qt.MetaModifier) && mods.indexOf("SUPER") < 0) mods.push("SUPER")
                            if ((event.modifiers & Qt.ControlModifier) && mods.indexOf("CTRL") < 0) mods.push("CTRL")
                                if ((event.modifiers & Qt.AltModifier) && mods.indexOf("ALT") < 0) mods.push("ALT")
                                    if ((event.modifiers & Qt.ShiftModifier) && mods.indexOf("SHIFT") < 0) mods.push("SHIFT")
                                        draftMods = Keybinds.sortMods(mods)
                                        draftKey = name
                                        error = ""
                                        return true
            }

            Hint {
                text: "Click a key to change it. Changes apply on their own: Hyprland reloads about a second after the last edit. Volume, brightness and mouse drag/resize binds are not editable here."
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

            Flickable {
                id: kbFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: -14; Layout.rightMargin: -14   // horizontal gutter only (hover-scaled buttons); top/bottom clip at the real edge
                clip: true
                contentWidth: width
                contentHeight: kbCol.implicitHeight + 8
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: kbCol
                    x: 14; y: 4
                    width: kbFlick.width - 28
                    spacing: 14

                    Repeater {
                        model: Keybinds.groups
                        delegate: ColumnLayout {
                            id: groupBox
                            required property string modelData
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: groupBox.modelData
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                                font.bold: true
                                Layout.bottomMargin: 2
                            }

                            Repeater {
                                model: Keybinds.defs.filter(function (d) { return d.group === groupBox.modelData })
                                delegate: ColumnLayout {
                                    id: bindRow
                                    required property var modelData
                                    readonly property string rid: modelData.id
                                    readonly property string combo: Keybinds.effective(rid)
                                    readonly property var clashes: Keybinds.conflictsOf(rid)
                                    readonly property bool editing: kb.editingId === rid
                                    Layout.fillWidth: true
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text {
                                                text: bindRow.modelData.label
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSize
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                visible: bindRow.clashes.length > 0
                                                text: "Also used by: " + bindRow.clashes.join(", ")
                                                color: "#e5484d"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                visible: bindRow.modelData.mode === "sbs"
                                                text: "Only active in SBS mode"
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                            }
                                            Text {
                                                visible: bindRow.modelData.mode === "normal"
                                                text: "Not active in SBS mode"
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeXs
                                            }
                                        }

                                        GlassButton {
                                            Layout.preferredWidth: 190
                                            implicitHeight: 30
                                            text: Keybinds.display(bindRow.combo)
                                            active: bindRow.editing
                                            onClicked: bindRow.editing ? kb.cancelEdit() : kb.startEdit(bindRow.rid)
                                        }

                                        GlassButton {
                                            Layout.preferredWidth: 64
                                            implicitHeight: 30
                                            text: "Reset"
                                            opacity: Keybinds.isOverridden(bindRow.rid) ? 1 : 0
                                            disabled: !Keybinds.isOverridden(bindRow.rid)
                                            onClicked: Keybinds.reset(bindRow.rid)
                                        }
                                    }

                                    // ---- inline editor ----
                                    Rectangle {
                                        visible: bindRow.editing
                                        Layout.fillWidth: true
                                        implicitHeight: editCol.implicitHeight + 20
                                        radius: Theme.radiusSm
                                        color: Theme.pillOffBg
                                        border.width: 1
                                        border.color: Theme.accentActive

                                        ColumnLayout {
                                            id: editCol
                                            anchors.fill: parent
                                            anchors.margins: 10
                                            spacing: 8

                                            Text {
                                                text: kb.editingIsMod
                                                ? "Pick the modifier(s). The number keys 1-0 are added automatically."
                                                : "Pick modifiers (or hold them), then press the key."
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSm
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }

                                            Row {
                                                spacing: 6
                                                Repeater {
                                                    model: Keybinds.modOrder
                                                    delegate: GlassButton {
                                                        required property string modelData
                                                        text: Keybinds.modLabels[modelData]
                                                        implicitHeight: 28
                                                        active: kb.draftMods.indexOf(modelData) >= 0
                                                        onClicked: kb.toggleMod(modelData)
                                                    }
                                                }
                                                Rectangle {
                                                    visible: !kb.editingIsMod
                                                    width: 150
                                                    height: 28
                                                    radius: Theme.radiusSm
                                                    color: "transparent"
                                                    border.width: 1
                                                    border.color: kb.draftKey === "" ? Theme.accentActive : Theme.borderMuted
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: kb.draftKey === "" ? "Press a key..." : Keybinds.display(kb.draftKey)
                                                        color: kb.draftKey === "" ? Theme.textDim : Theme.foreground
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: Theme.fontSize
                                                        font.bold: kb.draftKey !== ""
                                                    }
                                                }
                                            }

                                            Text {
                                                text: "Result: " + (kb.currentCombo() === "" ? "-" : Keybinds.display(kb.currentCombo()))
                                                color: Theme.foreground
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSm
                                            }

                                            Text {
                                                visible: kb.error !== ""
                                                text: kb.error
                                                color: "#e5484d"
                                                font.family: Theme.fontFamily
                                                font.pixelSize: Theme.fontSizeSm
                                                wrapMode: Text.WordWrap
                                                Layout.fillWidth: true
                                            }

                                            Row {
                                                spacing: 6
                                                GlassButton { text: "Save"; implicitHeight: 28; onClicked: kb.save() }
                                                GlassButton { text: "Unbind"; implicitHeight: 28; onClicked: kb.unbind() }
                                                GlassButton { text: "Cancel"; implicitHeight: 28; onClicked: kb.cancelEdit() }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        GlassButton { text: "Reset all keybindings"; onClicked: { kb.cancelEdit(); Keybinds.resetAll() } }
                    }

                    Item { Layout.preferredHeight: 4 }
                }
            }
        }
    }

    // ============================================================
    // FONT PAGE (was the standalone FontPickerPopup)
    // ============================================================
    Component { id: fontPage; FontSettingsPage {} }
    Component { id: displayPage; DisplayPage {} }
    Component { id: iconsPage; IconsSettingsPage {} }
    Component { id: popupsPage; PopupsSettingsPage {} }

    // ============================================================
    // THEME PAGE (surface styles + custom themes; see ThemeSettingsPage.qml)
    // ============================================================
    Component { id: themePage; ThemeSettingsPage {} }
}
