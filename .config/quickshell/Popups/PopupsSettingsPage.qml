import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// "Popups" category of SettingsPopup: a row of sub-settings, one page each.
//   General            scale of every popup            (PopupsGeneralPage.qml)
//   Popup styles       one popup at a time: scale, corner radius, button size / radius / text offset, live preview (PopupsStylePage.qml)
//   Commands palette   placement, scale, add style     (PopupsCommandsPage.qml)
//   Shortcuts palette  placement, scale, trigger, add style (PopupsShortcutsPage.qml)
//   Applications       launcher style and view         (PopupsAppsPage.qml)
//   Clipboard history  Rofi or Quickshell list         (PopupsClipboardPage.qml)
//   Power & display    power menu / schedule / display toggle: style + scale (PopupsPowerPage.qml)
Item {
    id: page

    property string sub: "general"
    // The page actually on screen. Normally equal to `sub`; it only lags while Popup styles is being left.
    property string shownSub: "general"

    // The window widens for "Popup styles" only once that page has fully loaded AND stayed ready for a moment,
    // so it expands once, already finished, instead of widening while the preview is still loading.
    property bool styleReady: false
    // wide only while Popup styles is the chosen page: leaving it starts the shrink at once
    readonly property bool wantsWide: page.sub === "styles" && page.shownSub === "styles" && page.styleReady
    property real previewW: 600            // passed on to the Popup styles page

    // The page's normal (narrow) width. It is frozen while Popup styles is open and while the window is still
    // shrinking back (shrinkHold), so the next page is laid out at its final width and never reflows.
    property real baseW: 0
    property bool shrinkHold: false
    readonly property bool trackBase: page.sub !== "styles" && page.shownSub !== "styles" && !page.shrinkHold
    onWidthChanged: {
        if (page.width <= 0) return
            if (page.trackBase) page.baseW = page.width
                else if (page.shrinkHold) holdTimer.restart()      // still shrinking: wait until the width stops changing
    }
    Component.onCompleted: { if (page.width > 0) page.baseW = page.width }
    // width the Popup styles page will have once the window has widened: preview column + gap + divider + gap
    readonly property real styleTargetW: page.baseW + page.previewW + 25

    // ---- page opacity ----
    // Hiding is INSTANT both ways (entering Popup styles while it loads, and leaving it), because an animated
    // hide would leave the page visible for the length of the fade. Only fade-ins animate.
    property real fadeOp: 1
    function updateFade() {
        const hidden = page.shownSub === "styles" && (!page.styleReady || page.sub !== "styles")
        const entering = hidden && page.sub === "styles"
        const target = hidden ? 0 : 1
        if (entering) {
            fadeAnim.stop()
            page.fadeOp = 0
        } else if (page.fadeOp !== target) {
            fadeAnim.stop()
            fadeAnim.from = page.fadeOp
            fadeAnim.to = target
            fadeAnim.start()
        }
    }
    onShownSubChanged: page.updateFade()
    onStyleReadyChanged: page.updateFade()

    NumberAnimation {
        id: fadeAnim
        target: page
        property: "fadeOp"
        duration: 100
        easing.type: Easing.OutCubic
    }

    onSubChanged: {
        if (page.sub === "styles") {
            page.shownSub = "styles"
            page.updateFade()               // covers the case where shownSub did not change
            page.checkStyleReady()          // already loaded and ready (e.g. clicked again)
        } else if (page.shownSub === "styles") {
            // leaving Popup styles: hide it instantly, start the shrink, and show the next page right away
            // (laid out at the narrow width, fading in while the window shrinks)
            settleTimer.stop()
            fadeAnim.stop()
            page.fadeOp = 0
            page.shrinkHold = true
            holdTimer.restart()
            page.styleReady = false
            page.shownSub = page.sub
        } else {
            page.shownSub = page.sub
        }
    }

    readonly property var subs: [
        { id: "general", label: "General" },
        { id: "styles", label: "Popup styles" },
        { id: "commands", label: "Commands palette" },
        { id: "shortcuts", label: "Shortcuts palette" },
        { id: "apps", label: "Applications" },
        { id: "clipboard", label: "Clipboard history" },
        { id: "power", label: "Power & display" },
        { id: "wallpaper", label: "Wallpaper picker" },
        { id: "animscale", label: "Animation scale" }
    ]

    function handleKey(event) {
        const it = subLoader.item
        return (it && it.handleKey) ? it.handleKey(event) : false
    }

    // Starts (or cancels) the "stayed ready" countdown that gates the window widening.
    function checkStyleReady() {
        const it = subLoader.item
        if (page.sub === "styles" && page.shownSub === "styles" && it && it.ready === true && !page.styleReady)
            settleTimer.restart()
            else
                settleTimer.stop()
    }

    Timer {
        id: settleTimer
        interval: 60
        repeat: false
        onTriggered: {
            const it = subLoader.item
            if (page.sub === "styles" && page.shownSub === "styles" && it && it.ready === true)
                page.styleReady = true
        }
    }

    // the window has stopped changing width: the shrink is over, so the narrow width can be tracked again
    Timer {
        id: holdTimer
        interval: 150
        repeat: false
        onTriggered: {
            page.shrinkHold = false
            if (page.width > 0 && page.trackBase) page.baseW = page.width
        }
    }

    Component { id: generalPage; PopupsGeneralPage {} }
    Component { id: stylesPage; PopupsStylePage { previewW: page.previewW } }
    Component { id: commandsPage; PopupsCommandsPage {} }
    Component { id: shortcutsPage; PopupsShortcutsPage {} }
    Component { id: appsPage; PopupsAppsPage {} }
    Component { id: clipboardPage; PopupsClipboardPage {} }
    Component { id: powerPage; PopupsPowerPage {} }
    Component { id: wallpaperPage; PopupsPickerPage { pid: "wallpaper" } }
    Component { id: animscalePage; PopupsPickerPage { pid: "animscale" } }

    function pageFor(id) {
        if (id === "general") return generalPage
            if (id === "styles") return stylesPage
                if (id === "commands") return commandsPage
                    if (id === "shortcuts") return shortcutsPage
                        if (id === "apps") return appsPage
                            if (id === "clipboard") return clipboardPage
                                if (id === "power") return powerPage
                                    if (id === "wallpaper") return wallpaperPage
                                        if (id === "animscale") return animscalePage
                                            return null
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: page.subs
                delegate: GlassButton {
                    required property var modelData
                    text: modelData.label
                    active: page.sub === modelData.id
                    onClicked: page.sub = modelData.id
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

        // Clipped host: every page is laid out at its final width right away, and the window's widening /
        // shrinking just uncovers / clips it, so the middle section never reflows while the window changes size.
        Item {
            id: host
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            Loader {
                id: subLoader
                x: 0
                y: 0
                height: host.height
                width: page.shownSub === "styles"
                ? (page.baseW > 0 ? Math.max(host.width, page.styleTargetW) : host.width)
                : ((page.shrinkHold && page.baseW > 0) ? page.baseW : host.width)
                sourceComponent: page.pageFor(page.shownSub)
                opacity: page.fadeOp

                // covers a page that is already ready the moment it loads (no change signal fires then)
                onLoaded: page.checkStyleReady()

                Connections {
                    target: subLoader.item
                    ignoreUnknownSignals: true
                    function onReadyChanged() { page.checkStyleReady() }
                }
            }
        }
    }
}
