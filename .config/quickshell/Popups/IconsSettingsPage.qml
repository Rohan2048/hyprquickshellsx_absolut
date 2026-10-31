import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// "Icons" page of SettingsPopup (backend: Services/IconSettings.qml).
//
//  * Preview          : every icon centred on a real themed bar strip, edge to edge
//                       (same GlassPanel + corner rule as the Bar page). Fixed at the top.
//  * Monochromize all : flat white icons in dark mode, flat black in light mode,
//                       whatever the text colour is.
//  * Per icon         : pick your own image with the file picker (png, jpg, svg, webp ...)
//                       and choose Follow all / On / Off for that icon. Includes every
//                       battery level (thresholds from the battery service) and the
//                       charging bolt.
Item {
    id: page

    // "bar" = the bar's icons (Settings > Icons), "lock" = the lock screen's (Settings > Lock screen > Icons)
    property string group: "bar"
    readonly property var slotList: IconSettings.slotsFor(page.group)

    property string browseId: ""            // icon being picked for ("" = list view)
    property bool previewDark: Theme.effectiveDark
    // Does the previewed mode match the shell's real mode?
    readonly property bool themed: page.previewDark === Theme.effectiveDark
    // The bar surface as the ACTIVE theme (built-in blur / opaque, or a custom theme) paints it
    // in the previewed mode, so Light and Dark both follow the theme, not just the current mode.
    readonly property var previewFill: {
        const d = page.previewDark
        if (Theme.customActive)
            return Theme.resolveFill(Theme.activeTheme.bar, d, Theme.activeTheme.adapt !== false)
            const c = Theme.opaque ? Theme._popupSurface(d)
            : (d ? Qt.rgba(0, 0, 0, 0.35) : Qt.rgba(1, 1, 1, 0.55))
            return { kind: "solid", color: c, avg: c, opacity: 1 }
    }
    readonly property color fillColor: page.previewFill.kind === "solid" ? page.previewFill.color : page.previewFill.avg
    // Stand-in for the wallpaper behind the bar when previewing the other mode (the real
    // surfaces are translucent, so they need something of that mode behind them).
    readonly property color backdrop: page.previewDark ? "#16141f" : "#efedf5"
    readonly property color edge: page.themed ? Theme.borderMuted
    : (page.previewDark ? Theme.color8 : Qt.rgba(0, 0, 0, 0.12))
    readonly property color tileColor: page.themed ? Theme.pillOffBg : page.fillColor
    readonly property real stripRadius: BarSettings.autohide ? (26) * BarSettings.roundnessPct / 100 : 0

    function handleKey(event) {
        if (event.key === Qt.Key_Escape && page.browseId !== "") { page.browseId = ""; return true }
        return false
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

    // ---------------- list ----------------
    ColumnLayout {
        anchors.fill: parent
        visible: page.browseId === ""
        spacing: 8

        // ---- preview (fixed, does not scroll) ----
        Item {
            id: strip
            Layout.fillWidth: true
            Layout.preferredHeight: 52

            readonly property int n: page.slotList.length
            readonly property real iconPx: 20
            // spread the icons out when there is room, squeeze when there is not
            readonly property real gap: Math.max(4, Math.min(14, (width - 32 - n * iconPx) / Math.max(1, n - 1)))

            // Bar surface, edge to edge, painted by the active theme in the previewed mode.
            // Same radius rule as the Bar page preview: docked = square, floating = pill
            // scaled by the corner radius setting.
            Rectangle {
                anchors.fill: parent
                visible: !page.themed
                radius: page.stripRadius
                color: page.backdrop
            }
            GlassPanel {
                anchors.fill: parent
                role: "bar"
                themeFill: page.previewFill
                radius: page.stripRadius
                border.color: page.edge
            }

            Row {
                anchors.centerIn: parent
                spacing: strip.gap
                Repeater {
                    model: page.slotList
                    delegate: ThemedIcon {
                        required property var modelData
                        iconId: modelData.id
                        dark: page.previewDark
                        size: strip.iconPx
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            GlassButton { text: "Dark"; active: page.previewDark; onClicked: page.previewDark = true }
            GlassButton { text: "Light"; active: !page.previewDark; onClicked: page.previewDark = false }
            Hint { Layout.leftMargin: 6; text: "Every icon above (on / off states, all battery levels and the charging bolt) in the chosen mode." }
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

            ColumnLayout {
                id: col
                x: 14; y: 4
                width: flick.width - 28
                spacing: 16

                // ---- monochromize all ----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    SectionLabel { text: "Monochromize all" }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Row {
                            spacing: 6
                            GlassButton { text: "On"; active: IconSettings.monoAll; onClicked: IconSettings.setAll(true) }
                            GlassButton { text: "Off"; active: !IconSettings.monoAll; onClicked: IconSettings.setAll(false) }
                        }
                        Hint { text: "Monochromize turns an icon into a flat white silhouette in dark mode and a flat black one in light mode, whatever the text colour is. Each icon below can follow this, or be forced On or Off." }
                        Hint { text: "Light and dark theme adaptation works best for SVG. For other image formats used as icons, real colour inversion is not possible: an image with a transparent background becomes a flat silhouette, and an opaque image becomes a solid block. PNG and other formats stay as they are when Monochromize is off. Preview before finalizing." }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.borderMuted }

                // ---- every icon ----
                Repeater {
                    model: page.slotList
                    delegate: RowLayout {
                        id: row
                        required property var modelData
                        readonly property string iid: row.modelData.id
                        readonly property string path: IconSettings.customPath(row.iid)
                        Layout.fillWidth: true
                        spacing: 10

                        // Tile: same surface as the preview strip, icon dead centre.
                        Rectangle {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            radius: Theme.radiusSm
                            color: page.themed ? "transparent" : page.backdrop
                            Rectangle {
                                anchors.fill: parent
                                radius: Theme.radiusSm
                                color: page.tileColor
                                border.width: 1
                                border.color: page.edge
                            }
                            ThemedIcon {
                                anchors.centerIn: parent
                                iconId: row.iid
                                dark: page.previewDark
                                size: 24
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: row.modelData.label
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }
                            Text {
                                Layout.fillWidth: true
                                elide: Text.ElideMiddle
                                text: row.path !== "" ? row.path.slice(row.path.lastIndexOf("/") + 1) : "Default icon"
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSm
                            }
                        }

                        GlassButton { text: "Browse..."; onClicked: page.browseId = row.iid }
                        GlassButton {
                            visible: row.path !== ""
                            text: "Reset"
                            onClicked: IconSettings.clearPath(row.iid)
                        }
                        Row {
                            spacing: 4
                            GlassButton {
                                text: "Follow"
                                active: IconSettings.modeOf(row.iid) === "inherit"
                                onClicked: IconSettings.setMode(row.iid, "inherit")
                            }
                            GlassButton {
                                text: "Mono"
                                active: IconSettings.modeOf(row.iid) === "on"
                                onClicked: IconSettings.setMode(row.iid, "on")
                            }
                            GlassButton {
                                text: "Colour"
                                active: IconSettings.modeOf(row.iid) === "off"
                                onClicked: IconSettings.setMode(row.iid, "off")
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    GlassButton { text: "Reset all icons"; onClicked: IconSettings.resetAll() }
                }

                Hint { text: "Mono: always flat white / black. Colour: never Monochromized (a built-in icon is tinted with the text colour as before; your own image keeps its colours). Follow: do whatever Monochromize all says. The chosen file is used where it is: if you move or delete it, the built-in icon comes back. Charging levels share the icon of their battery level; the bolt is its own icon." }

                Item { Layout.preferredHeight: 4 }
            }
        }
    }

    // ---------------- file picker ----------------
    Loader {
        anchors.fill: parent
        active: page.browseId !== ""
        sourceComponent: ImageBrowser {
            onPicked: (f) => { IconSettings.setPath(page.browseId, f); page.browseId = "" }
            onCancelled: page.browseId = ""
        }
    }
}
