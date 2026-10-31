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

    Component { id: generalPage; PopupsGeneralPage {} }
    Component { id: stylesPage; PopupsStylePage {} }
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

        Loader {
            id: subLoader
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: page.pageFor(page.sub)
        }
    }
}
