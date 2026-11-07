import QtQuick
import QtQuick.Layouts
import "../Services"
import "../Theme"
import "../Widgets"

// Settings > Popups > Popup styles: pick one popup (or "All popups") and set how it looks, with a live preview
// that is drawn with the real buttons, so every change shows at once.
//   Popup          scale and panel corner radius                (not for "All popups")
//   Buttons        corner radius, width, height, text offset   (PopupSettings "buttons"; "All popups" = the
//                  default for every popup, a popup's own value wins over it)
//   Layout         Battery and Volume show their real content in the preview (PopupLayoutEditor): drag a piece to
//                  move it, drag a corner handle to scale it (never stretched), both pages side by side.
//                  Battery also has two optional mini graphs. The other popups still get the button style,
//                  corner radius and scale, and show the three button states.
Item {
    id: page

    // width of the preview column on the right. The settings window grows by exactly this (+ the gap and divider),
    // set from SettingsPopup so there is one number, not two.
    property real previewW: 600

    property string sel: "volume"                      // a popup id, or "all"
    // fully loaded and sized: the Settings window waits for this before it widens (see PopupsSettingsPage)
    readonly property bool ready: page.editable ? editor.settled : true
    property bool showMore: false                      // the exact-value sliders under the preview
    readonly property bool isAll: page.sel === "all"
    readonly property bool hasScale: {
        const l = PopupSettings.popups
        for (let i = 0; i < l.length; i++) if (l[i].id === page.sel) return true
            return false
    }
    readonly property var items: [{ id: "all", label: "All popups" }].concat(PopupSettings.radiusItems)

    // popups whose real content the preview can show and rearrange
    // popups whose real content is split out into a *Content.qml and shown (and arranged) in the preview
    readonly property var editableIds: ["battery", "volume", "wifi", "bluetooth", "notifications", "music", "commands", "powermenu", "schedule", "hdmi", "clipboard", "apps", "shortcuts"]
    readonly property bool editable: page.editableIds.indexOf(page.sel) >= 0
    readonly property int pageCount: (page.sel === "volume" || page.sel === "wifi" || page.sel === "bluetooth") ? 2 : 1
    readonly property var pageNameList: page.sel === "volume" ? ["Devices", "Output ports"] : (page.sel === "wifi" ? ["New networks", "Saved networks"] : (page.sel === "bluetooth" ? ["New devices", "Paired devices"] : []))
    readonly property string selEl: editable ? editor.selected : ""
    readonly property var elementLabels: ({
        percent: "Percentage", remaining: "Time remaining", turbo: "Turbo Mode", mode: "Light / Dark mode", sbs: "Go SBS",
        graphLevel: "Battery graph", graphEnergy: "Energy graph", prioritise: "Prioritise", optimise: "Optimise For",
        title: "Title", "default": "Default button", settings: "Settings button", mute: "Mute button", slider: "Volume slider",
        devices: "Device list", outputLabel: "Output device", ports: "Output ports"
    })
    function labelOf(id) { return page.elementLabels[id] ?? (page.editable ? editor.labelFor(id) : id) }

    function resetThis() {
        PopupSettings.clearButtonStyle(page.sel)
        if (!page.isAll) {
            PopupSettings.clearLayout(page.sel)
            PopupSettings.put("size", page.sel, null)
            PopupSettings.setScalePct(page.sel, 100)
            PopupSettings.setRadius(page.sel, PopupSettings.defaultRadius(page.sel))
        }
    }

    component Hint: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }
    component SectionLabel: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
        Layout.fillWidth: true
        Layout.topMargin: 2
    }

    // "label ---slider--- value [Reset]" for one button setting of the selected popup
    component ValRow: RowLayout {
        id: vr
        property string label: ""
        property string key: ""                         // r w h dx dy
        property string unit: "px"
        property bool signedValue: false
        readonly property var lim: PopupSettings.buttonLimits[vr.key]
        readonly property int cur: PopupSettings.buttonVal(page.sel, vr.key,
                                                           vr.key === "r" ? PopupSettings.defaultButtonRadius : PopupSettings.buttonDefaults[vr.key])
        readonly property bool isSet: PopupSettings.buttonValSet(page.sel, vr.key)
        Layout.fillWidth: true
        spacing: 10

        Text {
            text: vr.label
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            Layout.preferredWidth: 150
            elide: Text.ElideRight
        }
        GlassSlider {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            min: vr.lim[0]
            max: vr.lim[1]
            value: vr.cur
            onValueCommitted: (v) => PopupSettings.setButtonVal(page.sel, vr.key, v)
        }
        Text {
            text: (vr.signedValue && vr.cur > 0 ? "+" : "") + vr.cur + " " + vr.unit
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            Layout.preferredWidth: 64
            horizontalAlignment: Text.AlignRight
        }
        GlassButton {
            text: "Reset"
            implicitHeight: 26
            opacity: vr.isSet ? 1 : 0
            disabled: !vr.isSet
            onClicked: PopupSettings.clearButtonVal(page.sel, vr.key)
        }
    }

    PopupStub { id: stub; reqId: page.sel }
    Component { id: batteryContent; BatteryContent {} }
    Component { id: volumeContent; VolumeContent {} }
    Component { id: wifiContent; WifiContent { host: stub } }
    Component { id: bluetoothContent; BluetoothContent { host: stub } }
    Component { id: notificationsContent; NotificationsContent { host: stub } }
    Component { id: commandsContent; CommandsContent { host: stub } }
    Component { id: choiceContent; ChoiceContent { host: stub } }
    Component { id: clipboardContent; ClipboardContent { host: stub } }
    Component { id: appsContent; AppLauncherContent { host: stub } }
    Component { id: shortcutsContent; ShortcutPickerContent { host: stub } }
    Component { id: musicContent; MusicContent { host: stub } }


    RowLayout {
        anchors.fill: parent
        spacing: 12

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: col.implicitHeight + 8
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: col
                x: 14; y: 4
                width: flick.width - 28
                spacing: 12

                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: page.items
                        delegate: GlassButton {
                            required property var modelData
                            text: modelData.label
                            active: page.sel === modelData.id
                            onClicked: page.sel = modelData.id
                        }
                    }
                }

                // ---- the three button states, in this popup's style ----
                Rectangle {
                    visible: page.editable
                    Layout.fillWidth: true
                    implicitHeight: typesRow.implicitHeight + 20
                    radius: Theme.radiusMd
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.borderMuted
                    property string popupId: page.sel
                    RowLayout {
                        id: typesRow
                        x: 12; y: 10
                        spacing: Theme.gapSm
                        Text { text: "Buttons"; color: Theme.foreground; opacity: 0.7; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSm; font.bold: true }
                        GlassButton { text: "Button" }
                        GlassButton { text: "Active"; active: true }
                        GlassButton { text: "Hover"; forceHover: true }
                    }
                }

                // ---- Battery: the two mini graphs ----
                RowLayout {
                    visible: page.sel === "battery"
                    Layout.fillWidth: true
                    spacing: Theme.gapSm
                    GlassButton {
                        text: (PopupSettings.batteryGraphLevel ? "\u25CF " : "\u25CB ") + "Battery % today"
                        variant: "toggle"
                        active: PopupSettings.batteryGraphLevel
                        onClicked: PopupSettings.setBatteryGraph("level", !PopupSettings.batteryGraphLevel)
                    }
                    GlassButton {
                        text: (PopupSettings.batteryGraphEnergy ? "\u25CF " : "\u25CB ") + "Energy used today"
                        variant: "toggle"
                        active: PopupSettings.batteryGraphEnergy
                        onClicked: PopupSettings.setBatteryGraph("energy", !PopupSettings.batteryGraphEnergy)
                    }
                }
                // ---- reset ----
                RowLayout {
                    visible: page.editable
                    Layout.fillWidth: true
                    spacing: 6
                    GlassButton {
                        text: "Reset layout & size"
                        disabled: !PopupSettings.layoutChanged(page.sel) && !PopupSettings.sizeChanged(page.sel)
                        onClicked: { PopupSettings.clearLayout(page.sel); PopupSettings.put("size", page.sel, null) }
                    }
                }

                GlassButton {
                    visible: !page.isAll
                    text: page.showMore ? "Hide exact values" : "Exact values & button style"
                    onClicked: page.showMore = !page.showMore
                }
                ColumnLayout {
                    visible: page.isAll || page.showMore
                    Layout.fillWidth: true
                    spacing: 12
                    // ---- the popup ----
                    ScaleRow {
                        visible: !page.isAll && page.hasScale
                        popupId: page.sel
                        label: "Scale"
                    }
                    RadiusRow {
                        visible: !page.isAll
                        popupId: page.sel
                        label: "Corner radius"
                    }

                    // ---- its buttons ----
                    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.borderMuted }
                    ValRow { label: "Corner radius"; key: "r"; unit: "px" }
                    ValRow { label: "Width"; key: "w"; unit: "%" }
                    ValRow { label: "Height"; key: "h"; unit: "%" }
                    ValRow { label: "Text offset, horizontal"; key: "dx"; unit: "px"; signedValue: true }
                    ValRow { label: "Text offset, vertical"; key: "dy"; unit: "px"; signedValue: true }

                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    GlassButton { text: page.isAll ? "Reset button defaults" : "Reset this popup"; onClicked: page.resetThis() }
                }

                Item { Layout.preferredHeight: 4 }
            }
        }

        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: Theme.borderMuted }

        // ---- right column: the live preview, fixed width, never scrolls ----
        Item {
            id: pv
            Layout.preferredWidth: page.previewW
            Layout.minimumWidth: page.previewW
            Layout.maximumWidth: page.previewW
            Layout.fillHeight: true
            clip: true

            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 4
                spacing: 10

                PopupLayoutEditor {
                    id: editor
                    Layout.fillWidth: true
                    visible: page.editable
                    popupId: page.sel
                    canScale: page.hasScale
                    maxH: pv.height - hintText.implicitHeight - 20   // never taller than the column: no scrolling
                    pages: page.pageCount
                    pageNames: page.pageNameList
                    host: stub
                    content: ({ battery: batteryContent, volume: volumeContent, wifi: wifiContent, bluetooth: bluetoothContent,
                        notifications: notificationsContent, music: musicContent, commands: commandsContent,
                        powermenu: choiceContent, schedule: choiceContent, hdmi: choiceContent,
                        clipboard: clipboardContent, apps: appsContent, shortcuts: shortcutsContent })[page.sel] ?? null
                }
                // every other popup: a stand-in panel with the three button states
                Rectangle {
                    id: stage
                    visible: !page.editable
                    Layout.fillWidth: true
                    Layout.preferredHeight: 190
                    radius: Theme.radiusMd
                    color: Qt.rgba(0, 0, 0, 0.18)
                    border.width: 1
                    border.color: Theme.borderMuted
                    clip: true

                    Rectangle {
                        id: mock
                        property string popupId: page.isAll ? "" : page.sel
                        readonly property real want: page.isAll ? 1 : PopupSettings.scaleOf(page.sel)
                        width: 340
                        height: 130
                        anchors.centerIn: parent
                        scale: Math.min(mock.want, (stage.width - 24) / mock.width, (stage.height - 20) / mock.height)
                        transformOrigin: Item.Center
                        radius: page.isAll ? Theme.radiusMd : PopupSettings.radiusOf(page.sel)
                        color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.07)
                        border.width: 1
                        border.color: Theme.borderMuted

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 12
                            Text {
                                text: page.isAll ? "Every popup" : (PopupSettings.radiusItems.filter(function (i) { return i.id === page.sel })[0] ?? { label: page.sel }).label
                                color: Theme.foreground
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }
                            RowLayout {
                                spacing: Theme.gapSm
                                GlassButton { text: "Button" }
                                GlassButton { text: "Active"; active: true }
                                GlassButton { text: "Hover"; forceHover: true }
                            }
                        }
                    }
                }
                Text {
                    id: hintText
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.foreground
                    opacity: 0.6
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    text: page.editable
                    ? "Drag a button or piece to move it. Click one to stretch it by its handles (the text stays the same size) and to set its text alignment, size and position. On the popup itself: edge bars = width / height, ring = corner radius, dot = overall size."
                    : (page.isAll ? "Shape the buttons of every popup." : "This popup's pieces can't be arranged here yet; its buttons, radius and scale follow the options below.")
                }
            }
        }
    }
}
