import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../Services"
import "../Widgets"
import "../Theme"

// In-shell replacement for the three rofi menus of scripts/commands-add.sh
// (group -> command -> direct / terminal). Used when Settings > Popups > Commands palette
// has Style = Quickshell. Opened by the + button through Commands.addDialogOpen, and it
// draws with the shell theme (GlassPanel, GlassButton) so it matches the rest of the shell.
PanelWindow {
    id: dlg

    readonly property bool shown: Commands.addDialogOpen
    property bool _closing: false
    readonly property int fadeMs: Animations.panelFadeDuration

    property string group: ""
    property bool terminal: false
    readonly property bool valid: group.trim() !== "" && cmdField.text.trim() !== ""

    visible: shown || _closing
    color: "transparent"
    exclusiveZone: 0
    // No anchors: the compositor centres the window. Margin around the panel for the scale-in.
    implicitWidth: 452
    implicitHeight: panel.implicitHeight + 24

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:command-add"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function close() { Commands.addDialogOpen = false }
    function submit() {
        if (!dlg.valid) return
            if (Commands.addEntry(dlg.group, cmdField.text, dlg.terminal)) dlg.close()
    }

    onShownChanged: {
        if (shown) {
            hideTimer.stop()
            _closing = false
            group = ""
            terminal = false
            cmdField.text = ""
            focusTimer.restart()
        } else {
            _closing = true
            hideTimer.restart()
        }
    }
    Timer { id: hideTimer; interval: dlg.fadeMs + 60; onTriggered: dlg._closing = false }
    Timer { id: focusTimer; interval: 60; onTriggered: groupField.forceActiveFocus() }

    ClickAwayCloser {
        targetWindows: [dlg]
        active: dlg.shown
        onDismissed: dlg.close()
    }

    component Field: TextField {
        implicitHeight: 32
        selectByMouse: true
        color: Theme.foreground
        placeholderTextColor: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
        background: Rectangle {
            radius: Theme.radiusSm
            color: "transparent"
            border.width: 1
            border.color: parent.activeFocus ? Theme.accentActive : Theme.borderMuted
        }
    }
    component FieldLabel: Text {
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSm
        font.bold: true
    }

    Item {
        id: root
        anchors.fill: parent
        anchors.margins: 12
        focus: dlg.shown
        opacity: dlg.shown ? 1 : 0
        scale: dlg.shown ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: dlg.fadeMs } }
        Behavior on scale {
            SpringAnimation {
                spring: Animations.panelSlideSpring
                damping: Animations.panelSlideDamping
                mass: Animations.panelSlideMass
            }
        }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Escape) { dlg.close(); event.accepted = true }
        }

        GlassPanel {
            id: panel
            anchors.fill: parent
            implicitHeight: col.implicitHeight + 32
            radius: PopupSettings.radiusOf("commands")

            ColumnLayout {
                id: col
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                GradientText {
                    text: "Add command"
                    font.family: Theme.fontFamily
                    font.bold: true
                    font.pixelSize: Theme.fontSizeLg
                }

                FieldLabel { text: "Group" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: Commands.groupNames.length > 0
                    Repeater {
                        model: Commands.groupNames
                        delegate: GlassButton {
                            required property string modelData
                            text: modelData
                            implicitHeight: 28
                            active: dlg.group === modelData
                            onClicked: { groupField.text = modelData; dlg.group = modelData }
                        }
                    }
                }
                Field {
                    id: groupField
                    Layout.fillWidth: true
                    placeholderText: Commands.groupNames.length > 0 ? "Pick one above, or type a new group" : "Group name"
                    onTextEdited: dlg.group = text
                    Keys.onReturnPressed: cmdField.forceActiveFocus()
                    Keys.onEnterPressed: cmdField.forceActiveFocus()
                }

                FieldLabel { text: "Command"; Layout.topMargin: 4 }
                Field {
                    id: cmdField
                    Layout.fillWidth: true
                    placeholderText: "e.g. sudo systemctl restart NetworkManager"
                    Keys.onReturnPressed: dlg.submit()
                    Keys.onEnterPressed: dlg.submit()
                }

                FieldLabel { text: "How to launch"; Layout.topMargin: 4 }
                Row {
                    spacing: 6
                    GlassButton { text: "Direct"; active: !dlg.terminal; onClicked: dlg.terminal = false }
                    GlassButton { text: "In terminal"; active: dlg.terminal; onClicked: dlg.terminal = true }
                }
                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSm
                    text: dlg.terminal ? "Opens your terminal with the command ready to run (you can edit it first)."
                    : "Runs the command in the background."
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    GlassButton { text: "Cancel"; onClicked: dlg.close() }
                    GlassButton {
                        text: "Add"
                        active: dlg.valid
                        disabled: !dlg.valid
                        onClicked: dlg.submit()
                    }
                }
            }
        }
    }
}
