pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../Theme"
import "../Widgets"

// "Display" page of SettingsPopup (backend: Services/DisplaySettings.qml).
//
//  * Preview : every connected output with its current resolution, refresh
//              rate and scale. Click an output that is ON to edit it. Click an
//              output that is OFF to switch to it (asks for confirmation first).
//              Each external output has a three-dot menu: Extend / Mirror /
//              Use only this display (the choices of hdmi.sh). The laptop panel
//              gets "Use only this display" while another output is on.
//  * Edit    : resolution and refresh rate apply immediately; scale is staged
//              (Apply / Cancel). Every applied change is followed by a
//              "keep these settings?" countdown that reverts automatically.
//  * Reset   : preferred mode + automatic scale.
//  * Animations: Auto / 0.75x ... 2x (same setting as the Alt+R rofi picker).
Item {
    id: page

    property string confirmTarget: ""      // output waiting for Proceed / Cancel

    // Three-dot menu (drawn at page level so the scroll area cannot clip it).
    property string menuName: ""
    property real menuX: 0
    property real menuY: 0
    readonly property real menuW: 200
    readonly property var menuMon: DisplaySettings.byName(page.menuName)
    // Clicking outside the menu closes it but is NOT swallowed (no grab): the click
    // still reaches whatever is underneath. This remembers which menu that press just
    // closed so a click on its own three-dot button toggles it shut instead of reopening.
    property string justClosed: ""
    Timer { id: closeGuard; interval: 250; onTriggered: page.justClosed = "" }
    function closeMenuFromOutside() {
        page.justClosed = page.menuName
        page.menuName = ""
        closeGuard.restart()
    }
    function toggleMenu(anchorItem, m) {
        if (page.menuName === m.name || page.justClosed === m.name) { page.menuName = ""; page.justClosed = ""; return }
        const p = anchorItem.mapToItem(page, 0, anchorItem.height + 4)
        page.menuX = Math.max(0, Math.min(page.width - page.menuW, p.x + anchorItem.width - page.menuW))
        page.menuY = p.y
        page.menuName = m.name
    }
    function runMode(mode) {
        const n = page.menuName
        page.menuName = ""
        if (n === "") return
            if (mode === "only") page.confirmTarget = n
                else DisplaySettings.setMode(n, mode)
    }

    Component.onCompleted: DisplaySettings.active = true
    Component.onDestruction: DisplaySettings.active = false

    // Routed here by SettingsPopup; Esc cancels the confirmation card first.
    function handleKey(event) {
        if (event.key === Qt.Key_Escape) {
            if (page.menuName !== "") { page.menuName = ""; return true }
            if (page.confirmTarget !== "") { page.confirmTarget = ""; return true }
        }
        return false
    }

    readonly property var mon: DisplaySettings.current

    // Scale is staged: the slider only moves this value; nothing is applied
    // until Apply. -1 = nothing staged.
    property int stagedScale: -1
    readonly property int currentScalePct: page.mon ? Math.round(page.mon.scale * 100) : 100
    readonly property int shownScalePct: page.stagedScale >= 0 ? page.stagedScale : page.currentScalePct
    readonly property bool scaleDirty: page.stagedScale >= 0 && page.stagedScale !== page.currentScalePct

    Connections {
        target: DisplaySettings
        function onSelectedChanged() { page.stagedScale = -1 }
    }
    readonly property bool locked: DisplaySettings.pending !== null || DisplaySettings._busy

    function tileClicked(m) {
        page.menuName = ""
        if (!m.disabled) DisplaySettings.selected = m.name
            else page.confirmTarget = m.name
    }

    function modeLine(m) {
        if (m.disabled || m.w === 0) return "Off"
            return m.w + " \u00D7 " + m.h + "  @  " + DisplaySettings.fmtRate(m.rate)
    }

    function pickResolution(res) {
        const m = page.mon
        if (!m || page.locked) return
            let rate = res.rates[0]
            for (let i = 0; i < res.rates.length; i++)
                if (Math.abs(res.rates[i] - m.rate) < 0.1) { rate = res.rates[i]; break }
                DisplaySettings.apply(m.name, res.w, res.h, rate, m.scale)
    }

    function pickRate(rate) {
        const m = page.mon
        if (!m || page.locked) return
            DisplaySettings.apply(m.name, m.w, m.h, rate, m.scale)
    }

    // Slider released: stage the value (snapped to 5 %), do not apply.
    function stageScale(pct) {
        page.stagedScale = Math.max(50, Math.min(300, Math.round(pct / 5) * 5))
    }
    function cancelScale() { page.stagedScale = -1 }
    function applyScale() {
        const m = page.mon
        if (!m || page.locked || !page.scaleDirty) return
            const pct = page.stagedScale
            page.stagedScale = -1
            DisplaySettings.apply(m.name, m.w, m.h, Math.round(m.rate * 100) / 100, pct / 100)
    }

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

    // =====================================================================
    Flickable {
        id: flick
        anchors.fill: parent
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + (banner.visible ? banner.height + 8 : 0)
        boundsBehavior: Flickable.StopAtBounds

        // While the confirmation card is up, the page behind it fades back so the card
        // (same surface as every other popup) stays readable in both Transparent blur
        // and Opaque. The three-dot menu does NOT fade the page.
        opacity: page.confirmTarget !== "" ? 0.15
        : (DisplaySettings.pending !== null ? 0.3 : 1)
        Behavior on opacity { NumberAnimation { duration: 150 } }

        ColumnLayout {
            id: col
            width: flick.width
            spacing: 16

            // ---------------- preview ----------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 156
                radius: 8
                color: Theme.pillOffBg
                border.width: 1
                border.color: Theme.borderMuted

                Text {
                    visible: DisplaySettings.connectedCount === 0
                    anchors.centerIn: parent
                    text: DisplaySettings.loading ? "Reading displays..." : "No display detected"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 14

                    Repeater {
                        model: DisplaySettings.visibleMonitors

                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            readonly property bool isSel: tile.modelData.name === DisplaySettings.selected && !tile.modelData.disabled
                            readonly property real aspect: (tile.modelData.logicalH > 0)
                            ? tile.modelData.logicalW / tile.modelData.logicalH : 16 / 9
                            height: 112
                            width: Math.max(150, Math.min(230, Math.round(height * aspect)))
                            radius: 8
                            color: tileMouse.containsMouse ? Theme.hoverBgStrong : Theme.popupBg
                            border.width: tile.isSel ? 2 : 1
                            border.color: tile.isSel ? Theme.accentActive : Theme.borderMuted
                            opacity: tile.modelData.disabled ? 0.6 : 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Behavior on border.color { ColorAnimation { duration: 120 } }

                            Column {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: 8
                                width: parent.width - 16
                                spacing: 3

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: tile.modelData.name + "  \u00B7  " + (tile.modelData.internal ? "Laptop" : "External")
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: tile.modelData.model !== "" ? tile.modelData.model : tile.modelData.description
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: page.modeLine(tile.modelData)
                                    color: Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeSm
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: tile.modelData.disabled
                                    ? "Click to switch to this display"
                                    : (tile.modelData.mirrorOf !== ""
                                    ? "Mirror of " + tile.modelData.mirrorOf
                                    : "Scale " + DisplaySettings.fmtScale(tile.modelData.scale))
                                    color: tile.modelData.disabled ? Theme.accentActive : Theme.foreground
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeXs
                                }
                            }

                            MouseArea {
                                id: tileMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.tileClicked(tile.modelData)
                            }

                            // Three-dot menu: every external output; the laptop panel only
                            // while another output is on (nothing else to switch to).
                            Rectangle {
                                id: dots
                                visible: !tile.modelData.internal
                                || (!tile.modelData.disabled && DisplaySettings.enabledCount > 1)
                                z: 2
                                width: 24
                                height: 24
                                radius: Theme.radiusSm
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 6
                                color: (dotsMouse.containsMouse || page.menuName === tile.modelData.name)
                                ? Theme.hoverBgStrong : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 3
                                    Repeater {
                                        model: 3
                                        delegate: Rectangle { width: 3; height: 3; radius: 1.5; color: Theme.foreground }
                                    }
                                }
                                MouseArea {
                                    id: dotsMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: page.toggleMenu(dots, tile.modelData)
                                }
                            }
                        }
                    }
                }
            }

            // Several outputs on (extend / mirror): say which one the settings below edit.
            Hint {
                visible: DisplaySettings.enabledCount > 1 && page.mon !== null
                text: "More than one display is on. Editing: " + (page.mon ? page.mon.name : "")
                + ". Use the three-dot menu on a display to extend, mirror or use only that display."
            }

            // ---------------- resolution ----------------
            RowLayout {
                visible: page.mon !== null
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "Resolution" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: page.mon ? page.mon.resolutions : []
                        delegate: GlassButton {
                            required property var modelData
                            text: modelData.w + " \u00D7 " + modelData.h
                            active: page.mon && page.mon.w === modelData.w && page.mon.h === modelData.h
                            disabled: page.locked
                            onClicked: page.pickResolution(modelData)
                        }
                    }
                }
            }

            // ---------------- refresh rate ----------------
            RowLayout {
                visible: page.mon !== null
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "Refresh rate" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: {
                            const m = page.mon
                            if (!m) return []
                                for (let i = 0; i < m.resolutions.length; i++)
                                    if (m.resolutions[i].w === m.w && m.resolutions[i].h === m.h) return m.resolutions[i].rates
                                        return []
                        }
                        delegate: GlassButton {
                            required property var modelData
                            text: DisplaySettings.fmtRate(modelData)
                            active: page.mon && Math.abs(page.mon.rate - modelData) < 0.1
                            disabled: page.locked
                            onClicked: page.pickRate(modelData)
                        }
                    }
                }
            }

            // ---------------- scale (staged: Apply / Cancel) ----------------
            RowLayout {
                visible: page.mon !== null
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
                            enabled: !page.locked
                            min: 50
                            max: 300
                            value: page.shownScalePct
                            onValueCommitted: (v) => page.stageScale(v)
                        }
                        Text {
                            text: page.shownScalePct + "%"
                            color: page.scaleDirty ? Theme.accentActive : Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: page.scaleDirty
                            Layout.preferredWidth: 52
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                    RowLayout {
                        visible: page.scaleDirty
                        spacing: 8
                        GlassButton { text: "Apply"; active: true; disabled: page.locked; onClicked: page.applyScale() }
                        GlassButton { text: "Cancel"; onClicked: page.cancelScale() }
                        Hint { text: "Currently " + page.currentScalePct + "%. Apply, then choose Keep or Revert." }
                    }
                    Hint {
                        visible: !page.scaleDirty
                        text: "Scales everything on this display (the compositor's monitor scale). Hyprland may nudge it to a value that divides the resolution evenly; the result is shown here."
                    }
                }
            }

            // ---------------- animations ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "Animations" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: DisplaySettings.animOptions
                            delegate: GlassButton {
                                required property var modelData
                                text: modelData.label
                                active: DisplaySettings.animActive(modelData.id)
                                onClicked: DisplaySettings.setAnim(modelData.id)
                            }
                        }
                    }
                    Hint { text: "Same setting as Alt+R. Auto follows the refresh rate (rate \u00F7 60); 1\u00D7 is tuned for 60 Hz." }
                }
            }

            // ---------------- reset ----------------
            RowLayout {
                visible: page.mon !== null
                Layout.fillWidth: true
                spacing: 10
                SectionLabel { text: "" }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    GlassButton {
                        text: "Reset display"
                        disabled: page.locked
                        onClicked: { page.stagedScale = -1; DisplaySettings.reset(page.mon.name) }
                    }
                    Hint { text: "Back to this display's preferred resolution and refresh rate with automatic scale (what hyprland.lua asks for). You get Keep / Revert afterwards. Animation scale is not touched." }
                }
            }

            Text {
                visible: DisplaySettings.statusText !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: DisplaySettings.statusText
                color: Theme.accentActive
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }

            Hint { text: "Display changes apply to the running session (like Alt+S); a Hyprland restart goes back to hyprland.lua." }

            Item { Layout.preferredHeight: 4 }
        }
    }

    // ---------------- three-dot menu ----------------
    // Passive click-away: sees the press, closes the menu, then REJECTS the press so it
    // carries on to the item underneath (no grab, no overlay).
    MouseArea {
        visible: page.menuName !== ""
        anchors.fill: parent
        z: 20
        onPressed: (mouse) => { page.closeMenuFromOutside(); mouse.accepted = false }
    }
    GlassPanel {
        id: menuCard
        visible: page.menuName !== "" && page.menuMon !== null
        z: 21
        x: page.menuX
        y: page.menuY
        width: page.menuW
        height: menuCol.implicitHeight + 16

        Column {
            id: menuCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 8
            spacing: 6

            GlassButton {
                visible: page.menuMon !== null && !page.menuMon.internal
                width: parent.width
                text: "Extend"
                active: page.menuMon !== null && DisplaySettings.modeOf(page.menuMon) === "extend"
                disabled: page.locked
                onClicked: page.runMode("extend")
            }
            GlassButton {
                visible: page.menuMon !== null && !page.menuMon.internal
                width: parent.width
                text: "Mirror"
                active: page.menuMon !== null && DisplaySettings.modeOf(page.menuMon) === "mirror"
                disabled: page.locked
                onClicked: page.runMode("mirror")
            }
            GlassButton {
                width: parent.width
                text: "Use only this display"
                active: page.menuMon !== null && DisplaySettings.modeOf(page.menuMon) === "only"
                disabled: page.locked
                onClicked: page.runMode("only")
            }
        }
    }

    // ---------------- keep / revert banner ----------------
    GlassPanel {
        id: banner
        visible: DisplaySettings.pending !== null
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 48
        z: 5

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: "Keep these display settings? Reverting in "
                + (DisplaySettings.pending ? DisplaySettings.pending.secs : 0) + " s"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
            GlassButton { text: "Keep"; active: true; onClicked: DisplaySettings.keep() }
            GlassButton { text: "Revert"; onClicked: DisplaySettings.revert() }
        }
    }

    // ---------------- "switch display" confirmation (same GlassPanel surface as the rest) ----------------
    Item {
        id: dim
        visible: page.confirmTarget !== ""
        anchors.fill: parent
        z: 10

        MouseArea { anchors.fill: parent; hoverEnabled: true }   // swallow clicks

        GlassPanel {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 420)
            height: cardCol.implicitHeight + 32

            ColumnLayout {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 10

                Text {
                    text: "Switch display?"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeLg
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: "You are about to be connected to another screen (" + page.confirmTarget
                    + "). Only that display will be used, and the shell restarts for a moment while the change is applied."
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8
                    GlassButton { text: "Cancel"; onClicked: page.confirmTarget = "" }
                    GlassButton {
                        text: "Proceed"
                        active: true
                        onClicked: {
                            const t = page.confirmTarget
                            page.confirmTarget = ""
                            DisplaySettings.switchTo(t)
                        }
                    }
                }
            }
        }
    }
}
