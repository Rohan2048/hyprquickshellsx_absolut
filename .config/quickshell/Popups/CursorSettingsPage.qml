import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Cursor: pick the cursor theme (Default, Bibata and every theme you add), its size, and
// add new themes from the file picker. Applies at once (hyprctl) and is remembered for the next login
// (see scripts/set-cursor.sh). List or Grid view is shared with the file pickers.
Item {
    id: page

    property bool adding: false
    property string deleteArm: ""
    readonly property string viewMode: PopupSettings.get("browser", "view", "list") === "grid" ? "grid" : "list"
    function setViewMode(m) { PopupSettings.put("browser", "view", m === "grid" ? "grid" : null) }

    function handleKey(event) {
        if (page.adding && event.key === Qt.Key_Escape) { page.adding = false; return true }
        return false
    }

    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    // one theme: its arrow, name, note, buttons
    component ThemeCard: Rectangle {
        id: card
        property var info: ({})
        property bool grid: false
        property string armName: ""
        signal removeClicked(string name)
        readonly property bool inUse: CursorThemes.effective === card.info.name
        readonly property bool armed: card.armName === card.info.name
        radius: Theme.radiusMd
        color: card.inUse ? Qt.rgba(Theme.accentActive.r, Theme.accentActive.g, Theme.accentActive.b, 0.18) : "transparent"
        border.width: 1
        border.color: card.inUse ? Theme.accentActive : Theme.borderMuted
        opacity: card.info.installed ? 1 : 0.55

        // the theme's own arrow (scripts/cursor-preview.py), a plain arrow until it exists
        Item {
            id: prev
            x: 10; y: card.grid ? 10 : (card.height - height) / 2
            width: card.grid ? 48 : 32
            height: width
            Image {
                id: pimg
                anchors.fill: parent
                source: CursorThemes.previewOf(card.info.name)
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: pimg.status !== Image.Ready
                text: "\u2196"
                color: card.inUse ? Theme.accentActive : Theme.foreground
                font.pixelSize: card.grid ? 30 : 20
            }
        }
        Column {
            x: card.grid ? 10 : prev.x + prev.width + 10
            y: card.grid ? prev.y + prev.height + 6 : 8
            width: card.grid ? card.width - 20 : card.width - x - 250
            spacing: 0
            Text {
                width: parent.width
                text: card.info.label
                elide: Text.ElideRight
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }
            Text {
                width: parent.width
                text: card.info.note
                elide: Text.ElideRight
                color: Theme.foreground
                opacity: 0.6
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSm
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10
            y: card.grid ? card.height - height - 8 : (card.height - height) / 2
            spacing: 6
            GlassButton {
                text: card.inUse ? "In use" : "Apply"
                active: card.inUse
                disabled: !card.info.installed
                onClicked: CursorThemes.apply(card.info.name)
            }
            GlassButton {
                visible: card.info.user && !card.info.special
                text: card.armed ? "Click to confirm" : "Remove"
                onClicked: card.removeClicked(card.info.name)
            }
        }
    }
    function removeTheme(n) {
        if (page.deleteArm === n) { page.deleteArm = ""; CursorThemes.remove(n) }
        else { page.deleteArm = n; armReset.restart() }
    }
    Timer { id: armReset; interval: 3000; onTriggered: page.deleteArm = "" }

    Loader {
        anchors.fill: parent
        active: page.adding
        z: 2
        sourceComponent: CursorAddBrowser {
            onPicked: (p) => { CursorThemes.install(p); page.adding = false }
            onCancelled: page.adding = false
        }
    }

    Flickable {
        id: flick
        visible: !page.adding
        anchors.fill: parent
        anchors.leftMargin: -14; anchors.rightMargin: -14   // horizontal gutter only (hover-scaled buttons); top/bottom clip at the real edge
        clip: true
        contentWidth: width
        contentHeight: col.implicitHeight + 8
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            x: 14; y: 4
            width: flick.width - 28
            spacing: 12

            Hint { text: "Choose the mouse cursor. It applies right away and is kept for the next login. Default is the system's own cursor, Bibata is the default theme; any theme you add is listed too." }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "Size"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    Layout.preferredWidth: 60
                }
                GlassSlider {
                    Layout.fillWidth: true; Layout.preferredHeight: 26
                    min: CursorThemes.minSize; max: CursorThemes.maxSize
                    value: CursorThemes.size
                    onValueCommitted: (v) => CursorThemes.setSize(v)
                }
                Text {
                    text: CursorThemes.size + " px"
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    Layout.preferredWidth: 52
                    horizontalAlignment: Text.AlignRight
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                GlassButton { text: "Add cursor theme"; active: true; onClicked: { CursorThemes.message = ""; page.adding = true } }
                GlassButton { text: "Refresh"; onClicked: CursorThemes.refresh() }
                Item { Layout.fillWidth: true }
                GlassButton { text: "List"; active: page.viewMode === "list"; onClicked: page.setViewMode("list") }
                GlassButton { text: "Grid"; active: page.viewMode === "grid"; onClicked: page.setViewMode("grid") }
            }
            Hint { visible: CursorThemes.message !== ""; text: CursorThemes.message }

            // list view
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6
                visible: page.viewMode === "list"
                Repeater {
                    model: page.viewMode === "list" ? CursorThemes.entries : []
                    delegate: ThemeCard {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        info: modelData
                        grid: false
                        armName: page.deleteArm
                        onRemoveClicked: (n) => page.removeTheme(n)
                    }
                }
            }
            // grid view
            Flow {
                id: gridFlow
                Layout.fillWidth: true
                spacing: 8
                visible: page.viewMode === "grid"
                readonly property int cols: Math.max(2, Math.floor((width + 8) / 200))
                readonly property real cw: Math.floor((width - (cols - 1) * 8) / cols)
                Repeater {
                    model: page.viewMode === "grid" ? CursorThemes.entries : []
                    delegate: ThemeCard {
                        required property var modelData
                        width: gridFlow.cw
                        height: 150
                        info: modelData
                        grid: true
                        armName: page.deleteArm
                        onRemoveClicked: (n) => page.removeTheme(n)
                    }
                }
            }

            Hint { text: "Each theme shows its own arrow. Themes in your own folders (~/.local/share/icons, ~/.icons) can be removed here; system themes can't." }
            Item { Layout.preferredHeight: 4 }
        }
    }
}
